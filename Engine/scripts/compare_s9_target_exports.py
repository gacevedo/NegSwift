"""S13m gate: Python vs Swift target_px export dimensions + working-space MAE.

``target_px`` export prints at ``export_target_long_edge_px`` (not full-res then shrink).
Exit 0 when dimensions match and MAE <= --max-mae at the pinned long edge.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from compare_s4a_renders import _repo_root, compare_print
from compare_s9_exports import S9_PIN, _dims, _swift_bin
from negswift_engine.export import export_asset

S9_TARGET_PIN = dict(S9_PIN)
S9_TARGET_PIN.update(
    {
        "export_resolution_mode": "target_px",
        # sample.tif is 48×32 — use 24 so Python layout downscales (not upscale).
        "export_target_long_edge_px": 24,
    }
)


def _swift_export(scan: Path, dest: Path, config: dict, fmt: str) -> dict:
    dest.mkdir(parents=True, exist_ok=True)
    cfg = dest / "config.json"
    cfg.write_text(json.dumps(config))
    cmd = [
        str(_swift_bin()),
        "export",
        "--path",
        str(scan),
        "--dest-dir",
        str(dest),
        "--fmt",
        fmt,
        "--config-json",
        str(cfg),
    ]
    proc = subprocess.run(cmd, check=True, capture_output=True, text=True)
    text = proc.stdout.strip()
    start = text.find("{")
    if start < 0:
        raise RuntimeError(f"swift export produced no JSON (stderr={proc.stderr!r})")
    return json.loads(text[start:])


def _compare_dimensions(scan: Path, config: dict, fmt: str) -> dict:
    with tempfile.TemporaryDirectory(prefix="negswift-s9t-dim-") as tmp:
        tmp_path = Path(tmp)
        py_dir = tmp_path / "py"
        sw_dir = tmp_path / "sw"
        py = export_asset(
            str(scan),
            str(py_dir),
            config_overrides=dict(config),
            export_overrides={
                "export_fmt": fmt,
                "export_color_space": "sRGB",
                "export_resolution_mode": "target_px",
                "export_target_long_edge_px": config["export_target_long_edge_px"],
                "jpeg_quality": 90,
            },
            prefer_gpu=False,
            overwrite=True,
        )
        sw = _swift_export(scan, sw_dir, config, fmt)
        py_wh = (int(py["width"]), int(py["height"]))
        sw_wh = (int(sw["width"]), int(sw["height"]))
        py_file = Path(py["output_path"])
        sw_file = Path(sw["output_path"])
        ok = py_wh == sw_wh == _dims(py_file) == _dims(sw_file)
        return {
            "label": f"S9t-{fmt.lower()}-dims",
            "ok": ok,
            "python": {"path": str(py_file), "width": py_wh[0], "height": py_wh[1]},
            "swift": {"path": str(sw_file), "width": sw_wh[0], "height": sw_wh[1]},
        }


def main() -> None:
    parser = argparse.ArgumentParser(description="S13m Python vs Swift target_px export gate")
    parser.add_argument(
        "--path",
        default=str(_repo_root() / "App/NegSwiftUITests/Fixtures/sample.tif"),
    )
    parser.add_argument("--target-long-edge", type=int, default=24)
    parser.add_argument("--max-mae", type=float, default=0.02)
    parser.add_argument("--out", help="Optional JSON report path")
    args = parser.parse_args()

    scan = Path(args.path).expanduser().resolve()
    if not scan.is_file():
        print(f"scan not found: {scan}", file=sys.stderr)
        sys.exit(2)

    isolated = Path(tempfile.mkdtemp(prefix="negswift-s9t-src-")) / scan.name
    shutil.copy2(scan, isolated)
    scan = isolated

    pin = dict(S9_TARGET_PIN)
    pin["export_target_long_edge_px"] = args.target_long_edge

    reports = [
        _compare_dimensions(scan, pin, "JPEG"),
        compare_print(
            scan,
            args.target_long_edge,
            pin,
            "S9t-mae",
            args.max_mae,
            "S13m target_px print at export long edge (not full-res then shrink).",
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
