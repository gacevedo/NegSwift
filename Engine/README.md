# negswift-engine

Headless wrapper around upstream NegPy. See [../PLAN.md](../PLAN.md).

## NegPy source

NegPy is pinned as a **git submodule** at `../Vendor/NegPy` (tag/commit recorded in the parent repo).

```bash
# From NegSwift repo root (first clone or after pull)
git submodule update --init --recursive
cd Engine && uv sync
uv run negswift-engine info
```

Clone in one step:

```bash
git clone --recurse-submodules <NegSwift repo URL>
```

## Dual-repo development

To hack a sibling NegPy checkout without changing the committed submodule SHA:

```bash
cp pyproject.override.toml.example pyproject.override.toml   # reference only — see comments
uv sync && uv pip install -e ../../NegPy
```

Or reinstall editable NegPy into the venv:

```bash
uv pip install -e ../../NegPy
```

CI and release builds **never** use the override.

## Bump NegPy pin

Run from the **NegSwift repo root**. Prefer an upstream **tag** (e.g. `0.51.0`); pin a specific commit only when validating main before a tag lands.

```bash
cd Vendor/NegPy && git fetch --tags && git checkout 0.51.0
cd ../..
git add Vendor/NegPy
cd Engine && uv lock && uv sync
uv run negswift-engine info   # negpy_version should match the tag (not Unknown-dev)
cd .. && make test
```

Commit the submodule SHA bump in NegSwift (not edits inside `Vendor/NegPy` — that tree is upstream).

**Checklist after bump**

- [ ] `git submodule status` shows the new commit and is clean
- [ ] `negswift-engine info` → `negpy_version` matches the pin
- [ ] `make test` green (engine pytest + Swift unit tests)
- [ ] Manual smoke: [../docs/MANUAL_TEST_CHECKLIST.md](../docs/MANUAL_TEST_CHECKLIST.md) — at least render, sidecar round-trip, crop, export
- [ ] If upstream changed serialized config keys (e.g. `process_mode` labels), update NegSwift models/tests in the same commit

**Tag vs commit:** `git checkout 0.51.0` checks out the tagged release. To pin main at a specific SHA: `git checkout <full-or-short-sha>`.

**Dual-repo dev unchanged:** sibling NegPy via `uv pip install -e ../../NegPy` does not update the committed pin; bump the submodule when you want CI and other clones on the new version.

## Commands

```bash
uv run negswift-engine info
uv run negswift-engine open /path/to/scan.tif
uv run negswift-engine render --path /path/to/scan.tif --out preview.png --cpu
uv run negswift-engine serve --stdio
uv run negswift-engine serve --socket /tmp/negswift-engine.sock
```
