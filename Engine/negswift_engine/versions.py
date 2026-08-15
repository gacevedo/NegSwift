"""Resolve pinned upstream NegPy version for info/protocol responses."""

from __future__ import annotations

import importlib.metadata
from pathlib import Path


def negpy_version() -> str:
    """Installed package version (pyproject/VERSION pin), not negpy.__version__ dev fallback."""
    try:
        return importlib.metadata.version("negpy")
    except importlib.metadata.PackageNotFoundError:
        pass

    import negpy

    attr = getattr(negpy, "__version__", "")
    if attr and attr != "Unknown-dev":
        return attr

    # Editable submodule: VERSION is at repo root, negpy/__init__.py only checks negpy/VERSION.
    root = Path(negpy.__file__).resolve().parent.parent
    version_file = root / "VERSION"
    if version_file.is_file():
        return version_file.read_text().strip()

    return attr or "unknown"
