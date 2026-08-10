"""NDJSON protocol tests for serve --stdio."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


def _request(method: str, params: dict | None = None, req_id: str = "test-1") -> dict:
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


def test_ping() -> None:
    msg = _request("ping")
    assert msg["ok"] is True
    assert msg["result"]["pong"] is True


def test_info() -> None:
    msg = _request("info", req_id="info-1")
    assert msg["ok"] is True
    result = msg["result"]
    assert result["protocol_version"] == "0.1"
    assert "negswift_version" in result
    assert "negpy_version" in result


def test_unknown_method() -> None:
    msg = _request("not_a_method", req_id="bad-1")
    assert msg["ok"] is False
    assert msg["error"]["code"] == "INVALID_REQUEST"
