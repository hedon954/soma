#!/usr/bin/env bash

set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
device_id="${SOMA_DEVICE_ID:-${SOMA_PROFILE_DEVICE:-}}"
configuration="${SOMA_DEVICE_CONFIGURATION:-Release}"
app_path="${SOMA_DEVICE_APP_PATH:-$root_dir/build/DeviceDerivedData/Build/Products/$configuration-iphoneos/Soma.app}"
record_after_install="${SOMA_RECORD_AFTER_INSTALL:-0}"
adopt_installed_build="${SOMA_ADOPT_INSTALLED_BUILD:-0}"

if [[ -z "$device_id" ]]; then
  echo "SOMA_DEVICE_ID or SOMA_PROFILE_DEVICE is required." >&2
  exit 2
fi
if [[ ! "$configuration" =~ ^(Debug|Release)$ ]]; then
  echo "SOMA_DEVICE_CONFIGURATION must be Debug or Release." >&2
  exit 2
fi
if [[ "$record_after_install" != "1" && "$adopt_installed_build" != "1" ]]; then
  echo "Refusing to trust an installed build without SOMA_RECORD_AFTER_INSTALL=1 or SOMA_ADOPT_INSTALLED_BUILD=1." >&2
  exit 2
fi
if [[ ! -d "$app_path" ]]; then
  echo "Local signed app bundle is missing: $app_path" >&2
  exit 1
fi

device_lock_state="$(
  xcrun devicectl device info lockState --device "$device_id" 2>/dev/null
)"
canonical_device_id="$(
  printf '%s\n' "$device_lock_state" |
    awk '$1 == "•" && $2 == "deviceIdentifier:" && !found { print $3; found = 1 }'
)"
if [[ -z "$canonical_device_id" ]]; then
  echo "Unable to resolve the canonical CoreDevice identifier." >&2
  exit 1
fi

installed_line="$(
  xcrun devicectl device info apps \
    --device "$device_id" \
    --bundle-id top.hedon.soma \
    --columns '*' 2>/dev/null |
    awk '$2 == "top.hedon.soma" && !found { print; found = 1 }'
)"
if [[ -z "$installed_line" ]]; then
  echo "Soma is not installed on the selected physical device." >&2
  exit 1
fi

installed_version="$(printf '%s\n' "$installed_line" | awk '{ print $3 }')"
installed_build="$(printf '%s\n' "$installed_line" | awk '{ print $4 }')"
local_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Info.plist")"
local_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_path/Info.plist")"
if [[ "$installed_version" != "$local_version" || "$installed_build" != "$local_build" ]]; then
  echo "Installed Soma $installed_version ($installed_build) does not match local $local_version ($local_build)." >&2
  exit 1
fi

fingerprint="$(
  SOMA_DEVICE_CONFIGURATION="$configuration" \
    "$root_dir/scripts/device-app-fingerprint.sh"
)"
binary_uuid="$(
  dwarfdump --uuid "$app_path/Soma" |
    awk 'NR == 1 { print $2 }'
)"
stamp_dir="$root_dir/build/performance/device-installs"
stamp_path="$stamp_dir/$canonical_device_id-$configuration.stamp"
mkdir -p "$stamp_dir"
{
  printf 'schema=soma-device-install-v1\n'
  printf 'device_id=%s\n' "$canonical_device_id"
  printf 'configuration=%s\n' "$configuration"
  printf 'fingerprint=%s\n' "$fingerprint"
  printf 'version=%s\n' "$local_version"
  printf 'build=%s\n' "$local_build"
  printf 'binary_uuid=%s\n' "$binary_uuid"
  printf 'recorded_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} >"$stamp_path"

echo "Recorded reusable device build: Soma $local_version ($local_build), $configuration."
echo "Device build stamp: $stamp_path"
