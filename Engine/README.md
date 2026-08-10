# negswift-engine

Headless wrapper around upstream NegPy. See [../PLAN.md](../PLAN.md).

## NegPy source

| Phase | Location |
|-------|----------|
| M0–M9 | Sibling checkout at `../../NegPy` (editable path in `pyproject.toml`) |
| **M9b+** | Git submodule at `../Vendor/NegPy` — **required before M10** |

## Setup

**Early dev (sibling):**

```bash
# ~/Development/NegPy and ~/Development/NegSwift as siblings
uv sync
uv run negswift-engine info
```

**After M9b (submodule):**

```bash
git submodule update --init --recursive
uv sync
uv run negswift-engine info
```

Optional: gitignored `pyproject.override.toml` to point at a local NegPy checkout while hacking upstream (see PLAN.md §3).

## Commands (Milestone 1)

```bash
uv run negswift-engine info
uv run negswift-engine open /path/to/scan.tif
```
