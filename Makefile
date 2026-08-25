.DEFAULT_GOAL := help

.PHONY: help setup env generate build test format format-check lint server-check server-test perf-check perf-profile-device db-migrate-create db-migrate-status db-migrate check verify online-check install-device archive clean

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
	@echo "  make db-migrate-create name=<name>  Create the next PostgreSQL migration"
	@echo "  make db-migrate-status              Show PostgreSQL migration status"
	@echo "  make db-migrate                     Apply pending PostgreSQL migrations"
	@echo "  make check         Run fast static checks without a Simulator"
	@echo "  make verify        Run static checks, build, and Simulator tests"
	@echo "  make perf-profile-device  Reuse an installed Release and run the bounded physical-device profile"
	@echo "  make online-check  Block external distribution while mail credentials live in the App"
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
	swiftformat Soma SomaWidget SomaTests SomaUITests

format-check:
	swiftformat Soma SomaWidget SomaTests SomaUITests --lint

lint:
	swiftlint lint --strict --config .swiftlint.yml
	actionlint
	shellcheck scripts/*.sh
	./scripts/validate-repository.sh

server-check:
	npm --prefix Server run check

server-test:
	npm --prefix Server test

perf-check:
	ruby ./scripts/check-performance-hotpaths.rb
	ruby -c ./scripts/analyze-app-launch-life-cycle.rb >/dev/null
	ruby -c ./scripts/analyze-animation-hitches.rb >/dev/null
	ruby -c ./scripts/analyze-tab-signposts.rb >/dev/null
	ruby ./scripts/analyze-tab-signposts.rb --minimum-samples 4 --minimum-per-target 1 --maximum-p95-ms 100 ./scripts/fixtures/tab-signposts.xml >/dev/null
	@if ruby ./scripts/analyze-tab-signposts.rb --maximum-p95-ms 70 ./scripts/fixtures/tab-signposts.xml >/dev/null 2>&1; then echo "Tab signpost budget fixture must be rejected." >&2; exit 1; fi

perf-profile-device:
	./scripts/profile-device-harness.sh

db-migrate-create:
	@test -n "$(name)" || (echo "Usage: make db-migrate-create name=<snake_case_name>" >&2; exit 1)
	npm --prefix Server run db:migrate:create -- "$(name)"

db-migrate-status:
	npm --prefix Server run db:migrate:status

db-migrate:
	npm --prefix Server run db:migrate

check:
	@$(MAKE) env
	@$(MAKE) format-check
	@$(MAKE) lint
	@$(MAKE) perf-check
	@$(MAKE) server-check

verify:
	@$(MAKE) check
	@$(MAKE) server-test
	@$(MAKE) build
	@$(MAKE) test

online-check:
	./scripts/online-check.sh

install-device: generate
	./scripts/install-device.sh

archive:
	./scripts/archive-testflight.sh

clean:
	rm -rf Soma.xcodeproj build
