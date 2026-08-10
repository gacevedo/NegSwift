"""Load optional JSON config overrides from a file."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any


def load_config_overrides(path: str | None) -> dict[str, Any] | None:
    if not path:
        return None
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise TypeError("config JSON must be an object")
    return data
