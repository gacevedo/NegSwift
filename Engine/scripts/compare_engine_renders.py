"""Python-vs-Swift preview MAE report.

S2/S3: Swift writes a log-normalized PNG (harsh positive; no H&D / autos / Lab).
S3 OETF is unit-only and is not applied to scan preview. Python still runs the
full lite look. This is not a full-pipeline MAE gate.
Exit 0 when both renders write a PNG and a report is printed.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _run(cmd: list[str], cwd: Path | None = None) -> None:
    subprocess.run(cmd, cwd=cwd, check=True)


def _load_rgb(path: Path) -> np.ndarray:
    image = Image.open(path).convert("RGB")
    return np.asarray(image, dtype=np.float32) / 255.0


def _mae(a: np.ndarray, b: np.ndarray) -> float:
    if a.shape != b.shape:
        b_img = Image.fromarray((np.clip(b, 0, 1) * 255).astype(np.uint8)).resize(
            (a.shape[1], a.shape[0]),
            Image.Resampling.NEAREST,
        )
        b = np.asarray(b_img, dtype=np.float32) / 255.0
    return float(np.mean(np.abs(a - b)))


def main() -> None:
    parser = argparse.ArgumentParser(description="Python vs Swift render MAE (S2 report, no look claim)")
    parser.add_argument(
        "--path",
        default=str(_repo_root() / "App/NegSwiftUITests/Fixtures/sample.tif"),
        help="Scan path (default: UI-test sample.tif)",
    )
    parser.add_argument("--long-edge", type=int, default=256)
    parser.add_argument("--out", help="Optional JSON report path")
    args = parser.parse_args()

    scan = Path(args.path).expanduser().resolve()
    if not scan.is_file():
        print(f"scan not found: {scan}", file=sys.stderr)
        sys.exit(2)

    root = _repo_root()
    engine_dir = root / "Engine"
    package_dir = root / "Packages" / "NegSwiftEngine"

    with tempfile.TemporaryDirectory(prefix="negswift-mae-") as tmp:
        tmp_path = Path(tmp)
        python_png = tmp_path / "python.png"
        swift_png = tmp_path / "swift.png"

        _run(
            [
                "uv",
                "run",
                "negswift-engine",
                "render",
                "--path",
                str(scan),
                "--out",
                str(python_png),
                "--long-edge",
                str(args.long_edge),
                "--cpu",
            ],
            cwd=engine_dir,
        )
        _run(
            [
                "swift",
                "run",
                "--package-path",
                str(package_dir),
                "negswift-engine-swift",
                "render",
                "--path",
                str(scan),
                "--out",
                str(swift_png),
                "--long-edge",
                str(args.long_edge),
            ]
        )

        python_rgb = _load_rgb(python_png)
        swift_rgb = _load_rgb(swift_png)
        resized = python_rgb.shape != swift_rgb.shape
        mae = _mae(python_rgb, swift_rgb)

        report = {
            "look_claim": False,
            "milestone": "S2",
            "scan": str(scan),
            "long_edge_px": args.long_edge,
            "python": {"width": int(python_rgb.shape[1]), "height": int(python_rgb.shape[0])},
            "swift": {"width": int(swift_rgb.shape[1]), "height": int(swift_rgb.shape[0]), "normalized": True},
            "resized_swift_to_python": resized,
            "mae": mae,
            "note": "S2 Swift is log-normalize only. Not a full-pipeline MAE gate.",
        }
        text = json.dumps(report, indent=2)
        print(text)
        if args.out:
            out = Path(args.out)
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_text(text + "\n")


if __name__ == "__main__":
    main()
