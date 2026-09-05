"""MAE between NegPy linear decode and Swift ImageIO decode.

S1 gate: same 16-bit untagged TIFF, compare scene-linear RGB (not display).
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _python_linear(path: Path) -> np.ndarray:
    from negpy.infrastructure.loaders.tiff_loader import TiffLoader

    wrapper, _meta = TiffLoader().load(str(path))
    with wrapper as handle:
        return np.asarray(handle.data, dtype=np.float32)


def main() -> None:
    parser = argparse.ArgumentParser(description="Python vs Swift linear-decode MAE")
    parser.add_argument(
        "--path",
        default=str(_repo_root() / "App/NegSwiftUITests/Fixtures/sample.tif"),
    )
    parser.add_argument("--max-mae", type=float, default=2.0 / 65535.0)
    parser.add_argument("--out", help="Optional JSON report path")
    args = parser.parse_args()

    scan = Path(args.path).expanduser().resolve()
    if not scan.is_file():
        print(f"scan not found: {scan}", file=sys.stderr)
        sys.exit(2)

    root = _repo_root()
    package_dir = root / "Packages" / "NegSwiftEngine"
    python_rgb = _python_linear(scan)

    with tempfile.TemporaryDirectory(prefix="negswift-linear-") as tmp:
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
        print(
            json.dumps(
                {
                    "ok": False,
                    "error": "shape mismatch",
                    "python": [h, w, 3],
                    "swift_count": int(swift_flat.size),
                },
                indent=2,
            )
        )
        sys.exit(1)

    swift_rgb = swift_flat.reshape(h, w, 3)
    mae = float(np.mean(np.abs(python_rgb - swift_rgb)))
    max_abs = float(np.max(np.abs(python_rgb - swift_rgb)))
    report = {
        "milestone": "S1",
        "scan": str(scan),
        "width": w,
        "height": h,
        "mae": mae,
        "max_abs": max_abs,
        "max_mae": args.max_mae,
        "ok": mae <= args.max_mae,
        "note": "Linear RGB vs NegPy TiffLoader. Not a display / look claim.",
    }
    print(json.dumps(report, indent=2))
    if args.out:
        Path(args.out).write_text(json.dumps(report, indent=2) + "\n")
    if not report["ok"]:
        sys.exit(1)


if __name__ == "__main__":
    main()
