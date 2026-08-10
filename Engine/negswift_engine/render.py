"""Preview render — shared by CLI and NDJSON protocol."""

from __future__ import annotations

import base64
import io
from typing import Any

import numpy as np
from negpy.domain.models import WorkspaceConfig
from negpy.infrastructure.display.color_mgmt import apply_display_transform
from negpy.infrastructure.display.color_spaces import WORKING_COLOR_SPACE
from negpy.infrastructure.gpu.resources import GPUTexture
from negpy.kernel.image.logic import calculate_file_hash, float_to_uint8
from negpy.kernel.system.config import APP_CONFIG, DEFAULT_WORKSPACE_CONFIG
from negpy.services.assets.sidecar import load_sidecar
from negpy.services.rendering.image_processor import ImageProcessor
from negpy.services.rendering.preview_manager import PreviewManager
from PIL import Image

_processor: ImageProcessor | None = None
_preview_manager: PreviewManager | None = None


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


def resolve_config(path: str, overrides: dict[str, Any] | None = None) -> WorkspaceConfig:
    config = load_sidecar(path) or DEFAULT_WORKSPACE_CONFIG
    if not overrides:
        return config
    flat = config.to_dict()
    flat.update(overrides)
    return WorkspaceConfig.from_flat_dict(flat)


def open_asset(path: str) -> dict[str, Any]:
    pm = _preview_manager_instance()
    f_hash = calculate_file_hash(path)
    buffer, dims, _meta = pm.load_linear_preview(path, color_space=WORKING_COLOR_SPACE, file_hash=f_hash)
    sidecar = load_sidecar(path)
    return {
        "path": path,
        "hash": f_hash,
        "width": dims[1] if dims else buffer.shape[1],
        "height": dims[0] if dims else buffer.shape[0],
        "has_sidecar": sidecar is not None,
    }


def render_preview_png(
    path: str,
    config_overrides: dict[str, Any] | None = None,
    long_edge_px: int | None = None,
    prefer_gpu: bool = True,
) -> tuple[bytes, int, int, dict[str, Any]]:
    """Run the NegPy preview pipeline; return PNG bytes, width, height, metrics."""
    config = resolve_config(path, config_overrides)
    f_hash = calculate_file_hash(path)
    preview_size = float(long_edge_px or APP_CONFIG.preview_render_size)

    pm = _preview_manager_instance()
    buffer, _dims, meta = pm.load_linear_preview(
        path,
        color_space=WORKING_COLOR_SPACE,
        file_hash=f_hash,
    )
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
    )

    if isinstance(result, GPUTexture):
        rgb = np.ascontiguousarray(result.readback()[:, :, :3])
    elif isinstance(result, np.ndarray):
        rgb = result[:, :, :3] if result.ndim == 3 and result.shape[2] >= 3 else result
    else:
        raise TypeError(f"Unexpected pipeline result type: {type(result)!r}")

    rgb = apply_display_transform(rgb.astype(np.float32, copy=False), WORKING_COLOR_SPACE)
    u8 = float_to_uint8(rgb)
    h, w = u8.shape[:2]

    png = Image.fromarray(u8, mode="RGB")
    out = io.BytesIO()
    png.save(out, format="PNG")
    slim_metrics = {k: metrics[k] for k in ("gpu_fallback",) if k in metrics}
    return out.getvalue(), w, h, slim_metrics


def render_preview_base64(
    path: str,
    config_overrides: dict[str, Any] | None = None,
    long_edge_px: int | None = None,
    prefer_gpu: bool = True,
) -> dict[str, Any]:
    png_bytes, width, height, metrics = render_preview_png(
        path,
        config_overrides=config_overrides,
        long_edge_px=long_edge_px,
        prefer_gpu=prefer_gpu,
    )
    return {
        "width": width,
        "height": height,
        "png_base64": base64.standard_b64encode(png_bytes).decode("ascii"),
        "metrics": metrics,
    }
