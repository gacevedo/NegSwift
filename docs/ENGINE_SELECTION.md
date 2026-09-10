# Build-time engine selection (M16)

NegSwift links **one** rendering backend at compile time. There is no in-app Python/Swift toggle.

| Build | Scheme | Configuration | Backend |
|-------|--------|---------------|---------|
| **Default** | `NegSwift` | Debug / Release | Swift (`Packages/NegSwiftEngine`, in-process) |
| **Oracle** | `NegSwift-Python` | Debug-Python / Release-Python | Python subprocess (`Engine/negswift-engine`) |

## Xcode

- **Run the app (default):** scheme **NegSwift** (⌘R). No `make sync` required.
- **Oracle subprocess app:** scheme **NegSwift-Python**. Run `make sync` first so `Engine/.venv/bin/negswift-engine` exists.

The user-defined build setting `NEGSWIFT_ENGINE` (`swift` | `python`) maps to Swift active compilation conditions:

- `NEGSWIFT_ENGINE_SWIFT` — native engine (default)
- `NEGSWIFT_ENGINE_PYTHON` — `EngineClient`, `EngineProcess`, `EngineLocator`, bundled PyInstaller path

## Make targets

| Target | Engine | Notes |
|--------|--------|-------|
| `make build-app` | Swift | Debug `.app`; no venv |
| `make build-release` | Swift | Release `.app`; no `Contents/Resources/engine/` |
| `make build-app-python` | Python | `make sync` + Debug-Python |
| `make build-release-python` | Python | `make sync` + PyInstaller + Release-Python |

## Parity / oracle work

Python remains the **look oracle** for `make compare-*` and `Engine/` pytest. Point protocol tests at the Swift CLI with `make test-s7-stdio` (sets `NEGSWIFT_ENGINE` to `negswift-engine-swift`).

Contributors who need in-app Python A/B use the **NegSwift-Python** scheme, not Settings.

## LibRaw (Swift builds)

Camera RAW in the Swift backend needs Homebrew `libraw` for local dev (`brew install libraw`). Release packaging may bundle the dylib separately; see [RELEASE.md](RELEASE.md).
