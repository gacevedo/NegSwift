"""Preview render — shared by CLI and NDJSON protocol."""

from __future__ import annotations

import base64
import io
import threading
from pathlib import Path
from typing import Any

import cv2
import numpy as np
from negpy.domain.models import WorkspaceConfig
from negpy.infrastructure.display.color_mgmt import apply_display_transform
from negpy.infrastructure.display.color_spaces import WORKING_COLOR_SPACE
from negpy.infrastructure.gpu.resources import GPUTexture
from negpy.kernel.image.logic import float_to_uint8
from negpy.kernel.system.config import APP_CONFIG, DEFAULT_WORKSPACE_CONFIG
from negpy.services.rendering.image_processor import ImageProcessor
from negpy.services.rendering.preview_manager import PreviewManager
from PIL import Image

from negswift_engine.file_hash_cache import cached_file_hash, clear_file_hash_cache
from negswift_engine.jobs import JobCancelled
from negswift_engine.metering import (
    default_auto_density_uses_crop,
    negpy_flat_for_pipeline,
    negpy_flat_for_save,
    negswift_sidecar_extras,
)
from negswift_engine.sidecar_io import clear_sidecar_cache, delete_sidecar, read_raw_sidecar, write_raw_sidecar


def _check_cancel(cancel: threading.Event | None) -> None:
    if cancel is not None and cancel.is_set():
        raise JobCancelled()


def _detected_crop_rect(metrics: dict[str, Any], frame_width: int, frame_height: int) -> list[float] | None:
    """Map NegPy ``active_roi`` (y1, y2, x1, x2) pixels to normalized manual crop coords."""
    roi = metrics.get("active_roi")
    if not roi or len(roi) != 4:
        return None
    if frame_width <= 0 or frame_height <= 0:
        return None
    y1, y2, x1, x2 = (float(v) for v in roi)
    return [x1 / frame_width, y1 / frame_height, x2 / frame_width, y2 / frame_height]


_processor: ImageProcessor | None = None
_preview_manager: PreviewManager | None = None
_active_asset_path: str | None = None
# Preview and thumbnail renders run on separate engine threads; the shared
# ImageProcessor GPU pool must not be torn down while another render holds textures.
_pipeline_lock = threading.Lock()


def _processor_instance() -> ImageProcessor:
    global _processor
    if _processor is None:
        _processor = ImageProcessor()
    return _processor


def _preview_manager_instance() -> PreviewManager:
    global _preview_manager
    if _preview_manager is None:
        _preview_manager = PreviewManager()
    return _preview_manager


def reset_render_cache() -> None:
    """Drop singleton processor/preview manager — benchmarks and tests only."""
    global _processor, _preview_manager, _active_asset_path
    with _pipeline_lock:
        if _processor is not None:
            _processor.cleanup(release_source_cache=True, collect=True)
        _processor = None
        _preview_manager = None
        _active_asset_path = None
    clear_file_hash_cache()
    clear_sidecar_cache()


def _evict_source_cache_if_asset_changed(path: str) -> None:
    """Release NegPy source cache when switching to a different scan."""
    global _active_asset_path
    resolved = str(Path(path).resolve())
    if _active_asset_path is not None and _active_asset_path != resolved:
        proc = _processor
        if proc is not None:
            proc.cleanup(release_source_cache=True, collect=True)
    _active_asset_path = resolved


def _base_flat_dict(path: str) -> dict[str, Any]:
    raw = read_raw_sidecar(path)
    if raw is not None:
        return dict(raw)
    flat = DEFAULT_WORKSPACE_CONFIG.to_dict()
    flat["auto_density_uses_crop"] = True
    flat["auto_crop_enabled"] = True
    return flat


def load_config_dict(path: str) -> dict[str, Any]:
    flat = _base_flat_dict(path)
    if "auto_density_uses_crop" not in flat:
        flat["auto_density_uses_crop"] = True
    if "auto_crop_enabled" not in flat:
        flat["auto_crop_enabled"] = True
    return flat


def resolve_config(path: str, overrides: dict[str, Any] | None = None) -> WorkspaceConfig:
    flat = _base_flat_dict(path)
    if overrides:
        flat.update(overrides)
    return WorkspaceConfig.from_flat_dict(negpy_flat_for_pipeline(flat))


def save_config_dict(path: str, overrides: dict[str, Any] | None = None) -> dict[str, Any]:
    """Merge overrides onto stored/default config and write a ``.negpy`` sidecar."""
    flat = _base_flat_dict(path)
    if overrides:
        flat.update(overrides)
    extras = negswift_sidecar_extras(flat)
    if "auto_density_uses_crop" not in extras:
        extras["auto_density_uses_crop"] = default_auto_density_uses_crop(flat)
    config = WorkspaceConfig.from_flat_dict(negpy_flat_for_save(flat))
    payload = config.to_dict()
    payload.update(extras)
    sidecar_path = write_raw_sidecar(path, payload)
    return {"sidecar_path": sidecar_path}


def reset_config_dict(path: str) -> dict[str, Any]:
    """Delete the frame sidecar so the next load uses NegPy defaults."""
    removed = delete_sidecar(path)
    return {"sidecar_removed": removed}


def open_asset(path: str) -> dict[str, Any]:
    with _pipeline_lock:
        _evict_source_cache_if_asset_changed(path)
    pm = _preview_manager_instance()
    f_hash = cached_file_hash(path)
    buffer, dims, _meta = pm.load_linear_preview(path, color_space=WORKING_COLOR_SPACE, file_hash=f_hash)
    return {
        "path": path,
        "hash": f_hash,
        "width": dims[1] if dims else buffer.shape[1],
        "height": dims[0] if dims else buffer.shape[0],
        "has_sidecar": read_raw_sidecar(path) is not None,
    }


def render_preview_png(
    path: str,
    config_overrides: dict[str, Any] | None = None,
    long_edge_px: int | None = None,
    prefer_gpu: bool = True,
    crop_preview_full: bool = False,
    cancel: threading.Event | None = None,
) -> tuple[bytes, int, int, dict[str, Any]]:
    """Run the NegPy preview pipeline; return PNG bytes, width, height, metrics."""
    with _pipeline_lock:
        _check_cancel(cancel)
        _evict_source_cache_if_asset_changed(path)
        _check_cancel(cancel)
        config = resolve_config(path, config_overrides)
        _check_cancel(cancel)
        f_hash = cached_file_hash(path)
        _check_cancel(cancel)
        preview_size = float(long_edge_px or APP_CONFIG.preview_render_size)
        load_full_res = preview_size > float(APP_CONFIG.preview_render_size)

        pm = _preview_manager_instance()
        buffer, _dims, meta = pm.load_linear_preview(
            path,
            color_space=WORKING_COLOR_SPACE,
            file_hash=f_hash,
            full_resolution=load_full_res,
        )
        _check_cancel(cancel)
        ir_buffer = meta.get("ir_preview")

        processor = _processor_instance()
        result, metrics = processor.run_pipeline(
            buffer,
            config,
            f_hash,
            render_size_ref=preview_size,
            prefer_gpu=prefer_gpu and APP_CONFIG.use_gpu,
            readback_metrics=False,
            ir_buffer=ir_buffer,
            crop_preview_full=crop_preview_full,
        )

        if isinstance(result, GPUTexture):
            rgb = np.ascontiguousarray(result.readback()[:, :, :3])
        elif isinstance(result, np.ndarray):
            rgb = result[:, :, :3] if result.ndim == 3 and result.shape[2] >= 3 else result
        else:
            raise TypeError(f"Unexpected pipeline result type: {type(result)!r}")

        rgb = apply_display_transform(rgb.astype(np.float32, copy=False), WORKING_COLOR_SPACE)
        u8 = float_to_uint8(rgb)
        frame_h, frame_w = u8.shape[:2]
        long_edge = max(frame_h, frame_w)
        if long_edge > preview_size:
            scale = preview_size / long_edge
            target_w = max(1, int(frame_w * scale))
            target_h = max(1, int(frame_h * scale))
            u8 = cv2.resize(u8, (target_w, target_h), interpolation=cv2.INTER_AREA)
        h, w = u8.shape[:2]

        png = Image.fromarray(u8, mode="RGB")
        out = io.BytesIO()
        png.save(out, format="PNG")
        slim_metrics = {k: metrics[k] for k in ("gpu_fallback",) if k in metrics}
        if crop_preview_full:
            detected = _detected_crop_rect(metrics, frame_w, frame_h)
            if detected is not None:
                slim_metrics["detected_crop_rect"] = detected
        return out.getvalue(), w, h, slim_metrics


def render_preview_base64(
    path: str,
    config_overrides: dict[str, Any] | None = None,
    long_edge_px: int | None = None,
    prefer_gpu: bool = True,
    crop_preview_full: bool = False,
    cancel: threading.Event | None = None,
) -> dict[str, Any]:
    png_bytes, width, height, metrics = render_preview_png(
        path,
        config_overrides=config_overrides,
        long_edge_px=long_edge_px,
        prefer_gpu=prefer_gpu,
        crop_preview_full=crop_preview_full,
        cancel=cancel,
    )
    return {
        "width": width,
        "height": height,
        "png_base64": base64.standard_b64encode(png_bytes).decode("ascii"),
        "metrics": metrics,
    }
