#!/bin/sh
# Precompile LiteKernels.metal → LiteKernels.metallib (S13h).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
src="$root/Sources/NegSwiftEngine/Resources/Metal/LiteKernels.metal"
air="$(mktemp -t LiteKernels).air"
out="$root/Sources/NegSwiftEngine/Resources/Metal/LiteKernels.metallib"
xcrun -sdk macosx metal -c "$src" -o "$air" -std=metal3.0
xcrun -sdk macosx metallib "$air" -o "$out"
rm -f "$air"
echo "wrote $out"
