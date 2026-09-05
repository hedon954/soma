#!/usr/bin/env bash

set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
requested_device_id="${SOMA_PROFILE_DEVICE:-${SOMA_DEVICE_ID:-}}"
mode="${SOMA_PROFILE_INTERACTION:-tabs}"
rounds="${SOMA_PROFILE_INTERACTION_ROUNDS:-10}"
duration="${SOMA_PROFILE_DURATION:-75s}"
output_root="${SOMA_PROFILE_OUTPUT_DIR:-$root_dir/build/performance/device-harness-$mode}"
fixture="${SOMA_UI_PERFORMANCE_FIXTURE:-long-stream-markdown-completion}"
post_fixture_delay_seconds="${SOMA_PROFILE_DELAY_SECONDS:-1}"
fast_stream="${SOMA_PROFILE_FAST_STREAM:-0}"
configuration="${SOMA_DEVICE_CONFIGURATION:-Release}"
start_timeout_seconds="${SOMA_PROFILE_START_TIMEOUT_SECONDS:-15}"
total_timeout_seconds="${SOMA_PROFILE_TIMEOUT_SECONDS:-120}"
profile_runs="${SOMA_PROFILE_RUNS:-1}"
profile_templates="${SOMA_PROFILE_TEMPLATES:-${SOMA_PROFILE_TEMPLATE:-Time Profiler}}"

if [[ -z "$requested_device_id" ]]; then
  echo "SOMA_PROFILE_DEVICE is required." >&2
  exit 2
fi
if [[ "$configuration" != "Release" ]]; then
  echo "Physical-device performance evidence requires SOMA_DEVICE_CONFIGURATION=Release." >&2
  exit 2
fi
if [[ ! "$mode" =~ ^(tabs|sessions|scroll)$ ]]; then
  echo "SOMA_PROFILE_INTERACTION must be tabs, sessions, or scroll." >&2
  exit 2
fi
if [[ ! "$rounds" =~ ^[1-9][0-9]*$ ]] || ((rounds > 100)); then
  echo "SOMA_PROFILE_INTERACTION_ROUNDS must be an integer from 1 through 100." >&2
  exit 2
fi
if [[ ! "$post_fixture_delay_seconds" =~ ^[0-9]+$ ]] ||
  ((post_fixture_delay_seconds > 30)); then
  echo "SOMA_PROFILE_DELAY_SECONDS must be an integer from 0 through 30." >&2
  exit 2
fi
if [[ ! "$fast_stream" =~ ^(0|1)$ ]]; then
  echo "SOMA_PROFILE_FAST_STREAM must be 0 or 1." >&2
  exit 2
fi
if [[ ! "$fixture" =~ ^[a-z0-9-]+$ ]]; then
  echo "SOMA_UI_PERFORMANCE_FIXTURE contains unsupported characters." >&2
  exit 2
fi
if [[ "$profile_runs" != "1" ]]; then
  echo "The installed-Release harness records one trace per isolated App launch; SOMA_PROFILE_RUNS must be 1." >&2
  exit 2
fi
if [[ "$profile_templates" == *,* ]]; then
  echo "Record one Instruments template per isolated App launch; pass a single SOMA_PROFILE_TEMPLATE." >&2
  exit 2
fi

device_details="$(
  xcrun devicectl device info details --device "$requested_device_id" 2>/dev/null
)"
canonical_device_id="$(
  printf '%s\n' "$device_details" |
    awk '/^• identifier:/ && !found { print $3; found = 1 }'
)"
xctrace_device_id="$(
  printf '%s\n' "$device_details" |
    awk '/^[[:space:]]*• udid:/ && !found { print $3; found = 1 }'
)"
if [[ -z "$canonical_device_id" || -z "$xctrace_device_id" ]]; then
  echo "Unable to resolve CoreDevice and xctrace identifiers for the iPhone." >&2
  exit 1
fi

device_lock_state="$(
  xcrun devicectl device info lockState --device "$canonical_device_id" 2>/dev/null
)"
if [[ "$device_lock_state" == *"passcodeRequired: true"* ]]; then
  echo "Unlock the physical iPhone before profiling." >&2
  exit 1
fi
xctrace_devices="$(xcrun xctrace list devices 2>/dev/null)"
if [[ "$xctrace_devices" != *"($xctrace_device_id)"* ]]; then
  echo "The iPhone is connected to CoreDevice but unavailable to xctrace." >&2
  exit 1
fi

reset_instruments_helper() {
  local developer_dir helper_path helper_pid refreshed_devices
  developer_dir="$(xcode-select -p)"
  helper_path="$(dirname "$developer_dir")/SharedFrameworks/DVTInstrumentsFoundation.framework/Resources/DTServiceHub"

  while IFS= read -r helper_pid; do
    [[ -z "$helper_pid" ]] || kill -TERM "$helper_pid" 2>/dev/null || true
  done < <(
    ps -axo pid=,command= |
      awk -v helper_path="$helper_path" 'index($0, helper_path) > 0 { print $1 }'
  )

  # Asking xctrace for its device list restarts the exact Xcode helper. Bound the
  # recovery so a broken Instruments service never turns into another long wait.
  for _ in 1 2 3 4 5; do
    refreshed_devices="$(xcrun xctrace list devices 2>/dev/null || true)"
    [[ "$refreshed_devices" != *"($xctrace_device_id)"* ]] || return 0
    sleep 1
  done
  return 1
}

stamp_path="$root_dir/build/performance/device-installs/$canonical_device_id-Release.stamp"
if [[ ! -f "$stamp_path" ]]; then
  echo "No reusable Release install stamp exists for this iPhone." >&2
  echo "Run once: SOMA_DEVICE_CONFIGURATION=Release make install-device" >&2
  exit 1
fi

stamp_value() {
  local key="$1"
  awk -F= -v key="$key" '$1 == key && !found { sub(/^[^=]*=/, ""); print; found = 1 }' \
    "$stamp_path"
}

current_fingerprint="$(
  SOMA_DEVICE_CONFIGURATION=Release "$root_dir/scripts/device-app-fingerprint.sh"
)"
installed_fingerprint="$(stamp_value fingerprint)"
if [[ -z "$installed_fingerprint" || "$installed_fingerprint" != "$current_fingerprint" ]]; then
  echo "The installed Release is stale relative to current App sources." >&2
  echo "Run once: SOMA_DEVICE_CONFIGURATION=Release make install-device" >&2
  exit 1
fi

installed_line="$(
  xcrun devicectl device info apps \
    --device "$canonical_device_id" \
    --bundle-id top.hedon.soma \
    --columns '*' 2>/dev/null |
    awk '$2 == "top.hedon.soma" && !found { print; found = 1 }'
)"
if [[ -z "$installed_line" ]]; then
  echo "Soma is not installed on the selected iPhone." >&2
  exit 1
fi
installed_version="$(printf '%s\n' "$installed_line" | awk '{ print $3 }')"
installed_build="$(printf '%s\n' "$installed_line" | awk '{ print $4 }')"
if [[ "$installed_version" != "$(stamp_value version)" ||
  "$installed_build" != "$(stamp_value build)" ]]; then
  echo "Installed Soma version no longer matches the reusable Release stamp." >&2
  echo "Run once: SOMA_DEVICE_CONFIGURATION=Release make install-device" >&2
  exit 1
fi

wait_for_fixture_completion=0
case "$fixture" in
  long-stream-no-newline | long-stream-markdown-completion | long-stream-production-completion)
    wait_for_fixture_completion=1
    ;;
esac

environment_json="$(
  printf '{"SOMA_DEVICE_PERFORMANCE_MODE":"%s","SOMA_DEVICE_PERFORMANCE_ROUNDS":"%s","SOMA_DEVICE_PERFORMANCE_DELAY_SECONDS":"%s","SOMA_DEVICE_PERFORMANCE_WAIT_FOR_FIXTURE_COMPLETION":"%s","SOMA_UI_PERFORMANCE_FIXTURE":"%s","SOMA_UI_PERFORMANCE_FAST_STREAM":"%s"}' \
    "$mode" \
    "$rounds" \
    "$post_fixture_delay_seconds" \
    "$wait_for_fixture_completion" \
    "$fixture" \
    "$fast_stream"
)"

timestamp="$(date +%Y%m%d-%H%M%S)"
run_dir="$output_root/run-$timestamp-$$"
mkdir -p "$run_dir"

echo "Using installed Soma $installed_version ($installed_build), Release; no build or install will run."
echo "Launching the isolated in-memory performance fixture on $xctrace_device_id."
xcrun devicectl device process launch \
  --device "$canonical_device_id" \
  --terminate-existing \
  --environment-variables "$environment_json" \
  top.hedon.soma >/dev/null

# CoreDevice publishes a new process before Instruments can necessarily attach. Require two
# consecutive observations of the same exact PID before starting the formal trace.
app_pid=""
previous_pid=""
for _ in 1 2 3 4 5 6 7 8; do
  candidate_pid="$(
    xcrun devicectl device info processes --device "$canonical_device_id" 2>/dev/null |
      awk '/\/Soma\.app\/Soma([[:space:]]|$)/ && !found { print $1; found = 1 }'
  )"
  if [[ -n "$candidate_pid" && "$candidate_pid" == "$previous_pid" ]]; then
    app_pid="$candidate_pid"
    break
  fi
  previous_pid="$candidate_pid"
  sleep 1
done
if [[ -z "$app_pid" ]]; then
  echo "Soma did not reach a stable running PID after the fixture launch." >&2
  exit 1
fi

formal_passed=0
formal_evidence_dir=""
for attempt in 1 2; do
  attempt_dir="$run_dir/record-attempt-$attempt"
  echo "Formal recording attempt $attempt/2 for Soma PID $app_pid ($duration)."
  if SOMA_PROFILE_DEVICE="$xctrace_device_id" \
    SOMA_PROFILE_ATTACH="$app_pid" \
    SOMA_PROFILE_DURATION="$duration" \
    SOMA_PROFILE_RUNS=1 \
    SOMA_PROFILE_TEMPLATES="$profile_templates" \
    SOMA_PROFILE_INTERACTION="$mode" \
    SOMA_PROFILE_INTERACTION_ROUNDS="$rounds" \
    SOMA_PROFILE_START_TIMEOUT_SECONDS="$start_timeout_seconds" \
    SOMA_PROFILE_TIMEOUT_SECONDS="$total_timeout_seconds" \
    SOMA_PROFILE_OUTPUT_DIR="$attempt_dir" \
    "$root_dir/scripts/profile-device-performance.sh"; then
    formal_passed=1
    formal_evidence_dir="$attempt_dir"
    break
  fi

  attempt_status="$(awk -F '\t' 'NR == 2 { print $8 }' "$attempt_dir/manifest.tsv" 2>/dev/null || true)"
  if ((attempt == 2)) ||
    [[ "$attempt_status" != "record_failed" && "$attempt_status" != "start_timed_out" ]]; then
    echo "Formal recording failed with non-retryable status '$attempt_status'. Evidence: $attempt_dir" >&2
    exit 1
  fi

  current_pid="$(
    xcrun devicectl device info processes --device "$canonical_device_id" 2>/dev/null |
      awk '/\/Soma\.app\/Soma([[:space:]]|$)/ && !found { print $1; found = 1 }'
  )"
  if [[ "$current_pid" != "$app_pid" ]]; then
    echo "Soma exited or changed PID before the retry." >&2
    exit 1
  fi

  echo "Formal attach did not start; resetting the stale Xcode Instruments helper for one bounded retry."
  if ! reset_instruments_helper; then
    echo "The Instruments helper did not restore this iPhone within five seconds." >&2
    exit 1
  fi
done
if ((formal_passed == 0)); then
  echo "xctrace could not start a formal trace after two bounded attempts. Evidence: $run_dir" >&2
  exit 1
fi

echo "Reusable physical-device profile passed without rebuilding: $formal_evidence_dir"
