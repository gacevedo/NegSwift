"""S4b gate: Python CPU vs Swift MAE at one zone-offset and one CMY-offset config.

Same S4 pin as S4a (autos/Lab off). Exit 0 when both variants MAE <= --max-mae.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from compare_s4a_renders import S4A_PIN, _repo_root, compare_print

S4B_ZONE = {
    "shadow_density": -0.4,
    "highlight_density": 0.25,
    "shadow_grade": -25,
    "highlight_grade": 20,
}

S4B_CMY = {
    "wb_cyan": 0.3,
    "wb_magenta": -0.2,
    "wb_yellow": 0.5,
}


def main() -> None:
    parser = argparse.ArgumentParser(description="S4b Python vs Swift zone/CMY MAE")
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
            "S4b-zone",
            S4B_ZONE,
            "Working-space OETF at S4 pin + zone density/grade offset (autos/Lab off).",
        ),
        (
            "S4b-cmy",
            S4B_CMY,
            "Working-space OETF at S4 pin + CMY offset (autos/Lab off).",
        ),
    )
    reports = []
    ok = True
    for name, overrides, note in variants:
        config = dict(S4A_PIN)
        config.update(overrides)
        report = compare_print(scan, args.long_edge, config, name, args.max_mae, note)
        report["overrides"] = overrides
        reports.append(report)
        ok = ok and bool(report.get("ok"))
        print(json.dumps(report, indent=2))

    summary = {"ok": ok, "variants": reports}
    if args.out:
        Path(args.out).write_text(json.dumps(summary, indent=2) + "\n")
    if not ok:
        sys.exit(1)


if __name__ == "__main__":
    main()
