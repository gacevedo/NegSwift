"""Process-mode autodetect — wraps NegPy heuristics for the lite shell."""

from __future__ import annotations

from negpy.features.process.logic import detect_process_mode
from negpy.features.process.models import ProcessMode
from negpy.infrastructure.display.color_spaces import WORKING_COLOR_SPACE
from negpy.services.rendering.preview_manager import PreviewManager

from negswift_engine.file_hash_cache import cached_file_hash
from negswift_engine.render import _preview_manager_instance
from negswift_engine.sidecar_io import read_raw_sidecar


def _lite_process_mode(mode: ProcessMode) -> str:
    """Map upstream modes to NegSwift's C-41 / B&W picker (E-6 → Color Negative)."""
    if mode == ProcessMode.BW:
        return str(ProcessMode.BW)
    return str(ProcessMode.C41)


def _linear_scan_for_detection(path: str, pm: PreviewManager):
    scan = pm.decode_for_detection(path)
    if scan is not None:
        return scan
    file_hash = cached_file_hash(path)
    buffer, _, _ = pm.load_linear_preview(
        path,
        color_space=WORKING_COLOR_SPACE,
        file_hash=file_hash,
        use_camera_wb=False,
    )
    return buffer


def detect_process_mode_dict(path: str, *, force: bool = False) -> dict[str, object]:
    """Classify a scan as C-41 or B&W for new files without a ``.negpy`` sidecar."""
    if not force and read_raw_sidecar(path) is not None:
        return {"skipped": True, "reason": "has_sidecar"}

    pm = _preview_manager_instance()
    scan = _linear_scan_for_detection(path, pm)
    detected = detect_process_mode(scan)
    return {
        "skipped": False,
        "detected_mode": str(detected),
        "process_mode": _lite_process_mode(detected),
    }
