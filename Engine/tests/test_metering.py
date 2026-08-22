"""NegSwift metering preference mapping."""

from __future__ import annotations

from negswift_engine.metering import (
    FULL_FRAME_ANALYSIS_RECT,
    default_auto_density_uses_crop,
    negpy_flat_for_pipeline,
    negpy_flat_for_save,
    negswift_sidecar_extras,
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
    assert out["crop_from_auto"] is False
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


def test_negswift_sidecar_extras_keeps_only_known_keys() -> None:
    flat = {"auto_density_uses_crop": False, "density": 1.2, "analysis_buffer": 0.1}
    assert negswift_sidecar_extras(flat) == {"auto_density_uses_crop": False}


def test_default_auto_density_uses_crop() -> None:
    assert default_auto_density_uses_crop({}) is True
    assert default_auto_density_uses_crop({"auto_density_uses_crop": False}) is False
