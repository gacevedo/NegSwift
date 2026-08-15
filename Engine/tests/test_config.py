"""Config load, save, and override tests."""

from __future__ import annotations

import shutil
from pathlib import Path

from ndjson_helpers import ndjson_request
from negpy.domain.models import WorkspaceConfig


def test_load_config_defaults(sample_tiff: Path) -> None:
    msg = ndjson_request("load_config", {"path": str(sample_tiff)}, req_id="load-1")
    assert msg["ok"] is True
    config = msg["result"]["config"]
    assert config["process_mode"] == "Color Negative"
    assert config["density"] == 1.0
    assert config["grade"] == 100.0
    assert config["auto_exposure"] is True
    assert config["auto_normalize_contrast"] is True
    assert config["saturation"] == 1.0
    assert config["analysis_buffer"] == 0.05
    assert config["auto_density_uses_crop"] is True


def test_render_with_analysis_buffer(sample_tiff: Path) -> None:
    params = {
        "path": str(sample_tiff),
        "prefer_gpu": False,
        "config": {"analysis_buffer": 0.15, "auto_exposure": True},
    }
    msg = ndjson_request("render", params, req_id="render-buffer")
    assert msg["ok"] is True
    assert msg["result"]["width"] > 0


def test_render_bw_process_mode(sample_tiff: Path) -> None:
    params = {
        "path": str(sample_tiff),
        "prefer_gpu": False,
        "config": {"process_mode": "B&W Negative"},
    }
    msg = ndjson_request("render", params, req_id="render-bw")
    assert msg["ok"] is True
    assert msg["result"]["width"] > 0


def test_render_with_manual_exposure(sample_tiff: Path) -> None:
    params = {
        "path": str(sample_tiff),
        "prefer_gpu": False,
        "config": {
            "auto_exposure": False,
            "auto_normalize_contrast": False,
            "density": 1.4,
        },
    }
    msg = ndjson_request("render", params, req_id="render-manual")
    assert msg["ok"] is True
    assert msg["result"]["width"] > 0


def test_save_config_round_trip(sample_tiff: Path, tmp_path: Path) -> None:
    frame = tmp_path / "frame.tif"
    shutil.copy(sample_tiff, frame)
    overrides = {
        "density": 1.25,
        "wb_cyan": 0.1,
        "auto_exposure": False,
        "analysis_buffer": 0.18,
    }
    save_msg = ndjson_request(
        "save_config",
        {"path": str(frame), "config": overrides},
        req_id="save-1",
    )
    assert save_msg["ok"] is True
    sidecar_path = Path(save_msg["result"]["sidecar_path"])
    assert sidecar_path.exists()
    assert sidecar_path.suffix == ".negpy"

    load_msg = ndjson_request("load_config", {"path": str(frame)}, req_id="load-2")
    assert load_msg["ok"] is True
    loaded = load_msg["result"]["config"]
    assert loaded["density"] == 1.25
    assert loaded["wb_cyan"] == 0.1
    assert loaded["auto_exposure"] is False
    assert loaded["analysis_buffer"] == 0.18
    assert loaded["grade"] == 100.0


def test_save_config_merge_preserves_unset_fields(sample_tiff: Path, tmp_path: Path) -> None:
    frame = tmp_path / "frame.tif"
    shutil.copy(sample_tiff, frame)
    ndjson_request(
        "save_config",
        {"path": str(frame), "config": {"density": 1.1, "saturation": 0.8}},
        req_id="merge-save",
    )
    loaded = ndjson_request("load_config", {"path": str(frame)}, req_id="merge-load")["result"]["config"]
    assert loaded["density"] == 1.1
    assert loaded["saturation"] == 0.8
    assert loaded["grade"] == 100.0
    assert loaded["auto_exposure"] is True


def test_save_geometry_round_trip(sample_tiff: Path, tmp_path: Path) -> None:
    frame = tmp_path / "frame.tif"
    shutil.copy(sample_tiff, frame)
    overrides = {
        "rotation": 1,
        "fine_rotation": -2.5,
        "autocrop_ratio": "3:2",
        "manual_crop_rect": [0.1, 0.15, 0.9, 0.85],
    }
    save_msg = ndjson_request("save_config", {"path": str(frame), "config": overrides}, req_id="geo-save")
    assert save_msg["ok"] is True

    load_msg = ndjson_request("load_config", {"path": str(frame)}, req_id="geo-load")
    loaded = load_msg["result"]["config"]
    assert loaded["rotation"] == 1
    assert loaded["fine_rotation"] == -2.5
    assert loaded["autocrop_ratio"] == "3:2"
    assert loaded["manual_crop_rect"] == [0.1, 0.15, 0.9, 0.85]

    WorkspaceConfig.from_flat_dict(loaded)


def test_auto_density_uses_crop_round_trip(sample_tiff: Path, tmp_path: Path) -> None:
    frame = tmp_path / "frame.tif"
    shutil.copy(sample_tiff, frame)
    overrides = {
        "manual_crop_rect": [0.2, 0.2, 0.8, 0.8],
        "auto_density_uses_crop": False,
    }
    save_msg = ndjson_request(
        "save_config",
        {"path": str(frame), "config": overrides},
        req_id="meter-save",
    )
    assert save_msg["ok"] is True

    loaded = ndjson_request("load_config", {"path": str(frame)}, req_id="meter-load")["result"]["config"]
    assert loaded["manual_crop_rect"] == [0.2, 0.2, 0.8, 0.8]
    assert loaded["auto_density_uses_crop"] is False
    assert loaded.get("analysis_rect") in (None, [])

    WorkspaceConfig.from_flat_dict({k: v for k, v in loaded.items() if k != "auto_density_uses_crop"})
