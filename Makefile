.PHONY: sync lint format test test-engine test-swift test-native-engine \
	compare-engines compare-linear-decode compare-s4a compare-s4b compare-s5 compare-s6 \
	compare-s8 compare-s9 compare-s9-target compare-s10b compare-s11 compare-s12 compare-s13 compare-s14 \
	compare-s13l-dust \
	test-s7-stdio test-s9-stdio test-s10a-stdio test-s10b-stdio test-s11-stdio bench-engine bench-native bundle-engine \
	build-app build-app-python build-release build-release-python \
	stage-engine-in-release-app sign-release-app notarize-release-app all

XCODE_DERIVED := App/build
RELEASE_APP := $(XCODE_DERIVED)/Build/Products/Release/NegSwift.app
ENGINE_BUNDLE := Packaging/out/negswift-engine

# Homebrew LibRaw is single-arch (/opt/homebrew = arm64, /usr/local = x86_64).
# Universal Release then fails linking the other slice (see Package.swift).
# NEGSWIFT_LIBRAW=0 skips LibRaw and allows a fat binary without camera RAW.
RELEASE_XCODE_ARGS :=
ifeq ($(NEGSWIFT_LIBRAW),0)
else
  LIBRAW_HEADER := $(firstword $(wildcard /opt/homebrew/opt/libraw/include/libraw/libraw.h) $(wildcard /usr/local/opt/libraw/include/libraw/libraw.h))
  ifneq ($(LIBRAW_HEADER),)
    RELEASE_XCODE_ARGS := ONLY_ACTIVE_ARCH=YES
  endif
endif

sync:
	@test -f Vendor/NegPy/VERSION || (echo "NegPy submodule missing — run: git submodule update --init --recursive" && exit 1)
	cd Engine && uv sync --locked

lint:
	cd Engine && uv run ruff check negswift_engine tests

format:
	cd Engine && uv run ruff format negswift_engine tests
	cd Engine && uv run ruff check --fix negswift_engine tests

test: test-native-engine test-swift test-engine

test-engine: sync
	cd Engine && uv run pytest tests/ -v

test-swift:
	cd App && xcodebuild -scheme NegSwift -configuration Debug -destination 'platform=macOS' test -quiet

test-native-engine:
	cd Packages/NegSwiftEngine && swift test
	cd Packages/NegSwiftEngine && swift build

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

compare-s8: sync
	cd Engine && uv run python scripts/compare_s8_renders.py

compare-s9: sync
	cd Engine && uv run python scripts/compare_s9_exports.py

compare-s9-target: sync
	cd Engine && uv run python scripts/compare_s9_target_exports.py

# Point Engine pytest at the Swift binary (S7 contract).
test-s7-stdio: test-native-engine
	NEGSWIFT_ENGINE="$$(cd Packages/NegSwiftEngine && swift build --show-bin-path)/negswift-engine-swift" \
		cd Engine && uv run pytest tests/test_protocol.py tests/test_config.py -v

# S9: reuse test_export.py against Swift serve --stdio.
test-s9-stdio: test-native-engine
	NEGSWIFT_ENGINE="$$(cd Packages/NegSwiftEngine && swift build --show-bin-path)/negswift-engine-swift" \
		cd Engine && uv run pytest tests/test_export.py -v

# S10a: heal mapping + undo against Swift serve --stdio.
test-s10a-stdio: test-native-engine
	NEGSWIFT_ENGINE="$$(cd Packages/NegSwiftEngine && swift build --show-bin-path)/negswift-engine-swift" \
		cd Engine && uv run pytest tests/test_append_heal_stroke.py tests/test_undo_last_heal.py -v

compare-s10b: sync
	cd Engine && uv run python scripts/compare_s10b_renders.py

# S10b: optical dust keys against Swift serve --stdio.
test-s10b-stdio: test-native-engine
	NEGSWIFT_ENGINE="$$(cd Packages/NegSwiftEngine && swift build --show-bin-path)/negswift-engine-swift" \
		cd Engine && uv run pytest tests/test_config.py -k 'dust' -v

compare-s11: sync
	cd Engine && uv run python scripts/compare_s11_renders.py

# S11: autocrop detect-once against Swift serve --stdio.
test-s11-stdio: test-native-engine
	NEGSWIFT_ENGINE="$$(cd Packages/NegSwiftEngine && swift build --show-bin-path)/negswift-engine-swift" \
		cd Engine && uv run pytest tests/test_autocrop.py tests/test_crop.py tests/test_render.py -k 'autocrop or crop_preview_full or detect' -v

# S12: CPU-vs-Metal MAE (used WGSL stages). Skips if Metal is unavailable.
compare-s12:
	cd Packages/NegSwiftEngine && swift test --filter MetalParityTests

# S13: reprint cache + Metal geometry + resident upload + decode reuse + Accelerate + splash/thumbs + progressive paint + GPU present + X-Trans PPG + queue/prefetch + disk preview cache.
compare-s13:
	cd Packages/NegSwiftEngine && swift test --filter ReprintCacheTests
	cd Packages/NegSwiftEngine && swift test --filter MetalGeometryTests
	cd Packages/NegSwiftEngine && swift test --filter DecodeReuseTests
	cd Packages/NegSwiftEngine && swift test --filter AccelerateConvertTests
	cd Packages/NegSwiftEngine && swift test --filter SplashThumbTests
	cd Packages/NegSwiftEngine && swift test --filter ProgressivePaintTests
	cd Packages/NegSwiftEngine && swift test --filter GPUPresentTests
	cd Packages/NegSwiftEngine && swift test --filter RawDecodeTests
	cd Packages/NegSwiftEngine && swift test --filter QueuePrefetchTests
	cd Packages/NegSwiftEngine && swift test --filter ProcessedPreviewDiskCacheTests
	cd Packages/NegSwiftEngine && swift test --filter ExportPerfTests

# S13i: time X-Trans preview AHD+OpenMP vs PPG+1-thread (skip-if-missing local RAF).
compare-s13i-timing:
	cd Packages/NegSwiftEngine && swift test --filter XTransPreviewTimingTests

# S13l: CPU-vs-Metal optical dust MAE (detect + bake).
compare-s13l-dust:
	cd Packages/NegSwiftEngine && swift test --filter MetalDustTests

# S14: TIFF still green; synthetic DNG + skip-if-missing local RAW (NEF/ARW/…).
compare-s14: sync
	cd Engine && uv run python scripts/compare_s14_raw.py

bench-engine:
	cd Engine && uv run python scripts/bench_render.py -o tests/fixtures/perf_baseline.json

# S13l: native Swift stage timings on a real scan (skip-if-missing local TIFF).
bench-native:
	cd Packages/NegSwiftEngine && \
		NEGSWIFT_PERF_SCAN="$${NEGSWIFT_PERF_SCAN:-/Users/gacevedo/Downloads/Kodak Portra Gold 120 K6500-008.TIFF}" \
		NEGSWIFT_PERF_OUTPUT="$${NEGSWIFT_PERF_OUTPUT:-Tests/NegSwiftEngineTests/Fixtures/native_perf_baseline.json}" \
		swift test --filter NativeStageTimingTests 2>&1 | tee /tmp/negswift_bench_native.log

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

build-app-python: sync
	mkdir -p App/NegSwift/Legal
	cp NOTICE LICENSE App/NegSwift/Legal/
	cd App && xcodebuild -scheme NegSwift-Python -configuration Debug-Python build

build-release:
ifneq ($(RELEASE_XCODE_ARGS),)
	@echo "Release: $(RELEASE_XCODE_ARGS) (Homebrew LibRaw is single-arch; NEGSWIFT_LIBRAW=0 for universal without RAW)."
endif
	mkdir -p App/NegSwift/Legal
	cp NOTICE LICENSE App/NegSwift/Legal/
	rm -rf App/NegSwift/Resources/engine
	cd App && xcodebuild -scheme NegSwift -configuration Release -derivedDataPath build $(RELEASE_XCODE_ARGS) build
	$(MAKE) sign-release-app

build-release-python: sync bundle-engine
ifneq ($(RELEASE_XCODE_ARGS),)
	@echo "Release: $(RELEASE_XCODE_ARGS) (Homebrew LibRaw is single-arch; NEGSWIFT_LIBRAW=0 for universal without RAW)."
endif
	mkdir -p App/NegSwift/Legal
	cp NOTICE LICENSE App/NegSwift/Legal/
	rm -rf App/NegSwift/Resources/engine
	cd App && xcodebuild -scheme NegSwift-Python -configuration Release-Python -derivedDataPath build $(RELEASE_XCODE_ARGS) build
	$(MAKE) stage-engine-in-release-app
	$(MAKE) sign-release-app

all: lint test build-app
