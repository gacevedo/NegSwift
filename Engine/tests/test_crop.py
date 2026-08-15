"""Crop preview and geometry render tests."""

from __future__ import annotations

import pytest

from ndjson_helpers import ndjson_request

_CROP_CONFIG = {"manual_crop_rect": [0.25, 0.25, 0.75, 0.75]}


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
