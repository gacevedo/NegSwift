"""S9 gate: Python vs Swift sRGB export dimensions (JPEG/TIFF, crop, original res).

Exit 0 when both backends write the same width/height for each case.
Pixel MAE is not the gate — ImageIO JPEG ≠ Pillow JPEG.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

from compare_s4a_renders import _repo_root
from compare_s8_renders import S8_PIN
from negswift_engine.export import export_asset

# Stored-crop only. NegPy defaults arm autocrop_offset=1
# and crop_from_auto, which shrink the file before Swift has detect.
S9_PIN = dict(S8_PIN)
S9_PIN.update(
    {
        "crop_from_auto": False,
        "auto_crop_enabled": False,
        "autocrop_offset": 0,
        "autocrop_ratio": "Free",
        "paper_aspect_ratio": "Original",
        "export_resolution_mode": "original",
        "border_size": 0,
    }
)


_SWIFT_BIN: Path | None = None


def _swift_bin() -> Path:
    global _SWIFT_BIN
    if _SWIFT_BIN is not None:
        return _SWIFT_BIN
    root = _repo_root()
    package_dir = root / "Packages" / "NegSwiftEngine"
    subprocess.run(["swift", "build", "--package-path", str(package_dir)], check=True)
    shown = subprocess.run(
        ["swift", "build", "--package-path", str(package_dir), "--show-bin-path"],
        check=True,
        capture_output=True,
        text=True,
    )
    _SWIFT_BIN = Path(shown.stdout.strip()) / "negswift-engine-swift"
    return _SWIFT_BIN


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


def _dims(path: Path) -> tuple[int, int]:
    with Image.open(path) as img:
        return img.width, img.height


def _compare_case(scan: Path, label: str, config: dict, fmt: str) -> dict:
    with tempfile.TemporaryDirectory(prefix="negswift-s9-") as tmp:
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
                "export_resolution_mode": "original",
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
            "label": label,
            "ok": ok,
            "python": {"path": str(py_file), "width": py_wh[0], "height": py_wh[1]},
            "swift": {"path": str(sw_file), "width": sw_wh[0], "height": sw_wh[1]},
        }


def main() -> None:
    parser = argparse.ArgumentParser(description="S9 Python vs Swift export dimensions")
    parser.add_argument(
        "--path",
        default=str(_repo_root() / "App/NegSwiftUITests/Fixtures/sample.tif"),
    )
    parser.add_argument("--out", help="Optional JSON report path")
    args = parser.parse_args()

    scan = Path(args.path).expanduser().resolve()
    if not scan.is_file():
        print(f"scan not found: {scan}", file=sys.stderr)
        sys.exit(2)

    # Isolate from a neighboring .negpy so both backends see the same pixels.
    isolated = Path(tempfile.mkdtemp(prefix="negswift-s9-src-")) / scan.name
    shutil.copy2(scan, isolated)
    scan = isolated

    crop = dict(S9_PIN)
    crop["crop_rect"] = [0.25, 0.25, 0.75, 0.75]
    crop["crop_from_auto"] = False

    reports = [
        _compare_case(scan, "S9-jpeg-full", dict(S9_PIN), "JPEG"),
        _compare_case(scan, "S9-tiff-full", dict(S9_PIN), "TIFF"),
        _compare_case(scan, "S9-jpeg-crop", crop, "JPEG"),
    ]
    payload = {"ok": all(r["ok"] for r in reports), "reports": reports}
    print(json.dumps(payload, indent=2))
    if args.out:
        Path(args.out).write_text(json.dumps(payload, indent=2) + "\n")
    if not payload["ok"]:
        sys.exit(1)


if __name__ == "__main__":
    main()
