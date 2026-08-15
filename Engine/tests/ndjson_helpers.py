"""Shared NDJSON protocol helpers for pytest."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

_ENGINE_ROOT = Path(__file__).resolve().parents[1]


def ndjson_request(method: str, params: dict | None = None, req_id: str = "test-1") -> dict:
    line = json.dumps({"id": req_id, "method": method, "params": params or {}})
    proc = subprocess.run(
        [sys.executable, "-m", "negswift_engine.main", "serve", "--stdio"],
        input=line + "\n",
        cwd=_ENGINE_ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    response_line = proc.stdout.strip().splitlines()[-1]
    return json.loads(response_line)
