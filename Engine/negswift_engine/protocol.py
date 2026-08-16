"""NDJSON request/response dispatch for negswift-engine serve."""

from __future__ import annotations

import sys
import threading
from collections.abc import Callable
from typing import Any

from negswift_engine.detect import detect_process_mode_dict
from negswift_engine.discover import discover_assets
from negswift_engine.export import export_asset
from negswift_engine.jobs import JobCancelled
from negswift_engine.render import (
    DEFAULT_PREVIEW_JPEG_QUALITY,
    VALID_PREVIEW_FORMATS,
    load_config_dict,
    open_asset,
    render_preview_base64,
    reset_config_dict,
    save_config_dict,
)
from negswift_engine.versions import negpy_version

Handler = Callable[[dict[str, Any]], dict[str, Any]]


def _cmd_info(_params: dict[str, Any]) -> dict[str, Any]:
    from negpy.infrastructure.gpu.device import GPUDevice

    from negswift_engine import __version__

    gpu = GPUDevice.get()
    return {
        "protocol_version": "0.1",
        "negswift_version": __version__,
        "negpy_version": negpy_version(),
        "python": sys.version.split()[0],
        "gpu_available": gpu.is_available,
        "gpu_backend": gpu.backend_name if gpu.is_available else None,
    }


def _cmd_ping(_params: dict[str, Any]) -> dict[str, Any]:
    return {"pong": True}


def _cmd_open(params: dict[str, Any]) -> dict[str, Any]:
    path = params.get("path")
    if not isinstance(path, str) or not path:
        raise ProtocolError("INVALID_REQUEST", "params.path is required")
    try:
        return open_asset(path)
    except FileNotFoundError as exc:
        raise ProtocolError("NOT_FOUND", str(exc)) from exc
    except OSError as exc:
        raise ProtocolError("LOAD_FAILED", str(exc)) from exc


def _cmd_discover(params: dict[str, Any]) -> dict[str, Any]:
    paths = params.get("paths")
    if not isinstance(paths, list) or not paths or not all(isinstance(p, str) for p in paths):
        raise ProtocolError("INVALID_REQUEST", "params.paths must be a non-empty string array")
    return {"assets": discover_assets(paths)}


def _cmd_load_config(params: dict[str, Any]) -> dict[str, Any]:
    path = params.get("path")
    if not isinstance(path, str) or not path:
        raise ProtocolError("INVALID_REQUEST", "params.path is required")
    try:
        return {"config": load_config_dict(path)}
    except FileNotFoundError as exc:
        raise ProtocolError("NOT_FOUND", str(exc)) from exc
    except OSError as exc:
        raise ProtocolError("LOAD_FAILED", str(exc)) from exc


def _cmd_save_config(params: dict[str, Any]) -> dict[str, Any]:
    path = params.get("path")
    if not isinstance(path, str) or not path:
        raise ProtocolError("INVALID_REQUEST", "params.path is required")
    config = params.get("config")
    if config is not None and not isinstance(config, dict):
        raise ProtocolError("INVALID_REQUEST", "params.config must be an object")
    try:
        return save_config_dict(path, config)
    except FileNotFoundError as exc:
        raise ProtocolError("NOT_FOUND", str(exc)) from exc
    except OSError as exc:
        raise ProtocolError("SAVE_FAILED", str(exc)) from exc


def _cmd_reset_config(params: dict[str, Any]) -> dict[str, Any]:
    path = params.get("path")
    if not isinstance(path, str) or not path:
        raise ProtocolError("INVALID_REQUEST", "params.path is required")
    try:
        return reset_config_dict(path)
    except OSError as exc:
        raise ProtocolError("RESET_FAILED", str(exc)) from exc


def _cmd_detect_process_mode(params: dict[str, Any]) -> dict[str, Any]:
    path = params.get("path")
    if not isinstance(path, str) or not path:
        raise ProtocolError("INVALID_REQUEST", "params.path is required")
    force = params.get("force", False)
    if not isinstance(force, bool):
        raise ProtocolError("INVALID_REQUEST", "params.force must be a boolean")
    try:
        return detect_process_mode_dict(path, force=force)
    except FileNotFoundError as exc:
        raise ProtocolError("NOT_FOUND", str(exc)) from exc
    except OSError as exc:
        raise ProtocolError("LOAD_FAILED", str(exc)) from exc


def _cmd_render(params: dict[str, Any], cancel: threading.Event | None = None) -> dict[str, Any]:
    path = params.get("path")
    if not isinstance(path, str) or not path:
        raise ProtocolError("INVALID_REQUEST", "params.path is required")
    config = params.get("config")
    if config is not None and not isinstance(config, dict):
        raise ProtocolError("INVALID_REQUEST", "params.config must be an object")
    long_edge = params.get("long_edge_px")
    if long_edge is not None and not isinstance(long_edge, int):
        raise ProtocolError("INVALID_REQUEST", "params.long_edge_px must be an integer")
    prefer_gpu = params.get("prefer_gpu", True)
    if not isinstance(prefer_gpu, bool):
        raise ProtocolError("INVALID_REQUEST", "params.prefer_gpu must be a boolean")
    crop_preview_full = params.get("crop_preview_full", False)
    if not isinstance(crop_preview_full, bool):
        raise ProtocolError("INVALID_REQUEST", "params.crop_preview_full must be a boolean")
    preview_format = params.get("preview_format", "png")
    if not isinstance(preview_format, str) or preview_format not in VALID_PREVIEW_FORMATS:
        raise ProtocolError("INVALID_REQUEST", "params.preview_format must be 'png' or 'jpeg'")
    jpeg_quality = params.get("jpeg_quality", DEFAULT_PREVIEW_JPEG_QUALITY)
    if not isinstance(jpeg_quality, int) or jpeg_quality < 1 or jpeg_quality > 100:
        raise ProtocolError("INVALID_REQUEST", "params.jpeg_quality must be an integer from 1 to 100")
    try:
        return render_preview_base64(
            path,
            config_overrides=config,
            long_edge_px=long_edge,
            prefer_gpu=prefer_gpu,
            crop_preview_full=crop_preview_full,
            preview_format=preview_format,
            jpeg_quality=jpeg_quality,
            cancel=cancel,
        )
    except JobCancelled as exc:
        raise ProtocolError("CANCELLED", "Job cancelled") from exc
    except FileNotFoundError as exc:
        raise ProtocolError("NOT_FOUND", str(exc)) from exc
    except OSError as exc:
        raise ProtocolError("LOAD_FAILED", str(exc)) from exc
    except Exception as exc:
        raise ProtocolError("RENDER_FAILED", str(exc)) from exc


def _cmd_export(params: dict[str, Any], cancel: threading.Event | None = None) -> dict[str, Any]:
    path = params.get("path")
    if not isinstance(path, str) or not path:
        raise ProtocolError("INVALID_REQUEST", "params.path is required")
    dest_dir = params.get("dest_dir")
    if not isinstance(dest_dir, str) or not dest_dir:
        raise ProtocolError("INVALID_REQUEST", "params.dest_dir is required")
    config = params.get("config")
    if config is not None and not isinstance(config, dict):
        raise ProtocolError("INVALID_REQUEST", "params.config must be an object")
    export = params.get("export")
    if export is not None and not isinstance(export, dict):
        raise ProtocolError("INVALID_REQUEST", "params.export must be an object")
    prefer_gpu = params.get("prefer_gpu", True)
    if not isinstance(prefer_gpu, bool):
        raise ProtocolError("INVALID_REQUEST", "params.prefer_gpu must be a boolean")
    overwrite = params.get("overwrite", False)
    if not isinstance(overwrite, bool):
        raise ProtocolError("INVALID_REQUEST", "params.overwrite must be a boolean")
    try:
        return export_asset(
            path,
            dest_dir,
            config_overrides=config,
            export_overrides=export,
            prefer_gpu=prefer_gpu,
            overwrite=overwrite,
            cancel=cancel,
        )
    except JobCancelled as exc:
        raise ProtocolError("CANCELLED", "Job cancelled") from exc
    except FileNotFoundError as exc:
        raise ProtocolError("NOT_FOUND", str(exc)) from exc
    except OSError as exc:
        raise ProtocolError("EXPORT_FAILED", str(exc)) from exc
    except RuntimeError as exc:
        raise ProtocolError("EXPORT_FAILED", str(exc)) from exc
    except Exception as exc:
        raise ProtocolError("EXPORT_FAILED", str(exc)) from exc


_HANDLERS: dict[str, Handler] = {
    "ping": _cmd_ping,
    "info": _cmd_info,
    "open": _cmd_open,
    "discover": _cmd_discover,
    "load_config": _cmd_load_config,
    "save_config": _cmd_save_config,
    "reset_config": _cmd_reset_config,
    "detect_process_mode": _cmd_detect_process_mode,
    "render": _cmd_render,
    "export": _cmd_export,
}


def dispatch(method: str, params: dict[str, Any], cancel: threading.Event | None = None) -> dict[str, Any]:
    handler = _HANDLERS.get(method)
    if handler is None:
        raise ProtocolError("INVALID_REQUEST", f"Unknown method: {method}")
    if method in ("render", "export"):
        return handler(params, cancel)
    return handler(params)


class ProtocolError(Exception):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


def serve_stdio() -> None:
    """Read NDJSON requests from stdin; write NDJSON responses to stdout."""
    from negswift_engine.serve import serve_stdio as _serve_stdio

    _serve_stdio()
