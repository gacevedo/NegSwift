"""Render executor — single worker and per-path supersession."""

from __future__ import annotations

import threading
import time

from negswift_engine.jobs import JobCancelled, JobRegistry
from negswift_engine.render_executor import RenderExecutor


def test_executor_supersedes_active_same_path() -> None:
    """Second submit for the same path cancels the in-flight job, not only queued work."""
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


def test_render_cancel_before_resolve_config(monkeypatch, sample_tiff) -> None:
    from negswift_engine import render
    from negswift_engine.jobs import JobCancelled

    calls = {"resolve": 0}
    original_resolve = render.resolve_config

    def counting_resolve(path: str, overrides):
        calls["resolve"] += 1
        return original_resolve(path, overrides)

    cancel = threading.Event()

    def cancel_on_asset_switch(path: str) -> None:
        cancel.set()

    monkeypatch.setattr(render, "resolve_config", counting_resolve)
    monkeypatch.setattr(render, "_evict_source_cache_if_asset_changed", cancel_on_asset_switch)

    try:
        render.render_preview_png(str(sample_tiff), prefer_gpu=False, cancel=cancel)
        raise AssertionError("expected JobCancelled")
    except JobCancelled:
        pass
    assert calls["resolve"] == 0


def test_render_cancel_before_cached_file_hash(monkeypatch, sample_tiff) -> None:
    from negswift_engine import render
    from negswift_engine.jobs import JobCancelled

    calls = {"hash": 0}
    original_hash = render.cached_file_hash
    original_resolve = render.resolve_config
    cancel = threading.Event()

    def resolve_then_cancel(path: str, overrides):
        cancel.set()
        return original_resolve(path, overrides)

    def counting_hash(path: str) -> str:
        calls["hash"] += 1
        return original_hash(path)

    monkeypatch.setattr(render, "resolve_config", resolve_then_cancel)
    monkeypatch.setattr(render, "cached_file_hash", counting_hash)

    try:
        render.render_preview_png(str(sample_tiff), prefer_gpu=False, cancel=cancel)
        raise AssertionError("expected JobCancelled")
    except JobCancelled:
        pass
    assert calls["hash"] == 0


def test_render_cancel_before_load_linear_preview(monkeypatch, sample_tiff) -> None:
    from negswift_engine import render
    from negswift_engine.jobs import JobCancelled

    calls = {"load": 0}
    original_hash = render.cached_file_hash
    cancel = threading.Event()
    pm = render._preview_manager_instance()
    original_load = pm.load_linear_preview

    def hash_then_cancel(path: str) -> str:
        cancel.set()
        return original_hash(path)

    def counting_load(*args, **kwargs):
        calls["load"] += 1
        return original_load(*args, **kwargs)

    monkeypatch.setattr(render, "cached_file_hash", hash_then_cancel)
    monkeypatch.setattr(pm, "load_linear_preview", counting_load)

    try:
        render.render_preview_png(str(sample_tiff), prefer_gpu=False, cancel=cancel)
        raise AssertionError("expected JobCancelled")
    except JobCancelled:
        pass
    assert calls["load"] == 0
