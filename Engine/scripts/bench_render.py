#!/usr/bin/env python3
"""Run NegSwift engine performance scenarios and emit JSON (M12 Phase 0)."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

_ENGINE_ROOT = Path(__file__).resolve().parents[1]
if str(_ENGINE_ROOT) not in sys.path:
    sys.path.insert(0, str(_ENGINE_ROOT))

from negswift_engine.bench import BENCHMARK_VERSION, build_report, compare_to_baseline


def _write_synthetic_large_tiff(dest: Path) -> Path:
    import numpy as np
    import tifffile

    path = dest / "bench_large.tif"
    rgb = np.zeros((1500, 2000, 3), dtype=np.uint16)
    rgb[:, :, 0] = 40000
    rgb[:, :, 1] = 20000
    rgb[:, :, 2] = 10000
    tifffile.imwrite(path, rgb, photometric="rgb")
    return path


def main() -> int:
    parser = argparse.ArgumentParser(description="NegSwift engine performance benchmark")
    parser.add_argument(
        "--scan",
        type=Path,
        help="Primary scan path (default: synthetic 2000×1500 TIFF in a temp dir)",
    )
    parser.add_argument(
        "--second-scan",
        type=Path,
        help="Second scan for frame-switch timing (default: copy of primary with different name)",
    )
    parser.add_argument("--profile", default="custom", help="Label stored in the JSON report")
    parser.add_argument("--prefer-gpu", action="store_true", help="Use GPU for render/export")
    parser.add_argument("--long-edge-px", type=int, default=None, help="Preview long edge override")
    parser.add_argument("--export-dir", type=Path, default=None, help="Export destination directory")
    parser.add_argument("-o", "--output", type=Path, help="Write JSON report to file (default: stdout)")
    parser.add_argument(
        "--compare-baseline",
        type=Path,
        help="Fail if any timing exceeds baseline × tolerance",
    )
    parser.add_argument(
        "--tolerance",
        type=float,
        default=2.0,
        help="Max ratio vs baseline before --compare-baseline fails (default: 2.0)",
    )
    args = parser.parse_args()

    if args.scan is not None:
        scan_path = args.scan.resolve()
        if not scan_path.is_file():
            print(f"scan not found: {scan_path}", file=sys.stderr)
            return 1
        profile = args.profile if args.profile != "custom" else "real_scan"
    else:
        import tempfile

        tmp = Path(tempfile.mkdtemp(prefix="negswift-bench-"))
        scan_path = _write_synthetic_large_tiff(tmp)
        profile = "synthetic_large"

    second_path = args.second_scan.resolve() if args.second_scan else None
    if second_path is None and args.scan is None:
        import shutil

        second_path = scan_path.parent / "bench_large_b.tif"
        shutil.copy(scan_path, second_path)

    report = build_report(
        str(scan_path),
        profile=profile,
        second_path=str(second_path) if second_path else None,
        prefer_gpu=args.prefer_gpu,
        export_dir=str(args.export_dir) if args.export_dir else None,
        long_edge_px=args.long_edge_px,
    )
    report["version"] = BENCHMARK_VERSION

    payload = json.dumps(report, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(payload, encoding="utf-8")
        print(f"wrote {args.output}", file=sys.stderr)
    else:
        sys.stdout.write(payload)

    if args.compare_baseline:
        baseline = json.loads(args.compare_baseline.read_text(encoding="utf-8"))
        regressions = compare_to_baseline(report, baseline, tolerance=args.tolerance)
        if regressions:
            print("performance regressions:", file=sys.stderr)
            for line in regressions:
                print(f"  - {line}", file=sys.stderr)
            return 2

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
