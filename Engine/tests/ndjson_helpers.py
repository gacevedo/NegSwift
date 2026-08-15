"""Shared NDJSON protocol helpers for pytest."""

from __future__ import annotations

import json
import socket
import subprocess
import sys
import threading
import time
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path

_ENGINE_ROOT = Path(__file__).resolve().parents[1]


def ndjson_request(method: str, params: dict | None = None, req_id: str = "test-1") -> dict:
    """One request on a fresh serve --stdio process (stdin closed after the line)."""
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


@contextmanager
def ndjson_stdio_session() -> Iterator[_StdioSession]:
    """Persistent serve --stdio subprocess for multi-request / cancel tests."""
    proc = subprocess.Popen(
        [sys.executable, "-m", "negswift_engine.main", "serve", "--stdio"],
        cwd=_ENGINE_ROOT,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )
    session = _StdioSession(proc)
    try:
        yield session
    finally:
        session.close()


class _StdioSession:
    def __init__(self, proc: subprocess.Popen[str]) -> None:
        self._proc = proc
        self._lock = threading.Lock()
        self._pending: dict[str, dict] = {}
        self._reader = threading.Thread(target=self._read_stdout, daemon=True)
        self._reader.start()

    def request(self, method: str, params: dict | None = None, req_id: str | None = None) -> dict:
        rid = req_id or f"req-{time.time_ns()}"
        line = json.dumps({"id": rid, "method": method, "params": params or {}})
        event = threading.Event()
        with self._lock:
            self._pending[rid] = {"event": event, "msg": None}
        assert self._proc.stdin is not None
        self._proc.stdin.write(line + "\n")
        self._proc.stdin.flush()
        if not event.wait(timeout=120):
            raise TimeoutError(f"no response for {rid}")
        with self._lock:
            msg = self._pending.pop(rid)["msg"]
        assert msg is not None
        return msg

    def close(self) -> None:
        if self._proc.stdin:
            self._proc.stdin.close()
        self._proc.wait(timeout=30)

    def _read_stdout(self) -> None:
        assert self._proc.stdout is not None
        for raw in self._proc.stdout:
            line = raw.strip()
            if not line:
                continue
            msg = json.loads(line)
            rid = msg.get("id")
            if rid is None:
                continue
            with self._lock:
                slot = self._pending.get(str(rid))
            if slot is not None:
                slot["msg"] = msg
                slot["event"].set()


def socket_request(sock_path: Path, method: str, params: dict | None = None, req_id: str = "sock-1") -> dict:
    payload = json.dumps({"id": req_id, "method": method, "params": params or {}}) + "\n"
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.connect(str(sock_path))
        client.sendall(payload.encode("utf-8"))
        chunks: list[bytes] = []
        while b"\n" not in b"".join(chunks):
            part = client.recv(65536)
            if not part:
                break
            chunks.append(part)
        line = b"".join(chunks).split(b"\n", 1)[0].decode("utf-8")
        return json.loads(line)
