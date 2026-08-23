"""Heal stroke IPC — viewport-to-source mapping via NegPy ``uv_grid``."""

from __future__ import annotations

from typing import Any

from negpy.kernel.system.config import APP_CONFIG
from negpy.services.view.coordinate_mapping import CoordinateMapping

from negswift_engine.file_hash_cache import cached_file_hash
from negswift_engine.render import (
    _base_flat_dict,
    _evict_source_cache_if_asset_changed,
    _pipeline_lock,
    _preview_manager_instance,
    _processor_instance,
    _use_camera_wb,
    resolve_config,
)


def _stroke_to_json(stroke: Any) -> list[Any]:
    points, size, pad0, pad1 = stroke
    return [points, float(size), float(pad0), float(pad1)]


def _strokes_to_json(strokes: list[Any]) -> list[list[Any]]:
    return [_stroke_to_json(stroke) for stroke in strokes]


def _existing_strokes(flat: dict[str, Any]) -> list[Any]:
    raw = flat.get("manual_heal_strokes") or []
    return list(raw)


def _existing_spots(flat: dict[str, Any]) -> list[Any]:
    raw = flat.get("manual_dust_spots") or []
    return list(raw)


def _merged_flat(path: str, overrides: dict[str, Any] | None) -> dict[str, Any]:
    flat = _base_flat_dict(path)
    if overrides:
        flat.update(overrides)
    return flat


def _uv_grid_for_config(path: str, flat: dict[str, Any]) -> Any:
    from negpy.infrastructure.display.color_spaces import WORKING_COLOR_SPACE

    with _pipeline_lock:
        _evict_source_cache_if_asset_changed(path)
        config = resolve_config(path, flat)
        f_hash = cached_file_hash(path)
        preview_size = float(APP_CONFIG.preview_render_size)
        pm = _preview_manager_instance()
        buffer, _dims, meta = pm.load_linear_preview(
            path,
            color_space=WORKING_COLOR_SPACE,
            file_hash=f_hash,
            use_camera_wb=_use_camera_wb(config),
        )
        ir_buffer = meta.get("ir_preview")
        processor = _processor_instance()
        _result, metrics = processor.run_pipeline(
            buffer,
            config,
            f_hash,
            render_size_ref=preview_size,
            prefer_gpu=APP_CONFIG.use_gpu,
            readback_metrics=True,
            ir_buffer=ir_buffer,
            crop_preview_full=False,
            wants_uv_grid=True,
        )
    uv_grid = metrics.get("uv_grid")
    if uv_grid is None:
        raise RuntimeError("Preview metrics did not include uv_grid")
    return uv_grid


def append_heal_stroke_dict(
    path: str,
    points: list[list[float]],
    brush_size: float | None = None,
    config_overrides: dict[str, Any] | None = None,
) -> dict[str, Any]:
    if not points:
        raise ValueError("points must be a non-empty array")
    flat = _merged_flat(path, config_overrides)
    size = float(brush_size if brush_size is not None else flat.get("manual_dust_size", 6))
    uv_grid = _uv_grid_for_config(path, flat)
    raw_pts = [list(CoordinateMapping.map_click_to_raw(float(nx), float(ny), uv_grid)) for nx, ny in points]
    strokes = _existing_strokes(flat)
    strokes.append([raw_pts, size, 0.0, 0.0])
    return {
        "manual_heal_strokes": _strokes_to_json(strokes),
        "stroke_index": len(strokes) - 1,
    }


def undo_last_heal_dict(path: str, config_overrides: dict[str, Any] | None = None) -> dict[str, Any]:
    flat = _merged_flat(path, config_overrides)
    strokes = _existing_strokes(flat)
    spots = _existing_spots(flat)
    removed: str | None = None
    if strokes:
        strokes.pop()
        removed = "stroke"
    elif spots:
        spots.pop()
        removed = "spot"
    return {
        "manual_heal_strokes": _strokes_to_json(strokes),
        "manual_dust_spots": list(spots),
        "removed": removed,
    }
