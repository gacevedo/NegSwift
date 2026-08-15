"""Unix domain socket transport tests."""

from __future__ import annotations

import subprocess
import sys
import time
from pathlib import Path

import pytest
from ndjson_helpers import _ENGINE_ROOT, socket_request


def test_socket_ping() -> None:
    sock_path = Path(f"/tmp/negswift-test-{time.time_ns()}.sock")
    proc = subprocess.Popen(
        [
            sys.executable,
            "-m",
            "negswift_engine.main",
            "serve",
            "--socket",
            str(sock_path),
        ],
        cwd=_ENGINE_ROOT,
        stderr=subprocess.PIPE,
    )
    try:
        for _ in range(100):
            if sock_path.exists():
                break
            time.sleep(0.1)
        if not sock_path.exists():
            err = proc.stderr.read().decode() if proc.stderr else ""
            pytest.fail(f"socket not created; engine stderr: {err!r}")
        msg = socket_request(sock_path, "ping", req_id="sock-ping")
        assert msg["ok"] is True
        assert msg["result"]["pong"] is True
    finally:
        proc.terminate()
        proc.wait(timeout=10)
