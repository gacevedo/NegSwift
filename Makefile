.PHONY: sync lint format test test-swift build-app all

sync:
	@test -f Vendor/NegPy/VERSION || (echo "NegPy submodule missing — run: git submodule update --init --recursive" && exit 1)
	cd Engine && uv sync

lint:
	cd Engine && uv run ruff check negswift_engine tests

format:
	cd Engine && uv run ruff format negswift_engine tests
	cd Engine && uv run ruff check --fix negswift_engine tests

test: sync test-swift
	cd Engine && uv run pytest tests/ -v

test-swift:
	cd App && xcodebuild -scheme NegSwift -configuration Debug -destination 'platform=macOS' test -quiet

build-app:
	mkdir -p App/NegSwift/Legal
	cp NOTICE LICENSE App/NegSwift/Legal/
	cd App && xcodebuild -scheme NegSwift -configuration Debug build

all: lint test build-app
