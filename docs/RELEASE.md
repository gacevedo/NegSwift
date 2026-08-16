# Release builds

NegSwift ships a frozen `negswift-engine` helper inside the app bundle. The SwiftUI shell is a normal Xcode app; only the Python engine is PyInstaller-frozen.

## Prerequisites

- macOS 14+ (match `MACOSX_DEPLOYMENT_TARGET` in the Xcode project)
- Xcode with command-line tools
- [uv](https://docs.astral.sh/uv/) and Python 3.13
- NegPy submodule: `git submodule update --init --recursive`
- **Distribution to other Macs:** Apple Developer Program membership, **Developer ID Application** certificate, and notarization credentials (`notarytool` keychain profile)

## Build a release `.app`

```bash
make build-release
```

This runs, in order:

1. `Packaging/build_engine.sh` — PyInstaller onedir from `Vendor/NegPy` → `Packaging/out/negswift-engine/`
2. `xcodebuild -configuration Release` (derived data under `App/build/`)
3. `ditto` the frozen engine into `Contents/Resources/engine/` (PyInstaller onedir)
4. **`Packaging/sign_app.sh`** — re-sign the app and every Mach-O in the bundled engine

Release builds currently run with **App Sandbox off** so the bundled PyInstaller tree can spawn from `Resources/`. Mac App Store / strict sandbox would need a one-file engine in `Contents/Helpers/` or an XPC helper.

Do **not** copy the engine into `App/NegSwift/Resources/` — Xcode's synchronized group flattens nested package metadata and Release builds fail.

The built app is at `App/build/Build/Products/Release/NegSwift.app`.

## "App is damaged and can't be opened"

macOS often shows **damaged** when Gatekeeper rejects the bundle. Common causes for NegSwift:

| Cause | Fix |
|-------|-----|
| Engine copied **after** Xcode signed the app (broken seal) | Fixed — `make build-release` re-signs automatically. Rebuild and re-copy. |
| **Ad-hoc** signature only (`-`) | Expected on other Macs. Sign with **Developer ID** and **notarize** (below). |
| Quarantine from AirDrop / zip / browser download | On the receiving Mac: `xattr -dr com.apple.quarantine /path/to/NegSwift.app` then open once via **Right-click → Open**. |

Verify the signature on the build machine:

```bash
codesign --verify --deep --strict App/build/Build/Products/Release/NegSwift.app
spctl -a -vv App/build/Build/Products/Release/NegSwift.app
```

Ad-hoc builds pass `codesign --verify` but **`spctl` rejects** until notarized.

## Distribute to other Macs (Developer ID + notarization)

### 1. One-time notarytool setup

Create an [app-specific password](https://appleid.apple.com) and store a keychain profile:

```bash
xcrun notarytool store-credentials "NegSwift-Notary" \
  --apple-id "you@example.com" \
  --team-id "YOURTEAMID" \
  --password "app-specific-password"
```

### 2. Build, sign, notarize

```bash
export NEGSWIFT_SIGN_IDENTITY="Developer ID Application: Gabriel Acevedo (TEAMID)"
make build-release          # includes re-sign with your Developer ID
export NEGSWIFT_NOTARY_PROFILE="NegSwift-Notary"
make notarize-release-app
```

Ship the **stapled** `NegSwift.app` (or a zip of it). Recipients should not see Gatekeeper blocks.

### 3. Optional: sign only (no notarization yet)

```bash
export NEGSWIFT_SIGN_IDENTITY="Developer ID Application: …"
make build-release
# make notarize-release-app   # when ready
```

Without notarization, other Macs may still prompt or block depending on macOS settings.

## Smoke test (no Xcode)

```bash
make bundle-engine
Packaging/out/negswift-engine/negswift-engine info
```

## Runtime layout

Engine binary: `NegSwift.app/Contents/Resources/engine/negswift-engine`

Resolution order:

1. `NEGSWIFT_ENGINE` environment variable
2. Bundled `Contents/Resources/engine/negswift-engine`
3. `NegSwiftEnginePath` from Info.plist (Debug venv)

The engine subprocess gets `NEGPY_USER_DIR=~/Library/Application Support/NegSwift/`.

## Distribution checklist

- [ ] `make build-release` succeeds
- [ ] `codesign --verify --deep --strict` passes on the built `.app`
- [ ] Signed with **Developer ID Application** (not ad-hoc `-`)
- [ ] `make notarize-release-app` succeeds; `spctl -a -vv` accepts on build machine
- [ ] Copy to another Mac **without** Python → import → preview → export
- [ ] No "damaged" / Gatekeeper block on the receiving Mac

## Debug vs release

| Configuration | Engine source | Sandbox |
|---------------|---------------|---------|
| Debug | venv via `NEGSWIFT_ENGINE_PATH` | Off |
| Release | Bundled `Resources/engine/` | On |

## PyInstaller warnings (benign)

| Warning | Meaning |
|---------|---------|
| `wgpu.utils.imgui` / `imgui_bundle` | Optional wgpu UI; not used headless |
| `pycparser.lextab` / `yacctab` | Generated on demand; safe to ignore |
| `libomp.dylib` | Install `brew install libomp` before `make bundle-engine` to bundle it |
