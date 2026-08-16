"""Read/write ``.negpy`` sidecars with NegSwift-only keys preserved."""

from __future__ import annotations

import json
import os
import tempfile
from typing import Any

from negpy.services.assets.sidecar import sidecar_path_for

_sidecar_cache: dict[tuple[str, int], dict[str, Any] | None] = {}


def _sidecar_cache_key(source_path: str) -> tuple[str, int]:
    sidecar_path = sidecar_path_for(source_path)
    if not os.path.exists(sidecar_path):
        return source_path, -1
    return source_path, os.stat(sidecar_path).st_mtime_ns


def _invalidate_sidecar_cache(source_path: str) -> None:
    stale = [key for key in _sidecar_cache if key[0] == source_path]
    for key in stale:
        del _sidecar_cache[key]


def clear_sidecar_cache() -> None:
    _sidecar_cache.clear()


def read_raw_sidecar(source_path: str) -> dict[str, Any] | None:
    key = _sidecar_cache_key(source_path)
    if key in _sidecar_cache:
        return _sidecar_cache[key]

    path = sidecar_path_for(source_path)
    if not os.path.exists(path):
        _sidecar_cache[key] = None
        return None
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        _sidecar_cache[key] = None
        return None
    _sidecar_cache[key] = data
    return data


def write_raw_sidecar(source_path: str, payload: dict[str, Any]) -> str:
    path = sidecar_path_for(source_path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    body = json.dumps(payload, default=str, indent=2)
    tmp_path = None
    try:
        with tempfile.NamedTemporaryFile(
            "w",
            dir=os.path.dirname(path),
            delete=False,
            suffix=".part",
            encoding="utf-8",
        ) as tmp:
            tmp_path = tmp.name
            tmp.write(body)
        os.replace(tmp_path, path)
    except Exception:
        if tmp_path is not None and os.path.exists(tmp_path):
            os.unlink(tmp_path)
        raise
    _invalidate_sidecar_cache(source_path)
    return path


def delete_sidecar(source_path: str) -> bool:
    """Remove the ``.negpy`` sidecar if present. Returns whether a file was deleted."""
    path = sidecar_path_for(source_path)
    if not os.path.exists(path):
        return False
    os.unlink(path)
    _invalidate_sidecar_cache(source_path)
    return True
