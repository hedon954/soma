#!/usr/bin/env bash

set -euo pipefail

destination="${1:?Usage: install-ci-swiftformat.sh DESTINATION}"
version="0.64.5"
checksum="ec017c91fdd46233e5a22dc43ff9564a3cc4b37023d3b4681b6c7d7b781de113"
temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT

curl --fail --location --retry 3 --silent --show-error \
  "https://github.com/nicklockwood/SwiftFormat/releases/download/$version/swiftformat.zip" \
  --output "$temporary_dir/swiftformat.zip"
printf '%s  %s\n' "$checksum" "$temporary_dir/swiftformat.zip" | shasum -a 256 --check
unzip -q "$temporary_dir/swiftformat.zip" -d "$temporary_dir/extracted"
mkdir -p "$destination"
install -m 755 "$temporary_dir/extracted/swiftformat" "$destination/swiftformat"
test "$("$destination/swiftformat" --version)" = "$version"
"$destination/swiftformat" --version
