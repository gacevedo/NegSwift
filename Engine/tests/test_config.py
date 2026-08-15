"""Config load and override tests."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


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
