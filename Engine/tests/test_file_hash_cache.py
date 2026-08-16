"""File hash cache (M12 Phase 1)."""

from __future__ import annotations

import time

from negswift_engine.file_hash_cache import cached_file_hash, clear_file_hash_cache


def test_cached_file_hash_returns_stable_digest(sample_tiff) -> None:
    clear_file_hash_cache()
    first = cached_file_hash(str(sample_tiff))
    second = cached_file_hash(str(sample_tiff))
    assert first == second
    assert len(first) > 8


def test_cached_file_hash_warm_call_is_fast(sample_tiff) -> None:
    clear_file_hash_cache()
    path = str(sample_tiff)
    cached_file_hash(path)
    start = time.perf_counter()
    cached_file_hash(path)
    elapsed_ms = (time.perf_counter() - start) * 1000.0
    assert elapsed_ms < 5.0
