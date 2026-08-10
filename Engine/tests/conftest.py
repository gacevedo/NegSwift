"""Shared pytest fixtures."""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pytest
import tifffile


@pytest.fixture
def sample_tiff(tmp_path: Path) -> Path:
    """Small RGB TIFF NegPy loaders can decode."""
    path = tmp_path / "sample.tif"
    rgb = np.zeros((32, 48, 3), dtype=np.uint16)
    rgb[:, :, 0] = 40000
    rgb[:, :, 1] = 20000
    rgb[:, :, 2] = 10000
    tifffile.imwrite(path, rgb, photometric="rgb")
    return path
