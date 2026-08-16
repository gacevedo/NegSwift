"""NegSwift sidecar read/write helpers."""

from __future__ import annotations

import shutil
from pathlib import Path

from negswift_engine.sidecar_io import delete_sidecar, read_raw_sidecar, write_raw_sidecar


def test_write_and_read_raw_sidecar_round_trip(sample_tiff: Path, tmp_path: Path) -> None:
    frame = tmp_path / "frame.tif"
    shutil.copy(sample_tiff, frame)
    payload = {"density": 1.3, "auto_density_uses_crop": False}
    sidecar_path = write_raw_sidecar(str(frame), payload)
    assert sidecar_path.endswith(".negpy")
    assert read_raw_sidecar(str(frame)) == payload


def test_delete_sidecar_reports_presence(sample_tiff: Path, tmp_path: Path) -> None:
    frame = tmp_path / "frame.tif"
    shutil.copy(sample_tiff, frame)
    assert delete_sidecar(str(frame)) is False
    write_raw_sidecar(str(frame), {"density": 1.1})
    assert delete_sidecar(str(frame)) is True
    assert delete_sidecar(str(frame)) is False
