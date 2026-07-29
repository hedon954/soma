#!/usr/bin/env bash

set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project_path="$root_dir/Soma.xcodeproj"
derived_data_path="$root_dir/build/DerivedData"
source_packages_path="$root_dir/build/SourcePackages"
action="${1:-build}"

if [[ ! -d "$project_path" ]]; then
  echo "Generated project is missing. Run: make generate" >&2
  exit 1
fi

case "$action" in
  build)
    destination="${SOMA_BUILD_DESTINATION:-generic/platform=iOS Simulator}"
    ;;
  test)
    if [[ -n "${SOMA_TEST_DESTINATION:-}" ]]; then
      destination="$SOMA_TEST_DESTINATION"
    elif [[ -n "${SOMA_SIMULATOR_DEVICE:-}" ]]; then
      destination="platform=iOS Simulator,name=$SOMA_SIMULATOR_DEVICE,OS=latest"
    else
      available_devices="$(xcrun simctl list devices available)"
      simulator_id=""
      for preferred_device in "iPhone 17 Pro" "iPhone 16 Pro" "iPhone 15 Pro" "iPhone 16" "iPhone 15"; do
        simulator_id="$(
          printf '%s\n' "$available_devices" |
            grep -F "    $preferred_device (" |
            sed -nE 's/.*\(([0-9A-F-]{36})\).*/\1/p' |
            head -1
        )"
        [[ -n "$simulator_id" ]] && break
      done

      if [[ -z "$simulator_id" ]]; then
        simulator_id="$(
          printf '%s\n' "$available_devices" |
            sed -nE '/^[[:space:]]+iPhone .* \(([0-9A-F-]{36})\)/ {
              s/.*\(([0-9A-F-]{36})\).*/\1/p
              q
            }'
        )"
      fi

      if [[ -z "$simulator_id" ]]; then
        echo "No available iPhone Simulator could be selected." >&2
        exit 1
      fi
      destination="platform=iOS Simulator,id=$simulator_id"
    fi
    ;;
  *)
    echo "Usage: $0 <build|test>" >&2
    exit 2
    ;;
esac

mkdir -p "$root_dir/build"

echo "Running '$action' for destination: $destination"

xcodebuild "$action" \
  -quiet \
  -project "$project_path" \
  -scheme Soma \
  -configuration Debug \
  -destination "$destination" \
  -derivedDataPath "$derived_data_path" \
  -clonedSourcePackagesDirPath "$source_packages_path" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO
