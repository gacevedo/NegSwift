#!/usr/bin/env bash
# Submit a signed Release .app to Apple notarization and staple the ticket.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/App/build/Build/Products/Release/NegSwift.app}"
PROFILE="${NEGSWIFT_NOTARY_PROFILE:?Set NEGSWIFT_NOTARY_PROFILE to your notarytool keychain profile name}"

test -d "$APP" || { echo "App not found: $APP" >&2; exit 1; }

ZIP="$(mktemp -t negswift-notarize.XXXXXX).zip"
trap 'rm -f "$ZIP"' EXIT

echo "Zipping $(basename "$APP")…"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "Submitting to Apple notarization…"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "Stapling ticket…"
xcrun stapler staple "$APP"

spctl -a -vv "$APP" || true
echo "Notarization complete."
