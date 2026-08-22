"""NegSwift metering preferences — keys NegPy does not model."""

from __future__ import annotations

from typing import Any

NEGSWIFT_SIDECAR_KEYS: frozenset[str] = frozenset({"auto_density_uses_crop"})
FULL_FRAME_ANALYSIS_RECT: tuple[float, float, float, float] = (0.0, 0.0, 1.0, 1.0)


def _as_rect(value: Any) -> tuple[float, ...] | None:
    if value is None:
        return None
    if isinstance(value, (list, tuple)) and len(value) == 4:
        return tuple(float(v) for v in value)
    return None


def is_full_frame_analysis_rect(value: Any) -> bool:
    rect = _as_rect(value)
    if rect is None:
        return False
    return all(abs(a - b) < 1e-6 for a, b in zip(rect, FULL_FRAME_ANALYSIS_RECT, strict=True))


def negswift_sidecar_extras(flat: dict[str, Any]) -> dict[str, Any]:
    return {key: flat[key] for key in NEGSWIFT_SIDECAR_KEYS if key in flat}


def default_auto_density_uses_crop(flat: dict[str, Any]) -> bool:
    value = flat.get("auto_density_uses_crop")
    if value is None:
        return True
    return bool(value)


def _inset_normalized_rect(rect: tuple[float, ...], buffer: float) -> tuple[float, float, float, float]:
    x1, y1, x2, y2 = rect
    if buffer <= 0:
        return (x1, y1, x2, y2)
    width = x2 - x1
    height = y2 - y1
    if width <= 0 or height <= 0:
        return (x1, y1, x2, y2)
    safe = min(max(buffer, 0.0), 0.3)
    inset_x = safe * width
    inset_y = safe * height
    nx1, ny1 = x1 + inset_x, y1 + inset_y
    nx2, ny2 = x2 - inset_x, y2 - inset_y
    if nx2 - nx1 < 1e-4 or ny2 - ny1 < 1e-4:
        return (x1, y1, x2, y2)
    return (nx1, ny1, nx2, ny2)


def crop_metering_analysis_rect(flat: dict[str, Any]) -> tuple[float, float, float, float] | None:
    rect = _as_rect(flat.get("crop_rect")) or _as_rect(flat.get("manual_crop_rect"))
    if rect is None:
        return None
    buffer = float(flat.get("analysis_buffer", 0.05))
    return _inset_normalized_rect(rect, buffer)


def _has_manual_crop_rect(flat: dict[str, Any]) -> bool:
    return _as_rect(flat.get("crop_rect")) is not None or _as_rect(flat.get("manual_crop_rect")) is not None


def negpy_flat_for_save(flat: dict[str, Any]) -> dict[str, Any]:
    """Strip NegSwift-only keys; never persist wire-only ``analysis_rect`` overrides."""
    out = {key: value for key, value in flat.items() if key not in NEGSWIFT_SIDECAR_KEYS}
    if _has_manual_crop_rect(out):
        out = dict(out)
        out.pop("analysis_rect", None)
    return out


def negpy_flat_for_pipeline(flat: dict[str, Any]) -> dict[str, Any]:
    """Map NegSwift metering prefs onto NegPy ``WorkspaceConfig`` flat keys for render/export."""
    out = negpy_flat_for_save(flat)
    if not _has_manual_crop_rect(out):
        return out
    out = dict(out)
    # A drawn rect is manual unless the caller explicitly armed auto crop with no rect yet.
    out["crop_from_auto"] = False
    out.pop("auto_crop_enabled", None)
    if default_auto_density_uses_crop(flat):
        meter_rect = crop_metering_analysis_rect(flat)
        if meter_rect is not None:
            out["analysis_rect"] = meter_rect
    else:
        out["analysis_rect"] = FULL_FRAME_ANALYSIS_RECT
    return out
