"""Single-worker GPU queue with per-path render supersession."""

from __future__ import annotations

import collections
import threading
from collections.abc import Callable
from dataclasses import dataclass
from typing import Any

from negswift_engine.jobs import JobCancelled, JobRegistry
from negswift_engine.protocol import ProtocolError

ResultEmitter = Callable[[dict[str, Any]], None]
ErrorEmitter = Callable[[str, str], None]
WorkFn = Callable[[threading.Event], dict[str, Any]]


@dataclass
class _WorkItem:
    job_id: str
    path: str | None
    supersede_path: bool
    cancel: threading.Event
    run: WorkFn
    emit_ok: ResultEmitter
    emit_err: ErrorEmitter


class RenderExecutor:
    """Serialize render/export GPU work on one thread; coalesce stale queued renders per path."""

    def __init__(self, jobs: JobRegistry) -> None:
        self._jobs = jobs
        self._lock = threading.Lock()
        self._cond = threading.Condition(self._lock)
        self._queue: collections.deque[_WorkItem] = collections.deque()
        self._active: _WorkItem | None = None
        self._worker = threading.Thread(target=self._worker_loop, name="negswift-gpu-worker", daemon=True)
        self._worker.start()

    def submit(
        self,
        job_id: str,
        *,
        path: str | None,
        supersede_path: bool,
        run: WorkFn,
        emit_ok: ResultEmitter,
        emit_err: ErrorEmitter,
    ) -> threading.Event:
        cancel = self._jobs.register(job_id)
        item = _WorkItem(
            job_id=job_id,
            path=path,
            supersede_path=supersede_path,
            cancel=cancel,
            run=run,
            emit_ok=emit_ok,
            emit_err=emit_err,
        )
        with self._cond:
            if supersede_path and path:
                self._supersede_queued_path(path)
                if self._active is not None and self._active.path == path:
                    self._jobs.cancel(self._active.job_id)
            self._queue.append(item)
            self._cond.notify()
        return cancel

    def pending_count(self) -> int:
        with self._cond:
            return len(self._queue) + (1 if self._active else 0)

    def _supersede_queued_path(self, path: str) -> None:
        kept: collections.deque[_WorkItem] = collections.deque()
        while self._queue:
            item = self._queue.popleft()
            if item.path == path:
                item.cancel.set()
                self._jobs.discard(item.job_id)
                item.emit_err("CANCELLED", "Job superseded")
            else:
                kept.append(item)
        self._queue = kept

    def _worker_loop(self) -> None:
        while True:
            with self._cond:
                while not self._queue:
                    self._cond.wait()
                item = self._queue.popleft()
                self._active = item
            try:
                if item.cancel.is_set():
                    item.emit_err("CANCELLED", "Job cancelled")
                    continue
                try:
                    result = item.run(item.cancel)
                except JobCancelled:
                    item.emit_err("CANCELLED", "Job cancelled")
                    continue
                except ProtocolError as exc:
                    item.emit_err(exc.code, exc.message)
                    continue
                except Exception as exc:  # noqa: BLE001 — protocol boundary
                    item.emit_err("INTERNAL", str(exc))
                    continue
                if item.cancel.is_set():
                    item.emit_err("CANCELLED", "Job cancelled")
                    continue
                item.emit_ok(result)
            finally:
                with self._cond:
                    if self._active is item:
                        self._active = None
                    self._jobs.discard(item.job_id)
                    self._cond.notify_all()
