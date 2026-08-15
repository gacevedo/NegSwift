"""NDJSON request/response dispatch for negswift-engine serve."""

from __future__ import annotations

import json
import sys
from collections.abc import Callable
from typing import Any

from negswift_engine.discover import discover_assets
from negswift_engine.export import export_asset
from negswift_engine.render import load_config_dict, open_asset, render_preview_base64, save_config_dict
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


def _cmd_render(params: dict[str, Any]) -> dict[str, Any]:
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
    try:
        return render_preview_base64(
            path,
            config_overrides=config,
            long_edge_px=long_edge,
            prefer_gpu=prefer_gpu,
            crop_preview_full=crop_preview_full,
        )
    except FileNotFoundError as exc:
        raise ProtocolError("NOT_FOUND", str(exc)) from exc
    except OSError as exc:
        raise ProtocolError("LOAD_FAILED", str(exc)) from exc
    except Exception as exc:
        raise ProtocolError("RENDER_FAILED", str(exc)) from exc


def _cmd_export(params: dict[str, Any]) -> dict[str, Any]:
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
        )
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
    "render": _cmd_render,
    "export": _cmd_export,
}


def dispatch(method: str, params: dict[str, Any]) -> dict[str, Any]:
    handler = _HANDLERS.get(method)
    if handler is None:
        raise ProtocolError("INVALID_REQUEST", f"Unknown method: {method}")
    return handler(params)


class ProtocolError(Exception):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


def serve_stdio() -> None:
    """Read NDJSON requests from stdin; write NDJSON responses to stdout."""
    for raw in sys.stdin:
        line = raw.strip()
        if not line:
            continue
        req_id: Any = None
        try:
            msg = json.loads(line)
            if not isinstance(msg, dict):
                raise ProtocolError("INVALID_REQUEST", "Request must be a JSON object")
            req_id = msg.get("id")
            method = msg.get("method")
            if not isinstance(method, str):
                raise ProtocolError("INVALID_REQUEST", "Missing or invalid method")
            params = msg.get("params") or {}
            if not isinstance(params, dict):
                raise ProtocolError("INVALID_REQUEST", "params must be an object")
            result = dispatch(method, params)
            _emit({"id": req_id, "ok": True, "result": result})
        except ProtocolError as exc:
            _emit({"id": req_id, "ok": False, "error": {"code": exc.code, "message": exc.message}})
        except json.JSONDecodeError:
            _emit({"id": req_id, "ok": False, "error": {"code": "INVALID_REQUEST", "message": "Malformed JSON"}})
        except Exception as exc:  # noqa: BLE001 — protocol boundary; never crash the daemon
            _emit({"id": req_id, "ok": False, "error": {"code": "INTERNAL", "message": str(exc)}})


def _emit(payload: dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(payload, separators=(",", ":")) + "\n")
    sys.stdout.flush()
