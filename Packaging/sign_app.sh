#!/usr/bin/env bash
# Sign NegSwift.app after LibRaw bundling (or a plain Swift-only build).
set -euo pipefail

APP="${1:?Usage: sign_app.sh /path/to/NegSwift.app}"
IDENTITY="${NEGSWIFT_SIGN_IDENTITY:--}"
ENTITLEMENTS="${NEGSWIFT_ENTITLEMENTS:-$(cd "$(dirname "$0")/.." && pwd)/App/NegSwift/NegSwift.entitlements}"

test -d "$APP" || { echo "App bundle not found: $APP" >&2; exit 1; }

# Hardened runtime enforces library validation: bundled dylibs must share the
# signing Team ID with the main executable. Ad-hoc (-) cannot satisfy that, so
# local builds skip runtime. Developer ID release builds use runtime everywhere.
USE_RUNTIME=0
if [ "$IDENTITY" != "-" ]; then
    USE_RUNTIME=1
fi

sign_macho() {
    local target="$1"
    local entitlements="${2:-}"
    local with_runtime="${3:-0}"
    local args=(--force --sign "$IDENTITY")
    if [ "$with_runtime" = "1" ]; then
        args+=(--options runtime)
    fi
    if [ "$IDENTITY" != "-" ]; then
        args+=(--timestamp)
    fi
    if [ -n "$entitlements" ] && [ -f "$entitlements" ]; then
        args+=(--entitlements "$entitlements")
    fi
    codesign "${args[@]}" "$target"
}

MAIN="$APP/Contents/MacOS/NegSwift"
test -f "$MAIN" || { echo "Missing main executable: $MAIN" >&2; exit 1; }

FRAMEWORKS="$APP/Contents/Frameworks"
if [ -d "$FRAMEWORKS" ]; then
    echo "Signing bundled Frameworks dylibs…"
    find "$FRAMEWORKS" -type f -name '*.dylib' -print0 | while IFS= read -r -d '' f; do
        codesign --remove-signature "$f" 2>/dev/null || true
        sign_macho "$f" "" "$USE_RUNTIME"
    done
fi

echo "Signing $APP with identity: $IDENTITY"
codesign --remove-signature "$MAIN" 2>/dev/null || true
if [ -f "$ENTITLEMENTS" ]; then
    sign_macho "$MAIN" "$ENTITLEMENTS" "$USE_RUNTIME"
    sign_macho "$APP" "$ENTITLEMENTS" "$USE_RUNTIME"
else
    sign_macho "$MAIN" "" "$USE_RUNTIME"
    sign_macho "$APP" "" "$USE_RUNTIME"
fi

codesign --verify --deep "$APP"
echo "Signature OK."

if [ "$IDENTITY" = "-" ]; then
    cat >&2 <<'EOF'

note: ad-hoc signature (-) is for local testing only.
Other Macs will still block Gatekeeper until you sign with a Developer ID and notarize:
  export NEGSWIFT_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
  make sign-release-app
  make notarize-release-app
EOF
fi
