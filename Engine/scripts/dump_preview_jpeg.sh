#!/usr/bin/env bash
# Dump a NegSwift engine preview JPEG for side-by-side checks in Preview.app.
#
# Usage:
#   ./scripts/dump_preview_jpeg.sh
#   ./scripts/dump_preview_jpeg.sh /path/to/scan.RAF
#   ./scripts/dump_preview_jpeg.sh /path/to/scan.RAF /tmp/out.jpg
#
# Environment:
#   PREFER_GPU=0   use CPU render (default: 1 / GPU when available)
#   LONG_EDGE_PX=1600

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SCAN_PATH="${1:-/Users/gacevedo/Downloads/sample-raw-scans/_DSF8434.RAF}"
OUT_PATH="${2:-}"
PREFER_GPU="${PREFER_GPU:-1}"
LONG_EDGE_PX="${LONG_EDGE_PX:-1600}"

if [[ ! -f "${SCAN_PATH}" ]]; then
  echo "Scan not found: ${SCAN_PATH}" >&2
  exit 1
fi

cd "${ENGINE_ROOT}"

uv run python - "${SCAN_PATH}" "${OUT_PATH}" "${PREFER_GPU}" "${LONG_EDGE_PX}" <<'PY'
import base64
import json
import subprocess
import sys
from pathlib import Path

scan = Path(sys.argv[1]).expanduser().resolve()
out = (
    Path(sys.argv[2]).expanduser().resolve()
    if sys.argv[2]
    else scan.with_name(f"{scan.stem}_preview.jpg")
)
prefer_gpu = sys.argv[3] not in {"0", "false", "False", "no", "NO"}
long_edge_px = int(sys.argv[4])

request = {
    "id": "dump-preview",
    "method": "render",
    "params": {
        "path": str(scan),
        "prefer_gpu": prefer_gpu,
        "preview_format": "jpeg",
        "jpeg_quality": 90,
        "long_edge_px": long_edge_px,
    },
}

proc = subprocess.run(
    [sys.executable, "-m", "negswift_engine.main", "serve", "--stdio"],
    input=json.dumps(request) + "\n",
    cwd=Path.cwd(),
    capture_output=True,
    text=True,
    check=True,
)
line = proc.stdout.strip().splitlines()[-1]
msg = json.loads(line)
if not msg.get("ok"):
    raise SystemExit(f"Engine error: {msg}")

result = msg["result"]
jpeg_b64 = result.get("jpeg_base64")
if not jpeg_b64:
    raise SystemExit(f"Engine returned no jpeg_base64: {result}")

jpeg = base64.standard_b64decode(jpeg_b64)
out.write_bytes(jpeg)
print(f"Scan:       {scan}")
print(f"GPU:        {prefer_gpu}")
print(f"Long edge:  {long_edge_px}px")
print(f"Preview:    {result.get('width')} x {result.get('height')}")
print(f"Wrote:      {out} ({len(jpeg)} bytes)")
PY
