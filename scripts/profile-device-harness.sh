#!/usr/bin/env bash

set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
device_id="${SOMA_PROFILE_DEVICE:-${SOMA_DEVICE_ID:-}}"
mode="${SOMA_PROFILE_INTERACTION:-tabs}"
rounds="${SOMA_PROFILE_INTERACTION_ROUNDS:-30}"
duration="${SOMA_PROFILE_DURATION:-75s}"
output_dir="${SOMA_PROFILE_OUTPUT_DIR:-$root_dir/build/performance/device-harness-$mode}"
fixture="${SOMA_UI_PERFORMANCE_FIXTURE:-long-stream}"

if [[ -z "$device_id" ]]; then
  echo "SOMA_PROFILE_DEVICE is required." >&2
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

environment_json="$(
  printf '{"SOMA_DEVICE_PERFORMANCE_MODE":"%s","SOMA_DEVICE_PERFORMANCE_ROUNDS":"%s","SOMA_DEVICE_PERFORMANCE_DELAY_SECONDS":"8","SOMA_UI_PERFORMANCE_FIXTURE":"%s"}' \
    "$mode" "$rounds" "$fixture"
)"

xcrun devicectl device process launch \
  --device "$device_id" \
  --terminate-existing \
  --environment-variables "$environment_json" \
  top.hedon.soma >/dev/null

# CoreDevice 的进程列表更新会比 launch 返回稍晚；等待 App 真正可枚举后再让
# xctrace 按名称附着，避免把这一瞬间的竞态误报为 App 退出。
app_pid=""
for _ in 1 2 3 4 5; do
  app_pid="$(
    xcrun devicectl device info processes --device "$device_id" 2>/dev/null |
      awk '/\/Soma\.app\/Soma([[:space:]]|$)/ { print $1; exit }'
  )"
  if [[ -n "$app_pid" ]]; then
    break
  fi
  sleep 1
done
if [[ -z "$app_pid" ]]; then
  echo "Soma did not remain running after the harness launch." >&2
  exit 1
fi

SOMA_PROFILE_DEVICE="$device_id" \
SOMA_PROFILE_ATTACH="$app_pid" \
SOMA_PROFILE_DURATION="$duration" \
SOMA_PROFILE_INTERACTION="$mode" \
SOMA_PROFILE_INTERACTION_ROUNDS="$rounds" \
SOMA_PROFILE_OUTPUT_DIR="$output_dir" \
  "$root_dir/scripts/profile-device-performance.sh"
