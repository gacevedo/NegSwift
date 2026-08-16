"""Render CLI and protocol tests."""

from __future__ import annotations

import base64
import json
import subprocess
import sys
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
    assert 750 <= fast_le <= 850
    assert 1550 <= high_le <= 1650


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
