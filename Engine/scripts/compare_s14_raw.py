"""S14 gate: camera RAW linear + S8 working-space MAE.

Always compares ``sample.tif`` (TIFF path unchanged). When LibRaw is linked,
also compares a tiny synthetic LinearRaw DNG. Named local RAW files
(``--path``, ``NEGSWIFT_S14_NEF``, ``NEGSWIFT_S14_ARW``, ``NEGSWIFT_S14_RAW``)
are skip-if-missing.
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
from compare_linear_decode import _is_camera_raw, _python_linear
from compare_s4a_renders import _downsample_nearest, _repo_root, _swift_print, compare_print
from compare_s8_renders import S8_PIN


def _swift_libraw_available() -> bool:
    package_dir = _repo_root() / "Packages" / "NegSwiftEngine"
    proc = subprocess.run(
        [
            "swift",
            "run",
            "--package-path",
            str(package_dir),
            "negswift-engine-swift",
            "info",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    text = proc.stdout
    start = text.find("{")
    end = text.rfind("}")
    if start < 0 or end < start:
        return False
    payload = json.loads(text[start : end + 1])
    return bool(payload.get("libraw"))


def _write_linear_dng(path: Path, height: int = 32, width: int = 32) -> None:
    import io
    import struct

    import tifffile

    rgb = np.zeros((height, width, 3), dtype=np.uint16)
    rgb[:, :, 0] = 40_000
    rgb[:, :, 1] = 22_000
    rgb[:, :, 2] = 10_000
    buf = io.BytesIO()
    tifffile.imwrite(
        buf,
        rgb,
        photometric="rgb",
        compression=None,
        metadata=None,
        extratags=[
            (254, 4, 1, 0, True),
            (50706, 1, 4, (1, 4, 0, 0), True),
        ],
    )
    data = bytearray(buf.getvalue())
    with tifffile.TiffFile(io.BytesIO(bytes(data))) as tif:
        offset = tif.pages[0].tags["PhotometricInterpretation"].valueoffset
        struct.pack_into(tif.byteorder + "H", data, offset, 34892)
    path.write_bytes(data)


def _python_print_any(path: Path, long_edge: int | None, config: dict) -> np.ndarray:
    from negpy.domain.models import WorkspaceConfig
    from negpy.services.rendering.image_processor import ImageProcessor

    from negswift_engine.metering import negpy_flat_for_pipeline

    rgb = _python_linear(path)
    if long_edge is not None:
        rgb = _downsample_nearest(rgb, long_edge)
    flat = dict(config)
    crop_preview_full = bool(flat.pop("crop_preview_full", False))
    workspace = WorkspaceConfig.from_flat_dict(negpy_flat_for_pipeline(flat))
    result, _metrics = ImageProcessor().run_pipeline(
        rgb,
        workspace,
        "s14-compare",
        render_size_ref=float(max(rgb.shape[0], rgb.shape[1])),
        prefer_gpu=False,
        wants_uv_grid=False,
        crop_preview_full=crop_preview_full,
    )
    if result.ndim == 3 and result.shape[2] >= 3:
        return np.asarray(result[:, :, :3], dtype=np.float32)
    return np.asarray(result, dtype=np.float32)


def _compare_linear(scan: Path, max_mae: float) -> dict:
    import compare_linear_decode as linear

    python_rgb = linear._python_linear(scan)
    root = _repo_root()
    package_dir = root / "Packages" / "NegSwiftEngine"
    with tempfile.TemporaryDirectory(prefix="negswift-s14-lin-") as tmp:
        raw = Path(tmp) / "swift.f32"
        subprocess.run(
            [
                "swift",
                "run",
                "--package-path",
                str(package_dir),
                "negswift-engine-swift",
                "decode",
                "--path",
                str(scan),
                "--out-f32",
                str(raw),
            ],
            check=True,
        )
        swift_flat = np.fromfile(raw, dtype="<f4")
    h, w = python_rgb.shape[:2]
    expected = h * w * 3
    if swift_flat.size != expected:
        return {
            "ok": False,
            "error": "shape mismatch",
            "milestone": "S14-linear",
            "scan": str(scan),
            "python": [h, w, 3],
            "swift_count": int(swift_flat.size),
        }
    swift_rgb = swift_flat.reshape(h, w, 3)
    mae = float(np.mean(np.abs(python_rgb - swift_rgb)))
    max_abs = float(np.max(np.abs(python_rgb - swift_rgb)))
    return {
        "milestone": "S14-linear",
        "scan": str(scan),
        "kind": "raw" if _is_camera_raw(scan) else "raster",
        "width": w,
        "height": h,
        "mae": mae,
        "max_abs": max_abs,
        "max_mae": max_mae,
        "ok": mae <= max_mae,
        "note": (
            "Sensor-native linear RGB vs rawpy. Not ImageIO camera RGB."
            if _is_camera_raw(scan)
            else "Linear RGB vs NegPy TiffLoader. TIFF/JPEG path unchanged."
        ),
    }


def _compare_s8(scan: Path, long_edge: int, max_mae: float) -> dict:
    if _is_camera_raw(scan):
        python_rgb = _python_print_any(scan, long_edge, dict(S8_PIN))
        swift_flat = _swift_print(scan, long_edge, dict(S8_PIN))
        h, w = python_rgb.shape[:2]
        expected = h * w * 3
        if swift_flat.size != expected:
            return {
                "ok": False,
                "error": "shape mismatch",
                "milestone": "S14-s8",
                "scan": str(scan),
                "python": [h, w, 3],
                "swift_count": int(swift_flat.size),
            }
        swift_rgb = swift_flat.reshape(h, w, 3)
        mae = float(np.mean(np.abs(python_rgb - swift_rgb)))
        return {
            "milestone": "S14-s8",
            "scan": str(scan),
            "long_edge_px": long_edge,
            "width": w,
            "height": h,
            "mae": mae,
            "max_mae": max_mae,
            "ok": mae <= max_mae,
            "note": "S8 working-space MAE on camera RAW at preview long edge.",
        }
    return compare_print(
        scan,
        long_edge,
        dict(S8_PIN),
        "S14-s8",
        max_mae,
        "S8 working-space MAE (raster).",
    )


def _local_raw_paths(explicit: list[str]) -> list[Path]:
    found: list[Path] = []
    seen: set[str] = set()

    def add(raw: str | None) -> None:
        if not raw:
            return
        for part in raw.split(os.pathsep):
            part = part.strip()
            if not part:
                continue
            path = Path(part).expanduser()
            key = str(path.resolve()) if path.is_file() else str(path)
            if key in seen:
                continue
            seen.add(key)
            found.append(path)

    for item in explicit:
        add(item)
    add(os.environ.get("NEGSWIFT_S14_NEF"))
    add(os.environ.get("NEGSWIFT_S14_ARW"))
    add(os.environ.get("NEGSWIFT_S14_RAW"))
    return found


def main() -> None:
    parser = argparse.ArgumentParser(description="S14 Python vs Swift camera RAW MAE")
    parser.add_argument(
        "--sample",
        default=str(_repo_root() / "App/NegSwiftUITests/Fixtures/sample.tif"),
    )
    parser.add_argument("--path", action="append", default=[], help="Local RAW (repeatable)")
    parser.add_argument("--long-edge", type=int, default=256)
    parser.add_argument("--max-mae-linear", type=float, default=2.0 / 65535.0)
    parser.add_argument("--max-mae-raw-linear", type=float, default=0.02)
    parser.add_argument("--max-mae-s8", type=float, default=0.02)
    parser.add_argument("--out", help="Optional JSON report path")
    args = parser.parse_args()

    reports: list[dict] = []
    sample = Path(args.sample).expanduser().resolve()
    if not sample.is_file():
        print(f"sample not found: {sample}", file=sys.stderr)
        sys.exit(2)
    reports.append(_compare_linear(sample, args.max_mae_linear))

    libraw = _swift_libraw_available()
    if libraw:
        with tempfile.TemporaryDirectory(prefix="negswift-s14-dng-") as tmp:
            dng = Path(tmp) / "synthetic.dng"
            _write_linear_dng(dng)
            reports.append(_compare_linear(dng, args.max_mae_raw_linear))
            reports.append(_compare_s8(dng, args.long_edge, args.max_mae_s8))
    else:
        reports.append(
            {
                "milestone": "S14-linear",
                "skipped": True,
                "ok": True,
                "note": "LibRaw not linked; synthetic DNG skipped.",
            }
        )

    for raw_path in _local_raw_paths(args.path):
        if not raw_path.is_file():
            reports.append(
                {
                    "milestone": "S14-linear",
                    "scan": str(raw_path),
                    "skipped": True,
                    "ok": True,
                    "note": "Local RAW missing.",
                }
            )
            continue
        if not libraw:
            reports.append(
                {
                    "milestone": "S14-linear",
                    "scan": str(raw_path),
                    "skipped": True,
                    "ok": True,
                    "note": "LibRaw not linked.",
                }
            )
            continue
        reports.append(_compare_linear(raw_path, args.max_mae_raw_linear))
        reports.append(_compare_s8(raw_path, args.long_edge, args.max_mae_s8))

    payload = {"ok": all(r.get("ok") for r in reports), "libraw": libraw, "reports": reports}
    print(json.dumps(payload, indent=2))
    if args.out:
        Path(args.out).write_text(json.dumps(payload, indent=2) + "\n")
    if not payload["ok"]:
        sys.exit(1)


if __name__ == "__main__":
    main()
