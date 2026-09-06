.PHONY: sync lint format test test-swift test-native-engine test-native-engine-ios \
	compare-engines compare-linear-decode compare-s4a compare-s4b compare-s5 compare-s6 \
	test-s7-stdio bench-engine bundle-engine build-app build-release \
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

test: sync test-native-engine test-swift
	cd Engine && uv run pytest tests/ -v

test-swift:
	cd App && xcodebuild -scheme NegSwift -configuration Debug -destination 'platform=macOS' test -quiet

test-native-engine:
	cd Packages/NegSwiftEngine && swift test
	cd Packages/NegSwiftEngine && swift build

test-native-engine-ios:
	cd Packages/NegSwiftEngine && xcodebuild -scheme NegSwiftEngine \
		-destination 'generic/platform=iOS Simulator' \
		-derivedDataPath .derived \
		build

compare-engines: sync
	cd Engine && uv run python scripts/compare_engine_renders.py

compare-linear-decode: sync
	cd Engine && uv run python scripts/compare_linear_decode.py

compare-s4a: sync
	cd Engine && uv run python scripts/compare_s4a_renders.py

compare-s4b: sync
	cd Engine && uv run python scripts/compare_s4b_renders.py

compare-s5: sync
	cd Engine && uv run python scripts/compare_s5_renders.py

compare-s6: sync
	cd Engine && uv run python scripts/compare_s6_renders.py

# Point Engine pytest at the Swift binary (S7 contract).
test-s7-stdio: test-native-engine
	NEGSWIFT_ENGINE="$$(cd Packages/NegSwiftEngine && swift build --show-bin-path)/negswift-engine-swift" \
		cd Engine && uv run pytest tests/test_protocol.py tests/test_config.py -v

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
