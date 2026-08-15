"""Config load, save, and override tests."""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

from negpy.domain.models import WorkspaceConfig


def _request(method: str, params: dict | None = None, req_id: str = "cfg-1") -> dict:
    line = json.dumps({"id": req_id, "method": method, "params": params or {}})
    proc = subprocess.run(
        [sys.executable, "-m", "negswift_engine.main", "serve", "--stdio"],
        input=line + "\n",
        cwd=Path(__file__).resolve().parents[1],
        capture_output=True,
        text=True,
        check=True,
    )
    response_line = proc.stdout.strip().splitlines()[-1]
    return json.loads(response_line)


def test_load_config_defaults(sample_tiff: Path) -> None:
    msg = _request("load_config", {"path": str(sample_tiff)}, req_id="load-1")
    assert msg["ok"] is True
    config = msg["result"]["config"]
    assert config["process_mode"] == "C41"
    assert config["density"] == 1.0
    assert config["grade"] == 100.0
    assert config["auto_exposure"] is True
    assert config["auto_normalize_contrast"] is True
    assert config["saturation"] == 1.0


def test_render_bw_process_mode(sample_tiff: Path) -> None:
    params = {
        "path": str(sample_tiff),
        "prefer_gpu": False,
        "config": {"process_mode": "B&W"},
    }
    msg = _request("render", params, req_id="render-bw")
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
    msg = _request("render", params, req_id="render-manual")
    assert msg["ok"] is True
    assert msg["result"]["width"] > 0


def test_save_config_round_trip(sample_tiff: Path, tmp_path: Path) -> None:
    frame = tmp_path / "frame.tif"
    shutil.copy(sample_tiff, frame)
    overrides = {
        "density": 1.25,
        "wb_cyan": 0.1,
        "auto_exposure": False,
    }
    save_msg = _request(
        "save_config",
        {"path": str(frame), "config": overrides},
        req_id="save-1",
    )
    assert save_msg["ok"] is True
    sidecar_path = Path(save_msg["result"]["sidecar_path"])
    assert sidecar_path.exists()
    assert sidecar_path.suffix == ".negpy"

    load_msg = _request("load_config", {"path": str(frame)}, req_id="load-2")
    assert load_msg["ok"] is True
    loaded = load_msg["result"]["config"]
    assert loaded["density"] == 1.25
    assert loaded["wb_cyan"] == 0.1
    assert loaded["auto_exposure"] is False

def test_save_geometry_round_trip(sample_tiff: Path, tmp_path: Path) -> None:
    frame = tmp_path / "frame.tif"
    shutil.copy(sample_tiff, frame)
    overrides = {
        "rotation": 1,
        "fine_rotation": -2.5,
        "autocrop_ratio": "3:2",
        "manual_crop_rect": [0.1, 0.15, 0.9, 0.85],
    }
    save_msg = _request("save_config", {"path": str(frame), "config": overrides}, req_id="geo-save")
    assert save_msg["ok"] is True

    load_msg = _request("load_config", {"path": str(frame)}, req_id="geo-load")
    loaded = load_msg["result"]["config"]
    assert loaded["rotation"] == 1
    assert loaded["fine_rotation"] == -2.5
    assert loaded["autocrop_ratio"] == "3:2"
    assert loaded["manual_crop_rect"] == [0.1, 0.15, 0.9, 0.85]

    WorkspaceConfig.from_flat_dict(loaded)
