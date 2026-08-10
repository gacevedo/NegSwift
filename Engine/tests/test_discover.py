"""Discovery tests."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


def test_discover_folder(sample_tiff: Path, tmp_path: Path) -> None:
    folder = tmp_path / "roll"
    folder.mkdir()
    (folder / "frame_a.tif").write_bytes(sample_tiff.read_bytes())
    (folder / "notes.txt").write_text("skip", encoding="utf-8")
    (folder / "frame_b.tif").write_bytes(sample_tiff.read_bytes())

    proc = subprocess.run(
        [sys.executable, "-m", "negswift_engine.main", "discover", str(folder)],
        cwd=Path(__file__).resolve().parents[1],
        capture_output=True,
        text=True,
        check=True,
    )
    payload = json.loads(proc.stdout)
    names = [a["name"] for a in payload["assets"]]
    assert names == ["frame_a.tif", "frame_b.tif"]


def test_discover_protocol(sample_tiff: Path, tmp_path: Path) -> None:
    folder = tmp_path / "roll2"
    folder.mkdir()
    target = folder / "one.tif"
    target.write_bytes(sample_tiff.read_bytes())

    line = json.dumps({"id": "d1", "method": "discover", "params": {"paths": [str(folder)]}})
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
    assert len(msg["result"]["assets"]) == 1
    assert msg["result"]["assets"][0]["path"] == str(target)
