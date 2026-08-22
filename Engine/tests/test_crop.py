"""Crop preview and geometry render tests."""

from __future__ import annotations

import base64
import io

import numpy as np
import pytest
from ndjson_helpers import ndjson_request
from PIL import Image

_CROP_CONFIG = {"crop_rect": [0.25, 0.25, 0.75, 0.75], "crop_from_auto": False}


def _render_rgb(path: str, *, crop_preview_full: bool, config: dict | None = None) -> np.ndarray:
    params = {
        "path": path,
        "prefer_gpu": False,
        "crop_preview_full": crop_preview_full,
        "config": {**_CROP_CONFIG, **(config or {})},
    }
    msg = ndjson_request("render", params, req_id=f"crop-{'full' if crop_preview_full else 'applied'}")
    assert msg["ok"] is True
    png = base64.standard_b64decode(msg["result"]["png_base64"])
    return np.array(Image.open(io.BytesIO(png)))


def test_crop_preview_full_is_larger_than_applied_crop(sample_tiff) -> None:
    params = {
        "path": str(sample_tiff),
        "prefer_gpu": False,
        "config": _CROP_CONFIG,
    }
    full = ndjson_request("render", {**params, "crop_preview_full": True}, req_id="crop-full")
    cropped = ndjson_request("render", {**params, "crop_preview_full": False}, req_id="crop-applied")
    assert full["ok"] is True
    assert cropped["ok"] is True
    full_size = full["result"]["width"] * full["result"]["height"]
    cropped_size = cropped["result"]["width"] * cropped["result"]["height"]
    assert full_size > cropped_size
    assert full["result"]["width"] == pytest.approx(cropped["result"]["width"] * 2, rel=0.1)
    assert full["result"]["height"] == pytest.approx(cropped["result"]["height"] * 2, rel=0.1)


def test_crop_preview_full_matches_applied_crop_with_auto_exposure(sample_tiff) -> None:
    """Uncropped crop-tool preview must tone-match the applied crop (ROI-scoped metering)."""
    path = str(sample_tiff)
    full = _render_rgb(path, crop_preview_full=True, config={"auto_exposure": True})
    cropped = _render_rgb(path, crop_preview_full=False, config={"auto_exposure": True})
    fh, fw = full.shape[:2]
    ch, cw = cropped.shape[:2]
    y1, x1 = int(0.25 * fh), int(0.25 * fw)
    region = full[y1 : y1 + ch, x1 : x1 + cw]
    assert region.shape == cropped.shape
    np.testing.assert_allclose(region, cropped, atol=2)


def test_crop_preview_full_reports_detected_crop_rect(tmp_path) -> None:
    import tifffile

    path = tmp_path / "bordered.tif"
    rgb = np.full((120, 160, 3), 2000, dtype=np.uint16)
    rgb[20:100, 30:130, :] = 30000
    tifffile.imwrite(path, rgb, photometric="rgb")

    params = {
        "path": str(path),
        "prefer_gpu": False,
        "crop_preview_full": True,
        "config": {"crop_from_auto": True},
    }
    msg = ndjson_request("render", params, req_id="crop-detect")
    assert msg["ok"] is True
    detected = msg["result"]["metrics"].get("detected_crop_rect")
    assert detected is not None
    assert len(detected) == 4
    x1, y1, x2, y2 = detected
    assert 0.0 <= x1 < x2 <= 1.0
    assert 0.0 <= y1 < y2 <= 1.0
    assert x1 > 0.05
    assert y1 > 0.05
    assert x2 < 0.95
    assert y2 < 0.95


def test_crop_preview_full_omits_detected_crop_rect_when_disabled(sample_tiff) -> None:
    params = {
        "path": str(sample_tiff),
        "prefer_gpu": False,
        "crop_preview_full": False,
        "config": {"crop_from_auto": True},
    }
    msg = ndjson_request("render", params, req_id="crop-no-detect")
    assert msg["ok"] is True
    assert msg["result"]["metrics"].get("detected_crop_rect") is None


def test_rotation_swaps_preview_dimensions(sample_tiff) -> None:
    base = ndjson_request(
        "render",
        {"path": str(sample_tiff), "prefer_gpu": False, "config": {"rotation": 0}},
        req_id="rot-0",
    )
    rotated = ndjson_request(
        "render",
        {"path": str(sample_tiff), "prefer_gpu": False, "config": {"rotation": 1}},
        req_id="rot-1",
    )
    assert base["ok"] is True
    assert rotated["ok"] is True
    assert base["result"]["width"] == pytest.approx(rotated["result"]["height"], rel=0.05)
    assert base["result"]["height"] == pytest.approx(rotated["result"]["width"], rel=0.05)
