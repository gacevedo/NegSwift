"""S11: autocrop detect-once over the engine protocol."""

from __future__ import annotations

from pathlib import Path

import numpy as np
import tifffile
from ndjson_helpers import ndjson_request


def _holder_tiff(path: Path, h: int = 240, w: int = 360) -> None:
    img = np.ones((h, w, 3), dtype=np.float32)
    img[round(0.12 * h) : round(0.88 * h), round(0.10 * w) : round(0.90 * w)] = 0.05
    tifffile.imwrite(path, (img * 65535.0 + 0.5).astype(np.uint16), photometric="rgb")


def test_second_render_does_not_redetect(tmp_path: Path) -> None:
    path = tmp_path / "holder.tif"
    _holder_tiff(path)
    first = ndjson_request(
        "render",
        {
            "path": str(path),
            "prefer_gpu": False,
            "config": {"crop_from_auto": True, "auto_crop_enabled": True},
        },
        req_id="s11-first",
    )
    assert first["ok"] is True, first
    metrics = first["result"].get("metrics") or {}
    rect = metrics.get("autocrop_resolved_rect")
    key = metrics.get("autocrop_resolved_key")
    assert rect is not None and len(rect) == 4
    assert key

    second = ndjson_request(
        "render",
        {
            "path": str(path),
            "prefer_gpu": False,
            "config": {
                "crop_from_auto": True,
                "crop_rect": rect,
                "crop_detect_key": key,
            },
        },
        req_id="s11-second",
    )
    assert second["ok"] is True, second
    assert (second["result"].get("metrics") or {}).get("autocrop_resolved_rect") is None
    assert second["result"]["width"] == first["result"]["width"]
    assert second["result"]["height"] == first["result"]["height"]


def test_open_suggests_crop_when_armed(tmp_path: Path) -> None:
    path = tmp_path / "holder.tif"
    _holder_tiff(path)
    msg = ndjson_request(
        "open",
        {"path": str(path), "config": {"crop_from_auto": True}},
        req_id="s11-open",
    )
    assert msg["ok"] is True, msg
    rect = msg["result"].get("suggested_crop_rect")
    assert rect is not None and len(rect) == 4
    assert msg["result"].get("crop_detect_key")
