"""Discover supported scan files under folders or paths."""

from __future__ import annotations

import os
from typing import Any

from negpy.infrastructure.loaders.constants import SUPPORTED_RAW_EXTENSIONS, is_ir_sidecar_path

_SUPPORTED = tuple(sorted(SUPPORTED_RAW_EXTENSIONS, key=len, reverse=True))


def _is_supported_file(path: str) -> bool:
    lower = path.lower()
    return lower.endswith(_SUPPORTED)


def discover_assets(paths: list[str]) -> list[dict[str, Any]]:
    """List image assets under paths. One directory level only — matches NegPy desktop discovery."""
    discovered: list[str] = []
    for path in paths:
        if os.path.isdir(path):
            try:
                for name in os.listdir(path):
                    full = os.path.join(path, name)
                    if os.path.isfile(full) and _is_supported_file(full):
                        discovered.append(full)
            except OSError:
                continue
        elif os.path.isfile(path) and _is_supported_file(path):
            discovered.append(path)

    discovered = list(dict.fromkeys(discovered))
    discovered = [p for p in discovered if not is_ir_sidecar_path(p)]
    discovered.sort(key=lambda p: os.path.basename(p).lower())

    return [{"path": p, "name": os.path.basename(p)} for p in discovered]
