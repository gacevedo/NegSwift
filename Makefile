.PHONY: sync lint format test test-swift bench-engine bundle-engine build-app build-release \
	stage-engine-in-release-app sign-release-app notarize-release-app all

XCODE_DERIVED := App/build
RELEASE_APP := $(XCODE_DERIVED)/Build/Products/Release/NegSwift.app
ENGINE_BUNDLE := Packaging/out/negswift-engine

sync:
	@test -f Vendor/NegPy/VERSION || (echo "NegPy submodule missing — run: git submodule update --init --recursive" && exit 1)
	cd Engine && uv sync --locked

lint:
	cd Engine && uv run ruff check negswift_engine tests

format:
	cd Engine && uv run ruff format negswift_engine tests
	cd Engine && uv run ruff check --fix negswift_engine tests

test: sync test-swift
	cd Engine && uv run pytest tests/ -v

test-swift:
	cd App && xcodebuild -scheme NegSwift -configuration Debug -destination 'platform=macOS' test -quiet

bench-engine:
	cd Engine && uv run python scripts/bench_render.py -o tests/fixtures/perf_baseline.json

bundle-engine:
	./Packaging/build_engine.sh

# Copy frozen engine into Resources/ (PyInstaller onedir; sandbox off for Release until onefile/XPC).
stage-engine-in-release-app:
	@test -d "$(RELEASE_APP)" || (echo "Release .app missing — run xcodebuild Release first" >&2; exit 1)
	@test -x "$(ENGINE_BUNDLE)/negswift-engine" || (echo "Engine bundle missing — run make bundle-engine first" >&2; exit 1)
	rm -rf "$(RELEASE_APP)/Contents/Resources/engine" "$(RELEASE_APP)/Contents/Helpers/engine"
	ditto "$(ENGINE_BUNDLE)" "$(RELEASE_APP)/Contents/Resources/engine"

sign-release-app:
	chmod +x Packaging/sign_app.sh
	./Packaging/sign_app.sh "$(RELEASE_APP)"

notarize-release-app:
	chmod +x Packaging/notarize_app.sh
	./Packaging/notarize_app.sh "$(RELEASE_APP)"

build-app:
	mkdir -p App/NegSwift/Legal
	cp NOTICE LICENSE App/NegSwift/Legal/
	rm -rf App/NegSwift/Resources/engine
	cd App && xcodebuild -scheme NegSwift -configuration Debug build

build-release: bundle-engine
	mkdir -p App/NegSwift/Legal
	cp NOTICE LICENSE App/NegSwift/Legal/
	rm -rf App/NegSwift/Resources/engine
	cd App && xcodebuild -scheme NegSwift -configuration Release -derivedDataPath build build
	$(MAKE) stage-engine-in-release-app
	$(MAKE) sign-release-app

all: lint test build-app
