#!/usr/bin/env bash
# Freeze negswift-engine with PyInstaller (onedir). Output: Packaging/out/negswift-engine/
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${ROOT}/Packaging/out"
SPEC="${ROOT}/Packaging/engine.spec"

test -f "${ROOT}/Vendor/NegPy/VERSION" || {
    echo "NegPy submodule missing — run: git submodule update --init --recursive" >&2
    exit 1
}

if [ "$(uname -s)" = "Darwin" ] && ! [ -f /opt/homebrew/opt/libomp/lib/libomp.dylib ] && ! [ -f /usr/local/opt/libomp/lib/libomp.dylib ]; then
    echo "note: libomp not found — numba may warn during freeze; install with: brew install libomp" >&2
fi

cd "${ROOT}/Engine"
uv python install 3.13
uv sync --locked --group dev
uv run pyinstaller "${SPEC}" \
    --distpath "${OUT}" \
    --workpath "${OUT}/.pyinstaller-work" \
    --noconfirm \
    --clean

ENGINE_BIN="${OUT}/negswift-engine/negswift-engine"
test -x "${ENGINE_BIN}" || {
    echo "PyInstaller did not produce ${ENGINE_BIN}" >&2
    exit 1
}

echo "Built ${ENGINE_BIN}"
"${ENGINE_BIN}" info
