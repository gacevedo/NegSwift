"""S10b gate: Python CPU vs Swift MAE with optical dust on a speckled fixture.

Pinned config is S8 (autos + Lab defaults) plus dust_remove / threshold / size.
Exit 0 when dust-on MAE <= --max-mae and the toggle actually rewrites the speck.
"""

from __future__ import annotations

import argparse
import json
import sys
import tempfile
from pathlib import Path

import numpy as np
import tifffile

from compare_s4a_renders import _repo_root, compare_print, _python_print, _swift_print
from compare_s8_renders import S8_PIN

S10B_OFF = dict(S8_PIN)
S10B_OFF["dust_remove"] = False

S10B_ON = dict(S8_PIN)
S10B_ON.update(
    {
        "dust_remove": True,
        "dust_threshold": 0.66,
        "dust_size": 4,
    }
)


def _write_dusty_tiff(path: Path, h: int = 160, w: int = 160, seed: int = 42) -> None:
    rng = np.random.default_rng(seed)
    img = (np.full((h, w, 3), 0.18) * (1.0 + rng.normal(0, 0.02, (h, w, 3)))).astype(np.float32)
    img = np.clip(img, 0.0, 1.0)
    img[80:83, 80:83] = 0.005
    img[40:43, 40:43] = 0.005
    img[120:124, 90:94] = 0.008
    tifffile.imwrite(path, (img * 65535.0 + 0.5).astype(np.uint16), photometric="rgb")


def _speck_mean(rgb: np.ndarray) -> float:
    return float(rgb[80:83, 80:83].mean())


def main() -> None:
    parser = argparse.ArgumentParser(description="S10b Python vs Swift optical-dust MAE")
    parser.add_argument("--path", default=None, help="Optional scan; default is a synthetic dusty TIFF")
    parser.add_argument("--long-edge", type=int, default=None)
    parser.add_argument("--max-mae", type=float, default=0.02)
    parser.add_argument("--out", help="Optional JSON report path")
    args = parser.parse_args()

    tmp: tempfile.TemporaryDirectory[str] | None = None
    if args.path:
        scan = Path(args.path).expanduser().resolve()
        if not scan.is_file():
            print(f"scan not found: {scan}", file=sys.stderr)
            sys.exit(2)
    else:
        tmp = tempfile.TemporaryDirectory(prefix="negswift-s10b-")
        scan = Path(tmp.name) / "dusty.tif"
        _write_dusty_tiff(scan)

    reports = [
        compare_print(
            scan,
            args.long_edge,
            dict(S10B_OFF),
            "S10b-off",
            args.max_mae,
            "S8 look with dust off (baseline).",
        ),
        compare_print(
            scan,
            args.long_edge,
            dict(S10B_ON),
            "S10b-on",
            args.max_mae,
            "S8 look with dust_remove at default threshold/size.",
        ),
    ]

    py_off = _python_print(scan, args.long_edge, dict(S10B_OFF))
    py_on = _python_print(scan, args.long_edge, dict(S10B_ON))
    sw_off = _swift_print(scan, args.long_edge, dict(S10B_OFF)).reshape(py_off.shape)
    sw_on = _swift_print(scan, args.long_edge, dict(S10B_ON)).reshape(py_on.shape)
    toggle = {
        "milestone": "S10b-toggle",
        "python_speck_off": _speck_mean(py_off),
        "python_speck_on": _speck_mean(py_on),
        "swift_speck_off": _speck_mean(sw_off),
        "swift_speck_on": _speck_mean(sw_on),
        "python_changed": bool(np.any(py_off != py_on)),
        "swift_changed": bool(np.any(sw_off != sw_on)),
        "ok": bool(
            np.any(py_off != py_on)
            and np.any(sw_off != sw_on)
            and _speck_mean(py_on) < _speck_mean(py_off)
            and _speck_mean(sw_on) < _speck_mean(sw_off)
        ),
        "note": "On a C-41 print the dark scan speck is a bright spot; dust on must recede it.",
    }
    reports.append(toggle)
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
