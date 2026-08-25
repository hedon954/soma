#!/usr/bin/env bash

set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project_path="$root_dir/Soma.xcodeproj"
derived_data_path="$root_dir/build/DeviceDerivedData"
source_packages_path="$root_dir/build/SourcePackages"
team_id="${DEVELOPMENT_TEAM:-}"
device_id="${SOMA_DEVICE_ID:-}"
configuration="${SOMA_DEVICE_CONFIGURATION:-Debug}"

if [[ -z "$team_id" ]]; then
  echo "DEVELOPMENT_TEAM is required. Example: DEVELOPMENT_TEAM=ABCDE12345 make install-device" >&2
  exit 2
fi
if [[ ! "$configuration" =~ ^(Debug|Release)$ ]]; then
  echo "SOMA_DEVICE_CONFIGURATION must be Debug or Release." >&2
  exit 2
fi

if [[ ! -d "$project_path" ]]; then
  echo "Generated project is missing. Run: make generate" >&2
  exit 1
fi

if [[ -z "$device_id" ]]; then
  destinations="$(xcodebuild -project "$project_path" -scheme Soma -showdestinations)"
  device_id="$(
    printf '%s\n' "$destinations" |
      sed -nE '/platform:iOS,/ {
        /placeholder/! {
          s/.*id:([^,]+), name:.*/\1/p
        }
      }' |
      head -1
  )"
fi

if [[ -z "$device_id" ]]; then
  echo "No connected physical iPhone is available. Connect, unlock, trust, and enable Developer Mode." >&2
  exit 1
fi

mkdir -p "$derived_data_path" "$source_packages_path"

echo "Building Soma ($configuration) for physical device: $device_id"

xcodebuild build \
  -quiet \
  -project "$project_path" \
  -scheme Soma \
  -configuration "$configuration" \
  -destination "platform=iOS,id=$device_id" \
  -derivedDataPath "$derived_data_path" \
  -clonedSourcePackagesDirPath "$source_packages_path" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$team_id" \
  CODE_SIGN_STYLE=Automatic

app_path="$derived_data_path/Build/Products/$configuration-iphoneos/Soma.app"
if [[ ! -d "$app_path" ]]; then
  echo "Signed app bundle was not produced at: $app_path" >&2
  exit 1
fi

echo "Installing Soma on physical device: $device_id"
xcrun devicectl device install app --device "$device_id" "$app_path"

# 安装成功后记录产品输入指纹。后续性能录制只校验并复用这个 Release，绝不
# 在 profiling 命令里隐式重新编译或重新安装。
SOMA_DEVICE_ID="$device_id" \
SOMA_DEVICE_CONFIGURATION="$configuration" \
SOMA_DEVICE_APP_PATH="$app_path" \
SOMA_RECORD_AFTER_INSTALL=1 \
  "$root_dir/scripts/record-device-install-stamp.sh"

echo "Launching Soma"
if ! launch_output="$(
  xcrun devicectl device process launch \
    --device "$device_id" \
    --terminate-existing \
    top.hedon.soma 2>&1
)"; then
  printf '%s\n' "$launch_output" >&2
  if [[ "$launch_output" == *"reason: Locked"* ]]; then
    echo "Soma is installed. Unlock the iPhone and open it manually." >&2
    exit 0
  fi
  exit 1
fi
printf '%s\n' "$launch_output"
