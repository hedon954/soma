.DEFAULT_GOAL := help

.PHONY: help setup env generate build test format format-check lint server-check server-test check verify install-device archive clean

help:
	@echo "Soma development commands:"
	@echo "  make setup         Install tools, hooks, and generate the Xcode project"
	@echo "  make generate      Generate Soma.xcodeproj from project.yml"
	@echo "  make build         Build for an available iOS Simulator without signing"
	@echo "  make test          Run unit tests on an available iOS Simulator"
	@echo "  make format        Format Swift sources"
	@echo "  make lint          Run SwiftLint, actionlint, shellcheck, and repo validation"
	@echo "  make server-check  Type-check the optional Agent server"
	@echo "  make server-test   Test the optional Agent server"
	@echo "  make check         Run fast static checks without a Simulator"
	@echo "  make verify        Run static checks, build, and Simulator tests"
	@echo "  make install-device Sign, install, and launch on a connected iPhone"
	@echo "  make archive       Export a signed App Store Connect archive"
	@echo "  make clean         Remove generated project and build artifacts"

setup:
	@command -v brew >/dev/null 2>&1 || (echo "Homebrew is required: https://brew.sh" >&2; exit 1)
	brew bundle
	npm --prefix Server ci
	pre-commit install
	$(MAKE) generate
	@echo "Ready. Open Soma.xcodeproj or run make check."

env:
	./scripts/check-env.sh

generate:
	xcodegen generate --spec project.yml

build: generate
	./scripts/xcodebuild.sh build

test: generate
	./scripts/xcodebuild.sh test

format:
	swiftformat Soma SomaWidget SomaTests

format-check:
	swiftformat Soma SomaWidget SomaTests --lint

lint:
	swiftlint lint --strict --config .swiftlint.yml
	actionlint
	shellcheck scripts/*.sh
	./scripts/validate-repository.sh

server-check:
	npm --prefix Server run check

server-test:
	npm --prefix Server test

check:
	@$(MAKE) env
	@$(MAKE) format-check
	@$(MAKE) lint
	@$(MAKE) server-check

verify:
	@$(MAKE) check
	@$(MAKE) server-test
	@$(MAKE) build
	@$(MAKE) test

install-device: generate
	./scripts/install-device.sh

archive:
	./scripts/archive-testflight.sh

clean:
	rm -rf Soma.xcodeproj build
