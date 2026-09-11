#!/usr/bin/env bash
# Sign NegSwift.app for local testing or distribution.
set -euo pipefail

APP="${1:?Usage: sign_app.sh /path/to/NegSwift.app}"
IDENTITY="${NEGSWIFT_SIGN_IDENTITY:--}"
ENTITLEMENTS="${NEGSWIFT_ENTITLEMENTS:-$(cd "$(dirname "$0")/.." && pwd)/App/NegSwift/NegSwift.entitlements}"

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
