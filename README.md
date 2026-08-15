# NegSwift

macOS-native **lite** shell for [NegPy](https://github.com/marcinz606/NegPy) — film-negative processing with a simpler SwiftUI interface, backed by upstream NegPy as a drop-in engine.

**License:** GPL-3.0 (required by NegPy). See [LICENSE](LICENSE).

## Status

**M0–M9b complete** (M3 partial: no `cancel`/socket). **Next: M10** bundle.

See **[PLAN.md](PLAN.md)** for the full roadmap. Agents: read **[AGENTS.md](AGENTS.md)** first.

```bash
make sync      # init submodule + uv sync (first time)
make test      # engine pytest + Swift unit tests
make build-app # Xcode Debug build
```

## Layout

```
NegSwift/
├── Vendor/NegPy/        # upstream engine (git submodule, pinned SHA)
├── App/                 # SwiftUI macOS app (Xcode)
├── Engine/              # Thin Python daemon + CLI (imports negpy)
├── Packaging/           # PyInstaller / embedded CPython (M10)
└── docs/                # Manual test checklists, protocol spec
```

## Development

```bash
git clone --recurse-submodules <NegSwift repo URL>
cd NegSwift
make sync
make test
make build-app # Xcode Debug build
```

If you already cloned without submodules:

```bash
git submodule update --init --recursive
make sync
```

NegPy contributors can point the engine at a sibling checkout via `Engine/pyproject.override.toml` (see [Engine/README.md](Engine/README.md)).

**M9b onward:** CI and packaging use `Vendor/NegPy` only — not `../../NegPy`.

See [PLAN.md](PLAN.md) — **M10 (bundling)** requires M9b complete.
