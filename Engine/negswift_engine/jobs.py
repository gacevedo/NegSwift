"""In-flight render/export jobs — cooperative cancel via request id."""

from __future__ import annotations

import threading
from dataclasses import dataclass, field


class JobCancelled(Exception):
    """Raised when a worker observes a cancel flag before returning."""


@dataclass
class _Job:
    cancel: threading.Event = field(default_factory=threading.Event)


class JobRegistry:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._jobs: dict[str, _Job] = {}

    def register(self, job_id: str) -> threading.Event:
        job = _Job()
        with self._lock:
            self._jobs[job_id] = job
        return job.cancel

    def cancel(self, job_id: str) -> bool:
        with self._lock:
            job = self._jobs.get(job_id)
        if job is None:
            return False
        job.cancel.set()
        return True

    def discard(self, job_id: str) -> None:
        with self._lock:
            self._jobs.pop(job_id, None)

    def pending_count(self) -> int:
        with self._lock:
            return len(self._jobs)
