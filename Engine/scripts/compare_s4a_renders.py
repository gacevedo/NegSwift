"""S4a gate: Python CPU vs Swift working-space OETF MAE at the pinned print config.

Compares scene-linear decode + H&D + cast 0.5 + BPC + working OETF (no display
transform, no Lab, autos off). Exit 0 when MAE <= --max-mae.

S4b reuses ``compare_print`` with zone-offset and CMY-offset configs.
"""

from __future__ import annotations

import argparse
import json
import math
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np

S4A_PIN = {
    "auto_exposure": False,
    "auto_normalize_contrast": False,
    "sharpen": 0,
    "skin_protection": 0,
    "saturation": 1,
    "cast_removal_strength": 0.5,
    "paper_profile": "neutral",
    "paper_black": False,
    "paper_dmin": False,
    "density": 1.0,
    "grade": 115.0,
    "shadow_density": 0,
    "highlight_density": 0,
    "shadow_grade": 0,
    "highlight_grade": 0,
    "wb_cyan": 0,
    "wb_magenta": 0,
    "wb_yellow": 0,
    "rotation": 0,
    "fine_rotation": 0,
    "flip_horizontal": False,
    "flip_vertical": False,
    "clahe_strength": 0,
    "dust_remove": False,
    "crosstalk_strength": 0,
    "vignette_stops": 0,
    "carrier_width": 0,
    "analysis_buffer": 0.05,
}


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _swift_round(x: float) -> int:
    if x >= 0:
        return int(math.floor(x + 0.5))
    return int(math.ceil(x - 0.5))


def _downsample_nearest(rgb: np.ndarray, max_edge: int) -> np.ndarray:
    h, w = rgb.shape[:2]
    longest = max(h, w)
    if max_edge <= 0 or longest <= max_edge:
        return rgb
    new_w = max(1, _swift_round(w * max_edge / longest))
    new_h = max(1, _swift_round(h * max_edge / longest))
    out = np.empty((new_h, new_w, 3), dtype=np.float32)
    for y in range(new_h):
        src_y = min(h - 1, y * h // new_h)
        for x in range(new_w):
            src_x = min(w - 1, x * w // new_w)
            out[y, x] = rgb[src_y, src_x]
    return out


def _python_print(path: Path, long_edge: int | None, config: dict) -> np.ndarray:
    from negpy.domain.models import WorkspaceConfig
    from negpy.infrastructure.loaders.tiff_loader import TiffLoader
    from negpy.services.rendering.image_processor import ImageProcessor

    wrapper, _meta = TiffLoader().load(str(path))
    with wrapper as handle:
        rgb = np.asarray(handle.data, dtype=np.float32)
    if long_edge is not None:
        rgb = _downsample_nearest(rgb, long_edge)
    workspace = WorkspaceConfig.from_flat_dict(dict(config))
    result, _metrics = ImageProcessor().run_pipeline(
        rgb,
        workspace,
        "s4-compare",
        render_size_ref=float(max(rgb.shape[0], rgb.shape[1])),
        prefer_gpu=False,
        wants_uv_grid=False,
    )
    if result.ndim == 3 and result.shape[2] >= 3:
        return np.asarray(result[:, :, :3], dtype=np.float32)
    return np.asarray(result, dtype=np.float32)


def _swift_print(path: Path, long_edge: int | None, config: dict) -> np.ndarray:
    root = _repo_root()
    package_dir = root / "Packages" / "NegSwiftEngine"
    with tempfile.TemporaryDirectory(prefix="negswift-s4-") as tmp:
        raw = Path(tmp) / "swift.f32"
        png = Path(tmp) / "swift.png"
        cfg = Path(tmp) / "config.json"
        cfg.write_text(json.dumps(config))
        cmd = [
            "swift",
            "run",
            "--package-path",
            str(package_dir),
            "negswift-engine-swift",
            "render",
            "--path",
            str(path),
            "--out",
            str(png),
            "--out-f32",
            str(raw),
            "--config-json",
            str(cfg),
        ]
        if long_edge is not None:
            cmd.extend(["--long-edge", str(long_edge)])
        subprocess.run(cmd, check=True)
        return np.fromfile(raw, dtype="<f4")


def compare_print(
    scan: Path,
    long_edge: int | None,
    config: dict,
    milestone: str,
    max_mae: float,
    note: str,
) -> dict:
    python_rgb = _python_print(scan, long_edge, config)
    swift_flat = _swift_print(scan, long_edge, config)
    h, w = python_rgb.shape[:2]
    expected = h * w * 3
    if swift_flat.size != expected:
        return {
            "ok": False,
            "error": "shape mismatch",
            "milestone": milestone,
            "python": [h, w, 3],
            "swift_count": int(swift_flat.size),
        }
    swift_rgb = swift_flat.reshape(h, w, 3)
    diff = np.abs(python_rgb - swift_rgb)
    mae = float(np.mean(diff))
    max_abs = float(np.max(diff))
    p99 = float(np.quantile(diff, 0.99))
    mse = float(np.mean((python_rgb - swift_rgb) ** 2))
    psnr = 10.0 * math.log10(1.0 / mse) if mse > 0 else float("inf")
    return {
        "milestone": milestone,
        "look_claim": True,
        "scan": str(scan),
        "long_edge_px": long_edge,
        "width": w,
        "height": h,
        "mae": mae,
        "p99_abs": p99,
        "max_abs": max_abs,
        "psnr_db": psnr,
        "max_mae": max_mae,
        "ok": mae <= max_mae,
        "note": note,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="S4a Python vs Swift working-space MAE")
    parser.add_argument(
        "--path",
        default=str(_repo_root() / "App/NegSwiftUITests/Fixtures/sample.tif"),
    )
    parser.add_argument("--long-edge", type=int, default=None)
    parser.add_argument("--max-mae", type=float, default=0.02)
    parser.add_argument("--out", help="Optional JSON report path")
    args = parser.parse_args()

    scan = Path(args.path).expanduser().resolve()
    if not scan.is_file():
        print(f"scan not found: {scan}", file=sys.stderr)
        sys.exit(2)

    report = compare_print(
        scan,
        args.long_edge,
        dict(S4A_PIN),
        "S4a",
        args.max_mae,
        "Working-space OETF at S4a pin (autos/Lab off). Gate is MAE; max-abs can spike on holder/edge pixels.",
    )
    print(json.dumps(report, indent=2))
    if args.out:
        Path(args.out).write_text(json.dumps(report, indent=2) + "\n")
    if not report["ok"]:
        sys.exit(1)


if __name__ == "__main__":
    main()
