# Release builds

`make build-release` produces a **Swift-only** `.app`. The native engine in `Packages/NegSwiftEngine` runs in-process. NegPy is not bundled — it remains the development parity oracle via `Engine/` and `make compare-*`.

## Prerequisites

- macOS 14+ (match `MACOSX_DEPLOYMENT_TARGET` in the Xcode project)
- Xcode with command-line tools
- **Distribution to other Macs:** Apple Developer Program membership, **Developer ID Application** certificate, and notarization credentials (`notarytool` keychain profile)

## Build a release `.app`

```bash
make build-release
```

This runs, in order:

1. `xcodebuild -scheme NegSwift -configuration Release` (derived data under `App/build/`)
2. **`Packaging/bundle_libraw.sh`** — copy LibRaw + deps into `Contents/Frameworks/` (fails fast if the build used the LibRaw stub)
3. **`Packaging/sign_app.sh`** — sign bundled dylibs and the app

No `Contents/Resources/engine/` directory is staged. When LibRaw is linked at build time, `make build-release` copies `libraw_r` and its Homebrew runtime deps into `Contents/Frameworks/` and rewrites load paths so Camera RAW works without `brew install libraw` on the target Mac.

### Release architecture (LibRaw)

**Prerequisites on the build Mac:** `brew install libraw libomp` (LibRaw links OpenMP for demosaic).

Debug builds already set `ONLY_ACTIVE_ARCH=YES`. Release defaults to a **universal** binary (arm64 + x86_64), which **cannot link** Homebrew LibRaw — Homebrew ships a **single-arch** `libraw_r` (`/opt/homebrew` on Apple Silicon, `/usr/local` on Intel). A universal Release build therefore compiles the **LibRaw stub** and Camera RAW fails at runtime with `Camera RAW requires LibRaw`.

`make build-release` detects Homebrew LibRaw and passes **`ONLY_ACTIVE_ARCH=YES`** automatically, producing an **arm64-only** app on Apple Silicon (or **x86_64-only** on Intel) with Camera RAW enabled and bundled.

| Goal | Command |
|------|---------|
| Release with Camera RAW (default when `brew install libraw`) | `make build-release` → single-arch for the build machine + bundled Frameworks |
| Universal binary, **no** camera RAW | `NEGSWIFT_LIBRAW=0 make build-release` |
| Universal binary **with** RAW | Build or install a **universal** LibRaw and link it from `Package.swift` (not Homebrew's default) |

If you previously built without LibRaw, clean before rebuilding:

```bash
rm -rf App/build
make build-release
```

Verify LibRaw is linked and bundled:

```bash
otool -L App/build/Build/Products/Release/NegSwift.app/Contents/MacOS/NegSwift | grep libraw
ls App/build/Build/Products/Release/NegSwift.app/Contents/Frameworks/
```

Verify the built executable:

```bash
lipo -info App/build/Build/Products/Release/NegSwift.app/Contents/MacOS/NegSwift
```

The built app is at `App/build/Build/Products/Release/NegSwift.app`.

## "App is damaged and can't be opened"

macOS often shows **damaged** when Gatekeeper rejects the bundle. Common causes for NegSwift:

| Cause | Fix |
|-------|-----|
| **Ad-hoc** signature only (`-`) | Expected on other Macs. Sign with **Developer ID** and **notarize** (below). |
| Quarantine from AirDrop / zip / browser download | On the receiving Mac: `xattr -dr com.apple.quarantine /path/to/NegSwift.app` then open once via **Right-click → Open**. |

Verify the signature on the build machine:

```bash
codesign --verify --deep --strict App/build/Build/Products/Release/NegSwift.app
spctl -a -vv App/build/Build/Products/Release/NegSwift.app
```

Ad-hoc builds pass `codesign --verify` but **`spctl` rejects** until notarized.

**Local ad-hoc signing** (`NEGSWIFT_SIGN_IDENTITY` unset) omits hardened runtime so bundled LibRaw dylibs load. **Developer ID** release builds use hardened runtime on the app and every bundled dylib (same Team ID).

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

## Runtime layout

| Build | Engine |
|-------|--------|
| **NegSwift** (default) | In-process `NegSwiftEngine`; no subprocess |

## Distribution checklist

- [ ] `make build-release` succeeds
- [ ] `codesign --verify --deep --strict` passes on the built `.app`
- [ ] Signed with **Developer ID Application** (not ad-hoc `-`)
- [ ] `make notarize-release-app` succeeds; `spctl -a -vv` accepts on build machine
- [ ] Copy to another Mac → import → preview → export
- [ ] No "damaged" / Gatekeeper block on the receiving Mac

## Debug vs release

| Scheme | Debug | Release |
|--------|-------|---------|
| **NegSwift** (Swift) | In-process native | In-process native |

App Sandbox is **off** for release builds today.
