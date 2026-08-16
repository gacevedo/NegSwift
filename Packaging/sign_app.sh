#!/usr/bin/env bash
# Re-sign NegSwift.app after the bundled engine is copied in (ditto invalidates Xcode's seal).
set -euo pipefail

APP="${1:?Usage: sign_app.sh /path/to/NegSwift.app}"
IDENTITY="${NEGSWIFT_SIGN_IDENTITY:--}"
ENTITLEMENTS="${NEGSWIFT_ENTITLEMENTS:-$(cd "$(dirname "$0")/.." && pwd)/App/NegSwift/NegSwift.entitlements}"
ENGINE_ENTITLEMENTS="${NEGSWIFT_ENGINE_ENTITLEMENTS:-$(cd "$(dirname "$0")" && pwd)/engine.entitlements}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

test -d "$APP" || { echo "App bundle not found: $APP" >&2; exit 1; }

sign_macho() {
    local target="$1"
    local entitlements="${2:-}"
    local args=(--force --sign "$IDENTITY" --options runtime)
    if [ "$IDENTITY" != "-" ]; then
        args+=(--timestamp)
    fi
    if [ -n "$entitlements" ] && [ -f "$entitlements" ]; then
        args+=(--entitlements "$entitlements")
    fi
    codesign "${args[@]}" "$target"
}

for ENGINE_DIR in "$APP/Contents/Helpers/engine" "$APP/Contents/Resources/engine"; do
    [ -d "$ENGINE_DIR" ] || continue
    echo "Signing bundled engine Mach-O files in $(basename "$(dirname "$ENGINE_DIR")")/$(basename "$ENGINE_DIR")…"
    MAIN_ENGINE="$ENGINE_DIR/negswift-engine"
    find "$ENGINE_DIR" -type f -print0 | while IFS= read -r -d '' f; do
        file -b "$f" | grep -Eq 'Mach-O|universal' || continue
        if [ "$f" = "$MAIN_ENGINE" ]; then
            sign_macho "$f" "$ENGINE_ENTITLEMENTS"
        else
            sign_macho "$f"
        fi
    done
done

MAIN="$APP/Contents/MacOS/NegSwift"
test -f "$MAIN" || { echo "Missing main executable: $MAIN" >&2; exit 1; }

echo "Signing $APP with identity: $IDENTITY"
if [ -f "$ENTITLEMENTS" ]; then
    sign_macho "$APP" "$ENTITLEMENTS"
else
    sign_macho "$APP"
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
