# PyInstaller spec for negswift-engine (headless NegPy wrapper, no Qt).
# Run via Packaging/build_engine.sh — inputs come from Vendor/NegPy only.

import os
import platform
from pathlib import Path

from PyInstaller.utils.hooks import collect_all, copy_metadata

block_cipher = None

spec_dir = Path(SPECPATH)
root = spec_dir.parent
negpy = root / "Vendor" / "NegPy"
engine = root / "Engine"

entry = str(engine / "negswift_engine" / "__main__.py")

negpy_datas = [
    ("negpy/features/exposure/shaders", "negpy/features/exposure/shaders"),
    ("negpy/features/geometry/shaders", "negpy/features/geometry/shaders"),
    ("negpy/features/toning/shaders", "negpy/features/toning/shaders"),
    ("negpy/features/lab/shaders", "negpy/features/lab/shaders"),
    ("negpy/features/lith/shaders", "negpy/features/lith/shaders"),
    ("negpy/features/cyanotype/shaders", "negpy/features/cyanotype/shaders"),
    ("negpy/features/finish/shaders", "negpy/features/finish/shaders"),
    ("icc", "icc"),
    ("media", "media"),
    ("crosstalk", "crosstalk"),
    ("gear", "gear"),
    ("VERSION", "."),
]

datas = [(str(negpy / rel), dest) for rel, dest in negpy_datas if (negpy / rel).exists()]
binaries: list = []

if platform.system() == "Darwin":
    for libomp in (
        Path("/opt/homebrew/opt/libomp/lib/libomp.dylib"),
        Path("/usr/local/opt/libomp/lib/libomp.dylib"),
    ):
        if libomp.is_file():
            binaries.append((str(libomp), "."))
            break

hiddenimports = [
    "negswift_engine",
    "negswift_engine.main",
    "negswift_engine.serve",
    "negswift_engine.protocol",
    "negswift_engine.render",
    "rawpy",
    "cv2",
    "numpy",
    "numba",
    "PIL",
    "PIL.Image",
    "PIL.ImageCms",
    "imageio",
    "imageio.v3",
    "tifffile",
    "imagecodecs",
    "jinja2",
]

for pkg in ("imageio", "rawpy", "imagecodecs", "wgpu"):
    datas += copy_metadata(pkg)

for pkg in ("wgpu", "rawpy", "imageio", "imagecodecs"):
    pkg_datas, pkg_binaries, pkg_hidden = collect_all(pkg)
    datas += pkg_datas
    binaries += pkg_binaries
    hiddenimports += [h for h in pkg_hidden if "imgui" not in h]

a = Analysis(
    [entry],
    pathex=[str(engine), str(negpy)],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        "PyQt6",
        "qtawesome",
        "negpy.desktop",
        "wgpu.utils.imgui",
        "imgui_bundle",
    ],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="negswift-engine",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=os.environ.get("NEGSWIFT_MACOS_ARCH", platform.machine()),
    codesign_identity=None,
    entitlements_file=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=False,
    upx_exclude=[],
    name="negswift-engine",
)
