"""S8 gate: Python CPU vs Swift MAE at app defaults (autos + Lab on).

Pinned config is S5 (autos on) plus NegPy Lab defaults: saturation 1,
sharpen 0.25 USM, skin_protection 0.5. Exit 0 when MAE <= --max-mae.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from compare_s5_renders import S5_PIN
from compare_s4a_renders import _repo_root, compare_print

S8_PIN = dict(S5_PIN)
S8_PIN.update(
    {
        "sharpen": 0.25,
        "skin_protection": 0.5,
        "saturation": 1.0,
        "sharpen_radius": 1.0,
        "sharpen_masking": 0.0,
    }
)

S8_CHROMA = dict(S8_PIN)
S8_CHROMA["saturation"] = 1.3


def main() -> None:
    parser = argparse.ArgumentParser(description="S8 Python vs Swift Lab-defaults MAE")
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

    reports = [
        compare_print(
            scan,
            args.long_edge,
            dict(S8_PIN),
            "S8",
            args.max_mae,
            "Working-space OETF at S8 pin (autos on, Lab defaults, identity geometry).",
        ),
        compare_print(
            scan,
            args.long_edge,
            dict(S8_CHROMA),
            "S8-chroma",
            args.max_mae,
            "S8 pin with saturation=1.3 (Chroma slider).",
        ),
    ]
    payload = {"ok": all(r["ok"] for r in reports), "reports": reports}
    print(json.dumps(payload, indent=2))
    if args.out:
        Path(args.out).write_text(json.dumps(payload, indent=2) + "\n")
    if not payload["ok"]:
        sys.exit(1)


if __name__ == "__main__":
    main()
