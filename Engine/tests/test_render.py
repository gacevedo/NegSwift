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
