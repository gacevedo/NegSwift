"""S5 gate: Python CPU vs Swift MAE with autos on, Lab still off.

Identity geometry. Crop-metering remap is covered by Swift ``MeteringRemapTests``
(port of ``test_metering.py``). Exit 0 when MAE <= --max-mae.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from compare_s4a_renders import S4A_PIN, _repo_root, compare_print

S5_PIN = dict(S4A_PIN)
S5_PIN.update(
    {
        "auto_exposure": True,
        "auto_normalize_contrast": True,
        "auto_density_uses_crop": True,
    }
)


def main() -> None:
    parser = argparse.ArgumentParser(description="S5 Python vs Swift autos MAE")
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
        dict(S5_PIN),
        "S5",
        args.max_mae,
        "Working-space OETF at S5 pin (autos on, Lab off, identity geometry).",
    )
    print(json.dumps(report, indent=2))
    if args.out:
        Path(args.out).write_text(json.dumps(report, indent=2) + "\n")
    if not report["ok"]:
        sys.exit(1)


if __name__ == "__main__":
    main()
