"""CLI smoke tests."""

from __future__ import annotations

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


def test_info_json() -> None:
    proc = _run("info")
    assert proc.returncode == 0, proc.stderr
    payload = json.loads(proc.stdout)
    assert "negswift_version" in payload
    assert "negpy_version" in payload
    assert payload["negpy_version"] not in ("Unknown-dev", "unknown")
    assert "gpu_available" in payload


def test_open_sample_tiff(sample_tiff: Path) -> None:
    proc = _run("open", str(sample_tiff))
    assert proc.returncode == 0, proc.stderr
    payload = json.loads(proc.stdout)
    assert payload["path"] == str(sample_tiff)
    assert payload["width"] == 48
    assert payload["height"] == 32
    assert payload["has_sidecar"] is False
    assert len(payload["hash"]) > 8
