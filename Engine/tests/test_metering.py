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


def test_pipeline_strips_stale_sidecar_analysis_rect_without_crop() -> None:
    flat = {
        "auto_crop_enabled": True,
        "analysis_rect": (0.2, 0.2, 0.8, 0.8),
        "local_floors": [0.1, 0.2, 0.3],
    }
    out = negpy_flat_for_pipeline(flat)
    assert out["crop_from_auto"] is True
    assert "analysis_rect" not in out
    assert out["local_floors"] == [0.0, 0.0, 0.0]


def test_armed_auto_crop_maps_auto_crop_enabled_to_crop_from_auto() -> None:
    flat = {"auto_crop_enabled": True}
    out = negpy_flat_for_pipeline(flat)
    assert out["crop_from_auto"] is True
    assert "auto_crop_enabled" not in out
    assert "analysis_rect" not in out


def test_negswift_sidecar_extras_keeps_only_known_keys() -> None:
    flat = {"auto_density_uses_crop": False, "density": 1.2, "analysis_buffer": 0.1}
    assert negswift_sidecar_extras(flat) == {"auto_density_uses_crop": False}


def test_default_auto_density_uses_crop() -> None:
    assert default_auto_density_uses_crop({}) is True
    assert default_auto_density_uses_crop({"auto_density_uses_crop": False}) is False


def test_crop_metering_keeps_crop_from_auto_when_frozen() -> None:
    flat = {
        "crop_rect": [0.1, 0.1, 0.9, 0.9],
        "crop_from_auto": True,
        "auto_density_uses_crop": True,
        "analysis_buffer": 0.1,
    }
    out = negpy_flat_for_pipeline(flat)
    assert out["crop_from_auto"] is True
    assert out["crop_rect"] == [0.1, 0.1, 0.9, 0.9]
    assert "analysis_rect" not in out


def test_pipeline_clears_stored_local_bounds() -> None:
    flat = {"local_floors": [0.1, 0.2, 0.3], "local_ceils": [0.9, 0.8, 0.7]}
    out = negpy_flat_for_pipeline(flat)
    assert out["local_floors"] == [0.0, 0.0, 0.0]
    assert out["local_ceils"] == [0.0, 0.0, 0.0]


def test_save_clears_local_bounds() -> None:
    flat = {
        "local_floors": [0.1, 0.2, 0.3],
        "local_ceils": [0.9, 0.8, 0.7],
        "density": 1.1,
    }
    out = negpy_flat_for_save(flat)
    assert out["local_floors"] == [0.0, 0.0, 0.0]
    assert out["local_ceils"] == [0.0, 0.0, 0.0]
    assert out["density"] == 1.1


def test_crop_metering_uses_analysis_rect_for_manual_crop() -> None:
    flat = {
        "manual_crop_rect": [0.1, 0.1, 0.9, 0.9],
        "crop_from_auto": False,
        "auto_density_uses_crop": True,
        "analysis_buffer": 0.1,
    }
    out = negpy_flat_for_pipeline(flat)
    assert out["crop_from_auto"] is False
    x1, y1, x2, y2 = out["analysis_rect"]
    assert abs(x1 - 0.18) < 1e-6 and abs(y1 - 0.18) < 1e-6
    assert abs(x2 - 0.82) < 1e-6 and abs(y2 - 0.82) < 1e-6
