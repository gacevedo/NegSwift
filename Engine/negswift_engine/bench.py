"""Engine performance scenarios for M12 baselines (NegSwift-local, no NegPy forks)."""

from __future__ import annotations

import json
import platform
import subprocess
import sys
import threading
import time
from collections.abc import Callable
from pathlib import Path
from typing import Any

from negswift_engine.export import export_asset
from negswift_engine.file_hash_cache import cached_file_hash
from negswift_engine.render import render_preview_png, reset_render_cache, resolve_config
from negswift_engine.sidecar_io import read_raw_sidecar

BENCHMARK_VERSION = 1
_ENGINE_ROOT = Path(__file__).resolve().parents[1]

TypeFn = Callable[[], Any]


def _ms_since(start: float) -> float:
    return (time.perf_counter() - start) * 1000.0


def _time_call(fn: TypeFn) -> tuple[Any, float]:
    start = time.perf_counter()
    result = fn()
    return result, _ms_since(start)


def machine_info() -> dict[str, Any]:
    return {
        "platform": platform.platform(),
        "processor": platform.processor() or platform.machine(),
        "python": platform.python_version(),
    }


def git_commit() -> str | None:
    try:
        proc = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            cwd=_ENGINE_ROOT.parent,
            capture_output=True,
            text=True,
            check=True,
        )
        return proc.stdout.strip() or None
    except (OSError, subprocess.CalledProcessError):
        return None


def run_scenarios(
    scan_path: str,
    *,
    second_path: str | None = None,
    prefer_gpu: bool = False,
    export_dir: str | None = None,
    long_edge_px: int | None = None,
) -> dict[str, float]:
    """Run timed engine scenarios; return flat dict of ``*_ms`` metrics."""
    path = str(Path(scan_path).resolve())
    alt = str(Path(second_path).resolve()) if second_path else path
    dest = export_dir or str(Path(path).parent / ".negswift_bench_export")
    render_kwargs: dict[str, Any] = {"prefer_gpu": prefer_gpu}
    if long_edge_px is not None:
        render_kwargs["long_edge_px"] = long_edge_px

    timings: dict[str, float] = {}

    _, timings["hash_ms"] = _time_call(lambda: cached_file_hash(path))
    _, timings["hash_warm_ms"] = _time_call(lambda: cached_file_hash(path))
    _, timings["sidecar_ms"] = _time_call(lambda: read_raw_sidecar(path))
    _, timings["resolve_config_ms"] = _time_call(lambda: resolve_config(path, None))

    reset_render_cache()
    _, timings["render_cold_ms"] = _time_call(lambda: render_preview_png(path, **render_kwargs))
    _, timings["render_warm_ms"] = _time_call(lambda: render_preview_png(path, **render_kwargs))

    config_change = {"density": 0.15}
    _, timings["render_config_change_ms"] = _time_call(
        lambda: render_preview_png(path, config_overrides=config_change, **render_kwargs)
    )

    reset_render_cache()
    render_preview_png(path, **render_kwargs)
    _, timings["frame_switch_ms"] = _time_call(lambda: render_preview_png(alt, **render_kwargs))

    reset_render_cache()
    render_preview_png(path, **render_kwargs)
    _, timings["export_ms"] = _time_call(
        lambda: export_asset(
            path,
            dest,
            prefer_gpu=prefer_gpu,
            overwrite=True,
            export_overrides={
                "export_fmt": "JPEG",
                "export_color_space": "sRGB",
                "export_resolution_mode": "original",
                "jpeg_quality": 90,
            },
        )
    )
    _, timings["export_then_preview_ms"] = _time_call(lambda: render_preview_png(path, **render_kwargs))

    protocol = _protocol_timings(path, prefer_gpu=prefer_gpu, long_edge_px=long_edge_px)
    timings.update(protocol)

    return timings


def build_report(
    scan_path: str,
    *,
    profile: str,
    second_path: str | None = None,
    prefer_gpu: bool = False,
    export_dir: str | None = None,
    long_edge_px: int | None = None,
) -> dict[str, Any]:
    """Full JSON report for ``bench_render.py`` and pytest."""
    timings = run_scenarios(
        scan_path,
        second_path=second_path,
        prefer_gpu=prefer_gpu,
        export_dir=export_dir,
        long_edge_px=long_edge_px,
    )
    resolved = str(Path(scan_path).resolve())
    if profile == "synthetic_large":
        resolved = "synthetic:2000x1500"
    return {
        "version": BENCHMARK_VERSION,
        "profile": profile,
        "captured_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "commit": git_commit(),
        "machine": machine_info(),
        "scan_path": resolved,
        "prefer_gpu": prefer_gpu,
        "long_edge_px": long_edge_px,
        "timings_ms": timings,
    }


def compare_to_baseline(
    report: dict[str, Any],
    baseline: dict[str, Any],
    *,
    tolerance: float = 2.0,
) -> list[str]:
    """Return human-readable regression messages; empty if within tolerance."""
    regressions: list[str] = []
    base_timings = baseline.get("timings_ms", {})
    actual = report.get("timings_ms", {})
    for key, base_ms in base_timings.items():
        if key not in actual:
            regressions.append(f"missing metric {key}")
            continue
        actual_ms = float(actual[key])
        if base_ms <= 0:
            continue
        ratio = actual_ms / float(base_ms)
        if ratio > tolerance:
            regressions.append(f"{key}: {actual_ms:.1f} ms > {base_ms:.1f} ms baseline ({ratio:.2f}x)")
    return regressions


class _StdioSession:
    """Minimal persistent serve --stdio client for protocol timing."""

    def __init__(self) -> None:
        self._proc = subprocess.Popen(
            [sys.executable, "-m", "negswift_engine.main", "serve", "--stdio"],
            cwd=_ENGINE_ROOT,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        self._lock = threading.Lock()
        self._pending: dict[str, dict[str, Any]] = {}
        self._reader = threading.Thread(target=self._read_stdout, daemon=True)
        self._reader.start()

    def request(self, method: str, params: dict[str, Any] | None = None, req_id: str | None = None) -> dict[str, Any]:
        rid = req_id or f"bench-{time.time_ns()}"
        line = json.dumps({"id": rid, "method": method, "params": params or {}})
        event = threading.Event()
        with self._lock:
            self._pending[rid] = {"event": event, "msg": None}
        assert self._proc.stdin is not None
        self._proc.stdin.write(line + "\n")
        self._proc.stdin.flush()
        if not event.wait(timeout=180):
            raise TimeoutError(f"no response for {rid}")
        with self._lock:
            msg = self._pending.pop(rid)["msg"]
        assert msg is not None
        return msg

    def close(self) -> None:
        if self._proc.stdin:
            self._proc.stdin.close()
        self._proc.wait(timeout=60)

    def _read_stdout(self) -> None:
        assert self._proc.stdout is not None
        for raw in self._proc.stdout:
            line = raw.strip()
            if not line:
                continue
            msg = json.loads(line)
            rid = msg.get("id")
            if rid is None:
                continue
            with self._lock:
                slot = self._pending.get(str(rid))
            if slot is not None:
                slot["msg"] = msg
                slot["event"].set()


def _protocol_timings(path: str, *, prefer_gpu: bool, long_edge_px: int | None) -> dict[str, float]:
    params: dict[str, Any] = {"path": path, "prefer_gpu": prefer_gpu}
    if long_edge_px is not None:
        params["long_edge_px"] = long_edge_px

    session = _StdioSession()
    try:
        ping_msg, ping_ms = _time_call(lambda: session.request("ping", req_id="bench-ping"))
        assert ping_msg.get("ok") is True, ping_msg

        cold_msg, cold_ms = _time_call(lambda: session.request("render", params, req_id="bench-render-cold"))
        assert cold_msg.get("ok") is True, cold_msg

        warm_msg, warm_ms = _time_call(lambda: session.request("render", params, req_id="bench-render-warm"))
        assert warm_msg.get("ok") is True, warm_msg
    finally:
        session.close()

    return {
        "protocol_ping_ms": ping_ms,
        "protocol_render_cold_ms": cold_ms,
        "protocol_render_warm_ms": warm_ms,
    }
