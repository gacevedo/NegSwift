"""Process-mode autodetect tests."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import tifffile
from ndjson_helpers import ndjson_request
from negpy.services.assets.sidecar import sidecar_path_for

from negswift_engine.detect import detect_process_mode_dict


def _write_bw_tiff(path: Path) -> None:
    gray = np.linspace(0.1, 0.9, 128 * 128, dtype=np.float32).reshape(128, 128)
    rgb = np.stack([gray, gray, gray], axis=-1)
    tifffile.imwrite(path, (rgb * 65535).astype(np.uint16), photometric="rgb")


def test_detect_c41_orange_mask_tiff(sample_tiff: Path) -> None:
    result = detect_process_mode_dict(str(sample_tiff))
    assert result["skipped"] is False
    assert result["process_mode"] == "Color Negative"
    assert result["detected_mode"] == "Color Negative"


def test_detect_bw_monochrome_tiff(tmp_path: Path) -> None:
    path = tmp_path / "bw.tif"
    _write_bw_tiff(path)
    result = detect_process_mode_dict(str(path))
    assert result["skipped"] is False
    assert result["process_mode"] == "B&W Negative"
    assert result["detected_mode"] == "B&W Negative"


def test_detect_skips_when_sidecar_present(sample_tiff: Path) -> None:
    sidecar = Path(sidecar_path_for(str(sample_tiff)))
    sidecar.write_text(json.dumps({"process_mode": "Color Negative"}), encoding="utf-8")
    try:
        result = detect_process_mode_dict(str(sample_tiff))
        assert result == {"skipped": True, "reason": "has_sidecar"}
    finally:
        sidecar.unlink(missing_ok=True)


def test_detect_force_ignores_sidecar(sample_tiff: Path) -> None:
    sidecar = Path(sidecar_path_for(str(sample_tiff)))
    sidecar.write_text(json.dumps({"process_mode": "B&W Negative"}), encoding="utf-8")
    try:
        result = detect_process_mode_dict(str(sample_tiff), force=True)
        assert result["skipped"] is False
        assert result["process_mode"] == "Color Negative"
    finally:
        sidecar.unlink(missing_ok=True)


def test_detect_process_mode_protocol(sample_tiff: Path) -> None:
    msg = ndjson_request(
        "detect_process_mode",
        {"path": str(sample_tiff)},
        req_id="detect-1",
    )
    assert msg["ok"] is True
    assert msg["result"]["process_mode"] == "Color Negative"


def test_detect_process_mode_not_found() -> None:
    msg = ndjson_request(
        "detect_process_mode",
        {"path": "/no/such/scan.tif"},
        req_id="detect-missing",
    )
    assert msg["ok"] is False
    assert msg["error"]["code"] == "NOT_FOUND"
