"""Read/write ``.negpy`` sidecars with NegSwift-only keys preserved."""

from __future__ import annotations

import json
import os
import tempfile
from typing import Any

from negpy.services.assets.sidecar import sidecar_path_for


def read_raw_sidecar(source_path: str) -> dict[str, Any] | None:
    path = sidecar_path_for(source_path)
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        return None
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
    return path


def delete_sidecar(source_path: str) -> bool:
    """Remove the ``.negpy`` sidecar if present. Returns whether a file was deleted."""
    path = sidecar_path_for(source_path)
    if not os.path.exists(path):
        return False
    os.unlink(path)
    return True
