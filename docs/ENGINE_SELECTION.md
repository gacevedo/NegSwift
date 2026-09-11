# Build-time engine selection (M16)

NegSwift links **one** rendering backend at compile time. There is no in-app Python/Swift toggle.

| Build | Scheme | Configuration | Backend |
|-------|--------|---------------|---------|
| **Default** | `NegSwift` | Debug / Release | Swift (`Packages/NegSwiftEngine`, in-process) |
| **Oracle (dev)** | `NegSwift-Python` | Debug-Python / Release-Python | Python subprocess (`Engine/.venv/bin/negswift-engine`) |

## Xcode

- **Run the app (default):** scheme **NegSwift** (⌘R). No `make sync` required.
- **Oracle subprocess app (dev only):** scheme **NegSwift-Python**. Run `make sync` first so `Engine/.venv/bin/negswift-engine` exists.

The user-defined build setting `NEGSWIFT_ENGINE` (`swift` | `python`) maps to Swift active compilation conditions:

- `NEGSWIFT_ENGINE_SWIFT` — native engine (default)
- `NEGSWIFT_ENGINE_PYTHON` — `EngineClient`, `EngineProcess`, `EngineLocator`, venv subprocess

## Make targets

| Target | Engine | Notes |
|--------|--------|-------|
| `make build-app` | Swift | Debug `.app`; no venv |
| `make build-release` | Swift | Release `.app`; no Python |
| `make build-app-python` | Python | `make sync` + Debug-Python (dev oracle) |

## Parity / oracle work

Python remains the **look oracle** for `make compare-*` and `Engine/` pytest. Point protocol tests at the Swift CLI with `make test-s7-stdio` (sets `NEGSWIFT_ENGINE` to `negswift-engine-swift`).

Contributors who need in-app Python A/B use the **NegSwift-Python** scheme, not Settings. NegPy is **not** bundled in release builds.

## LibRaw (Swift builds)

Camera RAW needs LibRaw at **build** time (`brew install libraw libomp`). `make build-release` bundles `libraw_r` and its runtime deps into `Contents/Frameworks/`. Debug builds link Homebrew directly; see [RELEASE.md](RELEASE.md).
