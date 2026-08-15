"""NDJSON transport — stdio and Unix domain socket."""

from __future__ import annotations

import json
import os
import socket
import sys
import threading
from collections.abc import Callable
from pathlib import Path
from typing import Any, BinaryIO, TextIO

from negswift_engine.jobs import JobCancelled, JobRegistry
from negswift_engine.protocol import ProtocolError, dispatch

_ASYNC_METHODS = frozenset({"render", "export"})


class NDJSONServer:
    """One NDJSON request line in; one response line out. Long jobs run off the read loop."""

    def __init__(self, write_line: Callable[[str], None]) -> None:
        self._write_line = write_line
        self._write_lock = threading.Lock()
        self._jobs = JobRegistry()

    def handle_message(self, raw: str) -> None:
        req_id: Any = None
        try:
            msg = json.loads(raw)
            if not isinstance(msg, dict):
                raise ProtocolError("INVALID_REQUEST", "Request must be a JSON object")
            req_id = msg.get("id")
            method = msg.get("method")
            if not isinstance(method, str):
                raise ProtocolError("INVALID_REQUEST", "Missing or invalid method")
            params = msg.get("params") or {}
            if not isinstance(params, dict):
                raise ProtocolError("INVALID_REQUEST", "params must be an object")

            if method == "cancel":
                self._cmd_cancel(req_id, params)
                return

            job_id = _job_id(req_id)
            if method in _ASYNC_METHODS and job_id is not None:
                self._run_async(job_id, req_id, method, params)
                return

            result = dispatch(method, params)
            self._emit_ok(req_id, result)
        except ProtocolError as exc:
            self._emit_err(req_id, exc.code, exc.message)
        except json.JSONDecodeError:
            self._emit_err(req_id, "INVALID_REQUEST", "Malformed JSON")
        except Exception as exc:  # noqa: BLE001 — protocol boundary
            self._emit_err(req_id, "INTERNAL", str(exc))

    def run_stdio(self, stream: TextIO | None = None) -> None:
        """Serve until stdin EOF; drain async workers before return (one-shot subprocess friendly)."""
        src = stream or sys.stdin
        for raw in src:
            line = raw.strip()
            if line:
                self.handle_message(line)
        self.drain()

    def drain(self) -> None:
        while self._jobs.pending_count() > 0:
            threading.Event().wait(0.05)

    def _cmd_cancel(self, req_id: Any, params: dict[str, Any]) -> None:
        job_id = params.get("job_id")
        if not isinstance(job_id, str) or not job_id:
            raise ProtocolError("INVALID_REQUEST", "params.job_id is required")
        cancelled = self._jobs.cancel(job_id)
        self._emit_ok(req_id, {"cancelled": cancelled})

    def _run_async(self, job_id: str, req_id: Any, method: str, params: dict[str, Any]) -> None:
        cancel = self._jobs.register(job_id)

        def worker() -> None:
            try:
                if cancel.is_set():
                    raise JobCancelled()
                result = dispatch(method, params)
                if cancel.is_set():
                    raise JobCancelled()
                self._emit_ok(req_id, result)
            except JobCancelled:
                self._emit_err(req_id, "CANCELLED", "Job cancelled")
            except ProtocolError as exc:
                self._emit_err(req_id, exc.code, exc.message)
            except Exception as exc:  # noqa: BLE001
                self._emit_err(req_id, "INTERNAL", str(exc))
            finally:
                self._jobs.discard(job_id)

        threading.Thread(target=worker, name=f"negswift-{method}-{job_id}", daemon=True).start()

    def _emit_ok(self, req_id: Any, result: dict[str, Any]) -> None:
        self._emit({"id": req_id, "ok": True, "result": result})

    def _emit_err(self, req_id: Any, code: str, message: str) -> None:
        self._emit({"id": req_id, "ok": False, "error": {"code": code, "message": message}})

    def _emit(self, payload: dict[str, Any]) -> None:
        line = json.dumps(payload, separators=(",", ":")) + "\n"
        with self._write_lock:
            self._write_line(line)


def _job_id(req_id: Any) -> str | None:
    if req_id is None:
        return None
    text = str(req_id)
    return text if text else None


def serve_stdio() -> None:
    def write_line(line: str) -> None:
        sys.stdout.write(line)
        sys.stdout.flush()

    NDJSONServer(write_line).run_stdio()


def serve_socket(path: str) -> None:
    """Listen on a Unix domain socket; one client connection per accepted session."""
    sock_path = Path(path)
    path_len = len(os.fsencode(sock_path))
    if path_len >= 104:
        raise OSError(
            f"Unix socket path too long ({path_len} bytes, max 103): {sock_path}"
        )
    sock_path.parent.mkdir(parents=True, exist_ok=True)
    if sock_path.exists():
        sock_path.unlink()

    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        server.bind(str(sock_path))
        os.chmod(sock_path, 0o600)
        server.listen(8)
        while True:
            conn, _addr = server.accept()
            threading.Thread(target=_serve_connection, args=(conn,), daemon=True).start()
    finally:
        server.close()
        if sock_path.exists():
            sock_path.unlink()


def _serve_connection(conn: socket.socket) -> None:
    buffer = b""
    write_lock = threading.Lock()

    def write_line(line: str) -> None:
        data = line.encode("utf-8")
        with write_lock:
            conn.sendall(data)

    ndjson = NDJSONServer(write_line)

    try:
        while True:
            chunk = conn.recv(4096)
            if not chunk:
                break
            buffer += chunk
            while b"\n" in buffer:
                raw, buffer = buffer.split(b"\n", 1)
                line = raw.decode("utf-8").strip()
                if line:
                    ndjson.handle_message(line)
        ndjson.drain()
    finally:
        try:
            conn.close()
        except OSError:
            pass


def serve_stdio_binary(stdin: BinaryIO, stdout: BinaryIO) -> None:
    """Test helper: binary stdin/stdout NDJSON session."""

    def write_line(line: str) -> None:
        stdout.write(line.encode("utf-8"))
        stdout.flush()

    buffer = b""
    ndjson = NDJSONServer(write_line)
    while True:
        chunk = stdin.read(4096)
        if not chunk:
            break
        buffer += chunk
        while b"\n" in buffer:
            raw, buffer = buffer.split(b"\n", 1)
            line = raw.decode("utf-8").strip()
            if line:
                ndjson.handle_message(line)
    ndjson.drain()
