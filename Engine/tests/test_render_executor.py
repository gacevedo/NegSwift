"""Render executor — single worker and per-path supersession."""

from __future__ import annotations

import threading
import time

from negswift_engine.jobs import JobCancelled, JobRegistry
from negswift_engine.render_executor import RenderExecutor


def test_executor_supersedes_queued_same_path() -> None:
    jobs = JobRegistry()
    executor = RenderExecutor(jobs)
    first_started = threading.Event()
    release_first = threading.Event()
    results: dict[str, tuple[bool, str]] = {}

    def run_factory(tag: str):
        def run(cancel: threading.Event) -> dict[str, object]:
            if tag == "first":
                first_started.set()
                release_first.wait(timeout=5)
            if cancel.is_set():
                raise JobCancelled()
            return {"tag": tag}

        return run

    def emit_ok(job_id: str):
        def _emit(result: dict[str, object]) -> None:
            results[job_id] = (True, str(result["tag"]))

        return _emit

    def emit_err(job_id: str):
        def _emit(code: str, message: str) -> None:
            results[job_id] = (False, code)

        return _emit

    executor.submit(
        "first",
        path="/frames/a.tif",
        supersede_path=True,
        run=run_factory("first"),
        emit_ok=emit_ok("first"),
        emit_err=emit_err("first"),
    )
    assert first_started.wait(timeout=5)

    executor.submit(
        "second",
        path="/frames/a.tif",
        supersede_path=True,
        run=run_factory("second"),
        emit_ok=emit_ok("second"),
        emit_err=emit_err("second"),
    )
    release_first.set()

    deadline = time.time() + 5
    while time.time() < deadline:
        if results.keys() >= {"first", "second"}:
            break
        time.sleep(0.02)

    assert results["first"] == (False, "CANCELLED")
    assert results["second"] == (True, "second")


def test_render_cancel_before_hash(monkeypatch, sample_tiff) -> None:
    from negswift_engine import render
    from negswift_engine.jobs import JobCancelled

    calls = {"hash": 0}
    original_hash = render.cached_file_hash

    def counting_hash(path: str) -> str:
        calls["hash"] += 1
        return original_hash(path)

    monkeypatch.setattr(render, "cached_file_hash", counting_hash)

    cancel = threading.Event()
    cancel.set()
    try:
        render.render_preview_png(str(sample_tiff), prefer_gpu=False, cancel=cancel)
        raise AssertionError("expected JobCancelled")
    except JobCancelled:
        pass
    assert calls["hash"] == 0
