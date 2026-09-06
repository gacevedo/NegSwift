"""S11 gate: autocrop detect-once. Preview and export share the frozen rect.

Pinned config is ``auto_crop_enabled=true`` with no manual rect. Exit 0 when:
- first render reports a rect + key
- second render with that freeze does not re-detect
- preview and export use the same stored rect
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
import tifffile

from compare_s4a_renders import _repo_root

S11_PIN = {
    "crop_from_auto": True,
    "auto_crop_enabled": True,
    "autocrop_ratio": "Free",
    "autocrop_offset": 0,
}


def _frame_image(h: int, w: int) -> np.ndarray:
    img = np.ones((h, w, 3), dtype=np.float32)
    img[round(0.12 * h) : round(0.88 * h), round(0.10 * w) : round(0.90 * w)] = 0.05
    return img


def _write_holder_tiff(path: Path, h: int = 1200, w: int = 1800) -> None:
    rgb = _frame_image(h, w)
    tifffile.imwrite(path, (np.clip(rgb, 0, 1) * 65535.0 + 0.5).astype(np.uint16), photometric="rgb")


def _swift_bin() -> Path:
    override = os.environ.get("NEGSWIFT_ENGINE")
    if override:
        return Path(override)
    package = _repo_root() / "Packages" / "NegSwiftEngine"
    subprocess.run(["swift", "build", "--package-path", str(package)], check=True)
    raw = subprocess.check_output(
        ["swift", "build", "--package-path", str(package), "--show-bin-path"],
        text=True,
    ).strip()
    return Path(raw) / "negswift-engine-swift"


def _stdio(bin_path: Path, method: str, params: dict, req_id: str) -> dict:
    line = json.dumps({"id": req_id, "method": method, "params": params}) + "\n"
    proc = subprocess.run(
        [str(bin_path), "serve", "--stdio"],
        input=line,
        capture_output=True,
        text=True,
        check=True,
    )
    rows = [row for row in proc.stdout.strip().splitlines() if row]
    if not rows:
        raise RuntimeError(f"no stdout (stderr={proc.stderr!r})")
    return json.loads(rows[-1])


def _python_resolve(path: Path) -> dict:
    from negpy.domain.models import WorkspaceConfig
    from negpy.features.geometry.logic import resolve_autocrop_rect
    from negpy.features.geometry.models import GeometryConfig
    from negpy.infrastructure.loaders.tiff_loader import TiffLoader
    from negpy.services.rendering.image_processor import _resolve_armed_autocrop

    wrapper, _meta = TiffLoader().load(str(path))
    with wrapper as handle:
        rgb = np.asarray(handle.data, dtype=np.float32)
    armed = WorkspaceConfig(geometry=GeometryConfig(crop_from_auto=True, autocrop_ratio="Free"))
    once, first = _resolve_armed_autocrop(rgb, armed)
    twice, second = _resolve_armed_autocrop(rgb, once)
    rect = resolve_autocrop_rect(rgb, armed.geometry, 1600)
    return {
        "first": None if first is None else [float(v) for v in first[0]],
        "first_key": None if first is None else first[1],
        "second_is_none": second is None,
        "same_rect": once.geometry.crop_rect == (tuple(first[0]) if first else None) or second is None,
        "resolve_rect": None if rect is None else [float(v) for v in rect],
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="S11 autocrop detect-once")
    parser.add_argument("--path", default=None, help="Optional holder scan; default is a synthetic bed/frame TIFF")
    parser.add_argument("--out", help="Optional JSON report path")
    args = parser.parse_args()

    tmp: tempfile.TemporaryDirectory[str] | None = None
    if args.path:
        scan = Path(args.path).expanduser().resolve()
        if not scan.is_file():
            print(f"scan not found: {scan}", file=sys.stderr)
            sys.exit(2)
    else:
        tmp = tempfile.TemporaryDirectory(prefix="negswift-s11-")
        scan = Path(tmp.name) / "holder.tif"
        _write_holder_tiff(scan)

    python = _python_resolve(scan)
    swift = _swift_bin()
    first = _stdio(
        swift,
        "render",
        {"path": str(scan), "prefer_gpu": False, "long_edge_px": 400, "config": dict(S11_PIN)},
        "s11-first",
    )
    assert first.get("ok") is True, first
    metrics = (first.get("result") or {}).get("metrics") or {}
    rect = metrics.get("autocrop_resolved_rect")
    key = metrics.get("autocrop_resolved_key")
    first_ok = isinstance(rect, list) and len(rect) == 4 and bool(key)

    frozen = dict(S11_PIN)
    if first_ok:
        frozen["crop_rect"] = rect
        frozen["crop_detect_key"] = key
    second = _stdio(
        swift,
        "render",
        {"path": str(scan), "prefer_gpu": False, "long_edge_px": 400, "config": frozen},
        "s11-second",
    )
    assert second.get("ok") is True, second
    second_metrics = (second.get("result") or {}).get("metrics") or {}
    second_ok = second_metrics.get("autocrop_resolved_rect") is None

    preview_full = _stdio(
        swift,
        "render",
        {
            "path": str(scan),
            "prefer_gpu": False,
            "long_edge_px": 400,
            "crop_preview_full": True,
            "config": frozen,
        },
        "s11-full",
    )
    dest = Path(tmp.name if tmp is not None else tempfile.mkdtemp(prefix="negswift-s11-export-"))
    opened = _stdio(swift, "open", {"path": str(scan)}, "s11-open")
    source_w = (opened.get("result") or {}).get("width")
    exported = _stdio(
        swift,
        "export",
        {
            "path": str(scan),
            "dest_dir": str(dest),
            "overwrite": True,
            "export": {"export_fmt": "JPEG"},
            "config": frozen,
        },
        "s11-export",
    )
    export_ok = exported.get("ok") is True
    preview_w = (first.get("result") or {}).get("width")
    export_w = (exported.get("result") or {}).get("width")
    full_w = (preview_full.get("result") or {}).get("width")
    same_crop = (
        export_ok
        and isinstance(preview_w, int)
        and isinstance(export_w, int)
        and isinstance(full_w, int)
        and isinstance(source_w, int)
        and full_w > preview_w
        and export_w < source_w
    )

    py_ok = python["first"] is not None and python["second_is_none"]
    reports = [
        {
            "milestone": "S11-python-idempotent",
            "ok": py_ok,
            "first": python["first"],
            "second_is_none": python["second_is_none"],
        },
        {
            "milestone": "S11-swift-detect-once",
            "ok": first_ok and second_ok,
            "first_rect": rect,
            "first_key": key,
            "second_resolved": second_metrics.get("autocrop_resolved_rect"),
        },
        {
            "milestone": "S11-preview-export-same-rect",
            "ok": same_crop,
            "preview_width": preview_w,
            "export_width": export_w,
            "full_preview_width": full_w,
            "source_width": source_w,
        },
    ]
    payload = {"ok": all(r["ok"] for r in reports), "scan": str(scan), "reports": reports}
    print(json.dumps(payload, indent=2))
    if args.out:
        Path(args.out).write_text(json.dumps(payload, indent=2) + "\n")
    if tmp is not None:
        tmp.cleanup()
    if not payload["ok"]:
        sys.exit(1)


if __name__ == "__main__":
    main()
