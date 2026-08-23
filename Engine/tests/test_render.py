"""Render CLI and protocol tests."""

from __future__ import annotations

import base64
import json
import shutil
import subprocess
import sys
import threading
from pathlib import Path


def _run(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, "-m", "negswift_engine.main", *args],
        cwd=Path(__file__).resolve().parents[1],
        capture_output=True,
        text=True,
        check=False,
    )


def test_render_cli_writes_png(sample_tiff: Path, tmp_path: Path) -> None:
    out = tmp_path / "preview.png"
    proc = _run("render", "--path", str(sample_tiff), "--out", str(out), "--cpu")
    assert proc.returncode == 0, proc.stderr
    assert out.exists()
    assert out.read_bytes()[:8] == b"\x89PNG\r\n\x1a\n"
    meta = json.loads(proc.stdout)
    assert meta["width"] > 0
    assert meta["height"] > 0
    assert abs(meta["width"] / meta["height"] - 48 / 32) < 0.05


def test_render_protocol(sample_tiff: Path) -> None:
    line = json.dumps({"id": "r1", "method": "render", "params": {"path": str(sample_tiff), "prefer_gpu": False}})
    proc = subprocess.run(
        [sys.executable, "-m", "negswift_engine.main", "serve", "--stdio"],
        input=line + "\n",
        cwd=Path(__file__).resolve().parents[1],
        capture_output=True,
        text=True,
        check=True,
    )
    msg = json.loads(proc.stdout.strip().splitlines()[-1])
    assert msg["ok"] is True
    result = msg["result"]
    assert result["width"] > 0
    assert result["height"] > 0
    assert result.get("preview_format", "png") == "png"
    png = base64.standard_b64decode(result["png_base64"])
    assert png[:8] == b"\x89PNG\r\n\x1a\n"


def test_render_protocol_jpeg(sample_tiff: Path) -> None:
    from ndjson_helpers import ndjson_request

    msg = ndjson_request(
        "render",
        {
            "path": str(sample_tiff),
            "prefer_gpu": False,
            "preview_format": "jpeg",
            "jpeg_quality": 90,
        },
        req_id="render-jpeg",
    )
    assert msg["ok"] is True, msg
    result = msg["result"]
    assert result["preview_format"] == "jpeg"
    assert "jpeg_base64" in result
    assert "png_base64" not in result
    jpeg = base64.standard_b64decode(result["jpeg_base64"])
    assert jpeg[:2] == b"\xff\xd8"


def test_render_fast_preview(sample_tiff: Path) -> None:
    from ndjson_helpers import ndjson_request

    msg = ndjson_request(
        "render",
        {
            "path": str(sample_tiff),
            "prefer_gpu": False,
            "fast_preview": True,
            "long_edge_px": 256,
        },
        req_id="render-fast-thumb",
    )
    assert msg["ok"] is True, msg
    result = msg["result"]
    assert result["width"] > 0
    assert result["height"] > 0
    png = base64.standard_b64decode(result["png_base64"])
    assert png[:8] == b"\x89PNG\r\n\x1a\n"


def _render_long_edge(result: dict) -> int:
    return max(result["width"], result["height"])


def test_render_long_edge_px_scales_output(large_tiff: Path) -> None:
    """Preview quality maps to render long edge — only visible when source exceeds the cap."""
    from ndjson_helpers import ndjson_request

    fast = ndjson_request(
        "render",
        {"path": str(large_tiff), "long_edge_px": 800, "prefer_gpu": False},
        req_id="render-le-800",
    )
    high = ndjson_request(
        "render",
        {"path": str(large_tiff), "long_edge_px": 1600, "prefer_gpu": False},
        req_id="render-le-1600",
    )
    assert fast["ok"] is True, fast
    assert high["ok"] is True, high

    fast_le = _render_long_edge(fast["result"])
    high_le = _render_long_edge(high["result"])
    assert fast_le < high_le
    assert 735 <= fast_le <= 850
    assert 1450 <= high_le <= 1650


def test_render_omitted_long_edge_defaults_to_standard(large_tiff: Path) -> None:
    from ndjson_helpers import ndjson_request

    explicit = ndjson_request(
        "render",
        {"path": str(large_tiff), "long_edge_px": 1600, "prefer_gpu": False},
        req_id="render-le-explicit",
    )
    default = ndjson_request(
        "render",
        {"path": str(large_tiff), "prefer_gpu": False},
        req_id="render-le-default",
    )
    assert explicit["ok"] is True
    assert default["ok"] is True
    assert _render_long_edge(explicit["result"]) == _render_long_edge(default["result"])


def test_concurrent_frame_switch_renders(sample_tiff: Path, tmp_path: Path) -> None:
    """Preview + thumbnail renders for different frames must not race on the GPU pool."""
    from ndjson_helpers import ndjson_stdio_session

    frame_a = tmp_path / "frame_a.tif"
    frame_b = tmp_path / "frame_b.tif"
    shutil.copy(sample_tiff, frame_a)
    shutil.copy(sample_tiff, frame_b)

    results: list[dict] = []
    errors: list[BaseException] = []

    def run_render(session, path: Path, req_id: str, *, long_edge_px: int | None) -> None:
        try:
            params: dict = {"path": str(path), "prefer_gpu": True}
            if long_edge_px is not None:
                params["long_edge_px"] = long_edge_px
            results.append(session.request("render", params, req_id=req_id))
        except BaseException as exc:  # noqa: BLE001
            errors.append(exc)

    with ndjson_stdio_session() as session:
        threads = [
            threading.Thread(
                target=run_render,
                args=(
                    session,
                    frame_a,
                    "preview-a",
                ),
                kwargs={"long_edge_px": None},
                daemon=True,
            ),
            threading.Thread(
                target=run_render,
                args=(
                    session,
                    frame_b,
                    "thumb-b",
                ),
                kwargs={"long_edge_px": 160},
                daemon=True,
            ),
        ]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=60)

    assert not errors
    assert len(results) == 2
    for msg in results:
        assert msg["ok"] is True, msg
        png = base64.standard_b64decode(msg["result"]["png_base64"])
        assert png[:8] == b"\x89PNG\r\n\x1a\n"


def test_render_reports_autocrop_metrics_when_armed(sample_tiff: Path) -> None:
    from ndjson_helpers import ndjson_request

    msg = ndjson_request(
        "render",
        {
            "path": str(sample_tiff),
            "prefer_gpu": False,
            "config": {"crop_from_auto": True, "auto_crop_enabled": True},
        },
        req_id="render-autocrop-metrics",
    )
    assert msg["ok"] is True, msg
    metrics = msg["result"].get("metrics") or {}
    # Tiny synthetic TIFF may not detect a border; when it does, rect and key are paired.
    if metrics.get("autocrop_resolved_rect") is not None:
        assert metrics.get("autocrop_resolved_key")


def test_open_include_splash_optional(sample_tiff: Path) -> None:
    from ndjson_helpers import ndjson_request

    msg = ndjson_request(
        "open",
        {"path": str(sample_tiff), "include_splash": True},
        req_id="open-splash",
    )
    assert msg["ok"] is True, msg
    result = msg["result"]
    assert result["width"] == 48
    if "splash_jpeg_base64" in result:
        assert result["splash_width"] > 0
        assert result["splash_height"] > 0


def test_render_job_cancelled_maps_to_cancelled_code(monkeypatch, sample_tiff: Path) -> None:
    """JobCancelled from cooperative cancel must not become RENDER_FAILED."""
    from negswift_engine.jobs import JobCancelled
    from negswift_engine.protocol import ProtocolError, _cmd_render

    def raise_cancelled(*_args, **_kwargs) -> dict:
        raise JobCancelled()

    monkeypatch.setattr("negswift_engine.protocol.render_preview_base64", raise_cancelled)

    try:
        _cmd_render({"path": str(sample_tiff), "prefer_gpu": False})
        raise AssertionError("expected ProtocolError")
    except ProtocolError as exc:
        assert exc.code == "CANCELLED"


def test_preview_load_passes_use_camera_wb(monkeypatch, sample_tiff: Path) -> None:
    """Preview decode must match export: camera WB unless linear_raw is enabled."""
    from negpy.services.rendering.preview_manager import PreviewManager

    from negswift_engine.render import render_preview_raster, reset_render_cache

    captured: dict[str, bool] = {}
    original = PreviewManager.load_linear_preview

    def spy(self, file_path, color_space=None, use_camera_wb=False, **kwargs):
        captured["use_camera_wb"] = use_camera_wb
        return original(self, file_path, color_space=color_space, use_camera_wb=use_camera_wb, **kwargs)

    monkeypatch.setattr(PreviewManager, "load_linear_preview", spy)
    reset_render_cache()
    render_preview_raster(str(sample_tiff), prefer_gpu=False)
    assert captured["use_camera_wb"] is True

    captured.clear()
    reset_render_cache()
    render_preview_raster(str(sample_tiff), config_overrides={"linear_raw": True}, prefer_gpu=False)
    assert captured["use_camera_wb"] is False
