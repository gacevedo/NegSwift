"""Export protocol tests."""

from __future__ import annotations

from pathlib import Path

from ndjson_helpers import ndjson_request
from PIL import Image


def test_export_jpeg(sample_tiff, tmp_path: Path) -> None:
    dest = tmp_path / "out"
    msg = ndjson_request(
        "export",
        {
            "path": str(sample_tiff),
            "dest_dir": str(dest),
            "prefer_gpu": False,
            "export": {
                "export_fmt": "JPEG",
                "export_color_space": "sRGB",
                "export_resolution_mode": "original",
                "jpeg_quality": 90,
            },
        },
        req_id="export-jpeg",
    )
    assert msg["ok"] is True, msg
    result = msg["result"]
    out_path = Path(result["output_path"])
    assert out_path.exists()
    assert out_path.suffix.lower() in {".jpg", ".jpeg"}
    assert result["width"] > 0
    assert result["height"] > 0
    with Image.open(out_path) as img:
        assert img.width == result["width"]
        assert img.height == result["height"]


def test_export_tiff(sample_tiff, tmp_path: Path) -> None:
    dest = tmp_path / "out"
    msg = ndjson_request(
        "export",
        {
            "path": str(sample_tiff),
            "dest_dir": str(dest),
            "prefer_gpu": False,
            "export": {"export_fmt": "TIFF", "export_color_space": "sRGB"},
        },
        req_id="export-tiff",
    )
    assert msg["ok"] is True, msg
    out_path = Path(msg["result"]["output_path"])
    assert out_path.suffix.lower() in {".tif", ".tiff"}
    with Image.open(out_path) as img:
        assert img.width > 0


def test_export_applies_crop(sample_tiff, tmp_path: Path) -> None:
    dest = tmp_path / "out"
    full = ndjson_request(
        "export",
        {
            "path": str(sample_tiff),
            "dest_dir": str(dest / "full"),
            "prefer_gpu": False,
            "export": {"export_fmt": "JPEG", "export_color_space": "sRGB"},
        },
        req_id="export-full",
    )
    cropped = ndjson_request(
        "export",
        {
            "path": str(sample_tiff),
            "dest_dir": str(dest / "crop"),
            "prefer_gpu": False,
            "config": {"manual_crop_rect": [0.25, 0.25, 0.75, 0.75]},
            "export": {"export_fmt": "JPEG", "export_color_space": "sRGB"},
        },
        req_id="export-crop",
    )
    assert full["ok"] is True
    assert cropped["ok"] is True
    full_size = full["result"]["width"] * full["result"]["height"]
    crop_size = cropped["result"]["width"] * cropped["result"]["height"]
    assert crop_size < full_size


def test_export_missing_path(tmp_path: Path) -> None:
    msg = ndjson_request(
        "export",
        {"path": "/no/such/file.tif", "dest_dir": str(tmp_path), "prefer_gpu": False},
        req_id="export-missing",
    )
    assert msg["ok"] is False
    assert msg["error"]["code"] == "NOT_FOUND"
