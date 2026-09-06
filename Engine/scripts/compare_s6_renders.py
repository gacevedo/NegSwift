"""S6 gate: Python CPU vs Swift MAE for stored geometry (no autocrop detect).

S5 look (autos on, Lab off) plus the geometry under test. Applies
``negpy_flat_for_pipeline`` so crop metering matches the Python engine.
Exit 0 when every variant MAE <= --max-mae and cropped dims shrink vs
the full frame. CI fixture is ``sample.tif``.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from compare_s5_renders import S5_PIN
from compare_s4a_renders import _repo_root, compare_print

S6_CROP = {
    "crop_rect": [0.25, 0.25, 0.75, 0.75],
    "crop_from_auto": False,
}


def main() -> None:
    parser = argparse.ArgumentParser(description="S6 Python vs Swift geometry MAE")
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

    variants = (
        (
            "S6-crop",
            S6_CROP,
            "S5 pin + stored crop_rect (pixel crop applied).",
        ),
        (
            "S6-rot90",
            {"rotation": 1},
            "S5 pin + 90° CCW (np.rot90 k=1).",
        ),
        (
            "S6-flip",
            {"flip_horizontal": True, "flip_vertical": True},
            "S5 pin + flip H/V.",
        ),
        (
            "S6-fine-rot",
            {"fine_rotation": 2.5},
            "S5 pin + fine_rotation 2.5° (cv2 warpAffine).",
        ),
        (
            "S6-crop-preview-full",
            {**S6_CROP, "crop_preview_full": True},
            "S5 pin + stored crop, crop_preview_full (uncropped frame).",
        ),
    )
    reports = []
    ok = True
    for name, overrides, note in variants:
        config = dict(S5_PIN)
        config.update(overrides)
        report = compare_print(scan, args.long_edge, config, name, args.max_mae, note)
        report["overrides"] = overrides
        reports.append(report)
        ok = ok and bool(report.get("ok"))
        print(json.dumps(report, indent=2))

    crop = next((r for r in reports if r["milestone"] == "S6-crop"), None)
    preview = next((r for r in reports if r["milestone"] == "S6-crop-preview-full"), None)
    dims_ok = False
    if crop and preview and "width" in crop and "width" in preview:
        dims_ok = (preview["width"] * preview["height"]) > (crop["width"] * crop["height"])
        if not dims_ok:
            ok = False
    dims_report = {
        "milestone": "S6-export-dims",
        "ok": dims_ok,
        "note": "Applied crop must shrink vs crop_preview_full (test_crop / test_export).",
        "crop": None if crop is None else [crop.get("width"), crop.get("height")],
        "preview_full": None if preview is None else [preview.get("width"), preview.get("height")],
    }
    reports.append(dims_report)
    print(json.dumps(dims_report, indent=2))

    summary = {"ok": ok, "variants": reports}
    if args.out:
        Path(args.out).write_text(json.dumps(summary, indent=2) + "\n")
    if not ok:
        sys.exit(1)


if __name__ == "__main__":
    main()
