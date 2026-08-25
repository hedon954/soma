#!/usr/bin/env bash

set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
device_id="${SOMA_PROFILE_DEVICE:-${SOMA_DEVICE_ID:-}}"
team_id="${DEVELOPMENT_TEAM:-}"
rounds="${SOMA_PROFILE_INTERACTION_ROUNDS:-30}"
fixture="${SOMA_UI_PERFORMANCE_FIXTURE:-}"
duration="${SOMA_PROFILE_DURATION:-90s}"
configuration="${SOMA_PROFILE_CONFIGURATION:-Release}"
ui_test="${SOMA_PROFILE_UI_TEST:-SomaUITests/PerformanceTabLoopUITests/testTabLoop}"
output_dir="${SOMA_PROFILE_OUTPUT_DIR:-$root_dir/build/performance/device-tab-loop}"
ui_result="$output_dir/ui-test.xcresult"
ui_log="$output_dir/ui-test.log"
ui_derived_data="$root_dir/build/DeviceUITestDerivedData"

if [[ -z "$device_id" || -z "$team_id" ]]; then
  echo "SOMA_PROFILE_DEVICE and DEVELOPMENT_TEAM are required." >&2
  exit 2
fi
if [[ ! "$rounds" =~ ^[1-9][0-9]*$ ]] || ((rounds > 100)); then
  echo "SOMA_PROFILE_INTERACTION_ROUNDS must be an integer from 1 through 100." >&2
  exit 2
fi
if [[ ! "$configuration" =~ ^[A-Za-z0-9_-]+$ ]]; then
  echo "SOMA_PROFILE_CONFIGURATION contains unsupported characters." >&2
  exit 2
fi
if [[ ! "$ui_test" =~ ^[A-Za-z0-9_/-]+$ ]]; then
  echo "SOMA_PROFILE_UI_TEST contains unsupported characters." >&2
  exit 2
fi

if ! device_lock_state="$(
  xcrun devicectl device info lockState --device "$device_id" 2>/dev/null
)"; then
  echo "Unable to read the physical device lock state." >&2
  exit 1
fi
if printf '%s\n' "$device_lock_state" | grep -q 'passcodeRequired: true'; then
  echo "Unlock the physical iPhone before starting the automated Tab profile." >&2
  exit 1
fi

mkdir -p "$output_dir"
rm -rf "$ui_result"
cd "$root_dir"
xcodegen generate --spec project.yml

old_pid="$(
  xcrun devicectl device info processes --device "$device_id" 2>/dev/null |
    awk '/\/Soma\.app\/Soma([[:space:]]|$)/ { print $1; exit }'
)"

set +e
xcodebuild test \
  -quiet \
  -project Soma.xcodeproj \
  -scheme SomaPerformance \
  -configuration "$configuration" \
  -destination "platform=iOS,id=$device_id" \
  -derivedDataPath "$ui_derived_data" \
  -clonedSourcePackagesDirPath build/SourcePackages \
  -resultBundlePath "$ui_result" \
  "-only-testing:$ui_test" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  TEST_RUNNER_SOMA_UI_TAB_ROUNDS="$rounds" \
  TEST_RUNNER_SOMA_UI_PERFORMANCE_FIXTURE="$fixture" \
  DEVELOPMENT_TEAM="$team_id" \
  CODE_SIGN_STYLE=Automatic >"$ui_log" 2>&1 &
ui_test_pid=$!
set -e

cleanup() {
  if kill -0 "$ui_test_pid" 2>/dev/null; then
    kill -TERM "$ui_test_pid" 2>/dev/null || true
    wait "$ui_test_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

deadline=$((SECONDS + 180))
while true; do
  current_pid="$(
    xcrun devicectl device info processes --device "$device_id" 2>/dev/null |
      awk '/\/Soma\.app\/Soma([[:space:]]|$)/ { print $1; exit }'
  )"
  if [[ -n "$current_pid" && "$current_pid" != "$old_pid" ]]; then
    break
  fi
  if ! kill -0 "$ui_test_pid" 2>/dev/null; then
    wait "$ui_test_pid" || true
    echo "UI test exited before Soma launched; see $ui_log" >&2
    exit 1
  fi
  if ((SECONDS >= deadline)); then
    echo "Timed out waiting for the UI-test app launch; see $ui_log" >&2
    exit 1
  fi
  sleep 1
done

profile_status=0
SOMA_PROFILE_DEVICE="$device_id" \
SOMA_PROFILE_DURATION="$duration" \
SOMA_PROFILE_RUNS=1 \
SOMA_PROFILE_INTERACTION=tabs \
SOMA_PROFILE_INTERACTION_ROUNDS="$rounds" \
SOMA_PROFILE_READY_NOTIFICATION='top.hedon.soma.performance-profile-ready' \
SOMA_PROFILE_OUTPUT_DIR="$output_dir" \
  scripts/profile-device-performance.sh || profile_status=$?

set +e
wait "$ui_test_pid"
ui_status=$?
set -e
trap - EXIT INT TERM

if ((ui_status != 0)); then
  echo "UI tab loop failed; see $ui_log and $ui_result" >&2
  exit "$ui_status"
fi
if ((profile_status != 0)); then
  exit "$profile_status"
fi

echo "Automated physical-device interaction passed: $ui_test, $rounds rounds, $configuration."
