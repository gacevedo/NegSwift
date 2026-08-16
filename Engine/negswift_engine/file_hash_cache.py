"""In-process file hash cache — avoids re-reading head/tail on every render."""

from __future__ import annotations

import os
from pathlib import Path

from negpy.kernel.image.logic import calculate_file_hash

_hash_cache: dict[tuple[str, int, int], str] = {}


def _file_identity(path: str) -> tuple[str, int, int]:
    resolved = str(Path(path).resolve())
    stat = os.stat(resolved)
    return resolved, stat.st_mtime_ns, stat.st_size


def cached_file_hash(path: str) -> str:
    """Return ``calculate_file_hash`` result, cached by path + mtime + size."""
    key = _file_identity(path)
    cached = _hash_cache.get(key)
    if cached is not None:
        return cached
    digest = calculate_file_hash(path)
    _hash_cache[key] = digest
    return digest


def clear_file_hash_cache() -> None:
    _hash_cache.clear()
