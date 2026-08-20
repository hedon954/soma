#!/usr/bin/env bash

set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project_path="$root_dir/Soma.xcodeproj"
derived_data_path="$root_dir/build/DerivedData"
source_packages_path="$root_dir/build/SourcePackages"
action="${1:-build}"
result_bundle_path="$root_dir/build/Soma-${action}.xcresult"

if [[ ! -d "$project_path" ]]; then
  echo "Generated project is missing. Run: make generate" >&2
  exit 1
fi

simulator_arch="$(uname -m)"
case "$simulator_arch" in
  arm64 | aarch64) simulator_arch="arm64" ;;
  *) simulator_arch="x86_64" ;;
esac

select_simulator_id() {
  local available_devices preferred_device
  local simulator_id=""
  available_devices="$(xcrun simctl list devices available)"
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
    return 1
  fi
  printf '%s\n' "$simulator_id"
}

destination=""
case "$action" in
  build)
    if [[ -n "${SOMA_BUILD_DESTINATION:-}" ]]; then
      destination="$SOMA_BUILD_DESTINATION"
    else
      destination="platform=iOS Simulator,id=$(select_simulator_id),arch=${simulator_arch}"
    fi
    ;;
  test)
    if [[ -n "${SOMA_TEST_DESTINATION:-}" ]]; then
      destination="$SOMA_TEST_DESTINATION"
    elif [[ -n "${SOMA_SIMULATOR_DEVICE:-}" ]]; then
      destination="platform=iOS Simulator,name=${SOMA_SIMULATOR_DEVICE},arch=${simulator_arch},OS=latest"
    else
      destination="platform=iOS Simulator,id=$(select_simulator_id),arch=${simulator_arch}"
    fi
    ;;
  *)
    echo "Usage: $0 <build|test>" >&2
    exit 2
    ;;
esac

mkdir -p "$root_dir/build"
rm -rf "$result_bundle_path"

echo "Running '$action' for destination: $destination"

set +e
xcodebuild "$action" \
  -quiet \
  -project "$project_path" \
  -scheme Soma \
  -configuration Debug \
  -destination "$destination" \
  -derivedDataPath "$derived_data_path" \
  -clonedSourcePackagesDirPath "$source_packages_path" \
  -resultBundlePath "$result_bundle_path" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO
status=$?
set -e

if [[ "$status" -ne 0 ]]; then
  echo "xcodebuild $action failed with status $status" >&2
  if [[ -d "$result_bundle_path" ]]; then
    echo "Result bundle: $result_bundle_path" >&2
    xcrun xcresulttool get test-results summary --path "$result_bundle_path" 2>/dev/null || true
    xcrun xcresulttool get test-results tests --path "$result_bundle_path" 2>/dev/null || true
    xcrun xcresulttool get build-results --path "$result_bundle_path" 2>/dev/null || true
  fi
  exit "$status"
fi
