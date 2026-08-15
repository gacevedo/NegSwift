"""NegSwift metering preference mapping."""

from __future__ import annotations

from negswift_engine.metering import (
    FULL_FRAME_ANALYSIS_RECT,
    negpy_flat_for_pipeline,
    negpy_flat_for_save,
)


def test_crop_metering_uses_inset_analysis_rect() -> None:
    flat = {
        "manual_crop_rect": [0.0, 0.0, 1.0, 1.0],
        "auto_density_uses_crop": True,
        "analysis_buffer": 0.1,
    }
    out = negpy_flat_for_pipeline(flat)
    assert "auto_density_uses_crop" not in out
    assert out["analysis_rect"] == (0.1, 0.1, 0.9, 0.9)


def test_crop_metering_off_sets_full_frame_analysis_rect() -> None:
    flat = {
        "manual_crop_rect": [0.1, 0.1, 0.9, 0.9],
        "auto_density_uses_crop": False,
    }
    out = negpy_flat_for_pipeline(flat)
    assert out["analysis_rect"] == FULL_FRAME_ANALYSIS_RECT
    assert out["manual_crop_rect"] == [0.1, 0.1, 0.9, 0.9]


def test_save_does_not_persist_wire_analysis_rect() -> None:
    flat = {
        "manual_crop_rect": [0.1, 0.1, 0.9, 0.9],
        "auto_density_uses_crop": True,
        "analysis_rect": (0.2, 0.2, 0.8, 0.8),
    }
    out = negpy_flat_for_save(flat)
    assert "auto_density_uses_crop" not in out
    assert "analysis_rect" not in out
