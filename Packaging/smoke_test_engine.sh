#!/usr/bin/env bash
# Smoke-test the frozen engine binary (used by CI).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="${ROOT}/Packaging/out/negswift-engine/negswift-engine"
test -x "${ENGINE}" || { echo "Missing ${ENGINE} — run make bundle-engine first" >&2; exit 1; }
"${ENGINE}" info | grep -q negswift_version
