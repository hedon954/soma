#!/usr/bin/env bash

set -euo pipefail

profile_device="${SOMA_PROFILE_DEVICE:-}"
profile_duration="${SOMA_PROFILE_DURATION:-30s}"
profile_templates="${SOMA_PROFILE_TEMPLATES:-${SOMA_PROFILE_TEMPLATE:-Time Profiler}}"
profile_process="${SOMA_PROFILE_PROCESS:-Soma}"
profile_attach="${SOMA_PROFILE_ATTACH:-$profile_process}"
profile_runs="${SOMA_PROFILE_RUNS:-1}"
profile_pause_seconds="${SOMA_PROFILE_PAUSE_SECONDS:-2}"
profile_interaction="${SOMA_PROFILE_INTERACTION:-manual}"
profile_interaction_rounds="${SOMA_PROFILE_INTERACTION_ROUNDS:-1}"
profile_timeout_seconds="${SOMA_PROFILE_TIMEOUT_SECONDS:-300}"
profile_start_timeout_seconds="${SOMA_PROFILE_START_TIMEOUT_SECONDS:-20}"
profile_subsystem="${SOMA_PROFILE_SUBSYSTEM:-top.hedon.soma}"
profile_tab_p95_budget_ms="${SOMA_PROFILE_TAB_P95_BUDGET_MS:-100}"
profile_session_p95_budget_ms="${SOMA_PROFILE_SESSION_P95_BUDGET_MS:-200}"
profile_ready_notification="${SOMA_PROFILE_READY_NOTIFICATION:-}"

if [[ -z "${profile_device}" ]]; then
  echo "Set SOMA_PROFILE_DEVICE to the physical iPhone UDID shown by 'xcrun xctrace list devices'." >&2
  exit 1
fi

if ! device_lock_state="$(
  xcrun devicectl device info lockState --device "${profile_device}" 2>/dev/null
)"; then
  echo "Unable to read the physical device lock state." >&2
  exit 1
fi
if printf '%s\n' "${device_lock_state}" | grep -q 'passcodeRequired: true'; then
  echo "Unlock the physical iPhone before recording a performance trace." >&2
  exit 1
fi

if [[ ! "${profile_runs}" =~ ^[1-9][0-9]*$ ]] || ((profile_runs > 100)); then
  echo "SOMA_PROFILE_RUNS must be an integer from 1 through 100." >&2
  exit 1
fi

if [[ ! "${profile_pause_seconds}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "SOMA_PROFILE_PAUSE_SECONDS must be a non-negative number." >&2
  exit 1
fi

if [[ ! "${profile_interaction}" =~ ^[a-z0-9_-]+$ ]]; then
  echo "SOMA_PROFILE_INTERACTION must contain only lowercase letters, numbers, underscores or hyphens." >&2
  exit 1
fi

if [[ ! "${profile_interaction_rounds}" =~ ^[1-9][0-9]*$ ]] || ((profile_interaction_rounds > 100)); then
  echo "SOMA_PROFILE_INTERACTION_ROUNDS must be an integer from 1 through 100." >&2
  exit 1
fi

if [[ ! "${profile_timeout_seconds}" =~ ^[1-9][0-9]*$ ]] || ((profile_timeout_seconds > 3600)); then
  echo "SOMA_PROFILE_TIMEOUT_SECONDS must be an integer from 1 through 3600." >&2
  exit 1
fi
if [[ ! "${profile_start_timeout_seconds}" =~ ^[1-9][0-9]*$ ]] ||
  ((profile_start_timeout_seconds > 120)); then
  echo "SOMA_PROFILE_START_TIMEOUT_SECONDS must be an integer from 1 through 120." >&2
  exit 1
fi

if [[ ! "${profile_tab_p95_budget_ms}" =~ ^[0-9]+([.][0-9]+)?$ ]] ||
  [[ "${profile_tab_p95_budget_ms}" == "0" ]]; then
  echo "SOMA_PROFILE_TAB_P95_BUDGET_MS must be a positive number." >&2
  exit 1
fi
if [[ ! "${profile_session_p95_budget_ms}" =~ ^[0-9]+([.][0-9]+)?$ ]] ||
  [[ "${profile_session_p95_budget_ms}" == "0" ]]; then
  echo "SOMA_PROFILE_SESSION_P95_BUDGET_MS must be a positive number." >&2
  exit 1
fi

timestamp="$(date +%Y%m%d-%H%M%S)"
output_dir="${SOMA_PROFILE_OUTPUT_DIR:-build/performance/device-${timestamp}-$$}"
manifest_path="${output_dir}/manifest.tsv"
mkdir -p "${output_dir}"

printf 'run\ttemplate\tduration\tinteraction\tinteraction_rounds\tstarted_at\tfinished_at\tstatus\ttrace\ttoc\tsummary\n' >"${manifest_path}"

IFS=',' read -r -a templates <<<"${profile_templates}"
if ((${#templates[@]} == 0)); then
  echo "SOMA_PROFILE_TEMPLATES did not contain a template." >&2
  exit 1
fi

echo "Recording ${profile_runs} independent trace(s) for each template from '${profile_process}' on ${profile_device}."
echo "Each trace expects ${profile_interaction_rounds} '${profile_interaction}' interaction round(s)."
echo "Keep the phone unlocked and open '${profile_process}'; profile_runs is not the interaction sample count."

active_record_pid=""

stop_active_record() {
  if [[ -z "${active_record_pid}" ]] || ! kill -0 "${active_record_pid}" 2>/dev/null; then
    active_record_pid=""
    return
  fi

  kill -TERM "${active_record_pid}" 2>/dev/null || true
  for _ in 1 2 3 4 5; do
    kill -0 "${active_record_pid}" 2>/dev/null || break
    sleep 1
  done
  if kill -0 "${active_record_pid}" 2>/dev/null; then
    kill -KILL "${active_record_pid}" 2>/dev/null || true
  fi
  wait "${active_record_pid}" 2>/dev/null || true
  active_record_pid=""
}

trap 'stop_active_record' EXIT
trap 'stop_active_record; exit 130' INT
trap 'stop_active_record; exit 143' TERM

record_trace() {
  local profile_template="$1"
  local output_path="$2"
  local deadline start_deadline state record_log ready_posted record_started

  record_log="${output_path}.record.log"
  : >"${record_log}"
  xcrun xctrace record \
    --template "${profile_template}" \
    --device "${profile_device}" \
    --attach "${profile_attach}" \
    --time-limit "${profile_duration}" \
    --output "${output_path}" \
    --no-prompt > >(tee "${record_log}") 2>&1 &
  active_record_pid=$!
  deadline=$((SECONDS + profile_timeout_seconds))
  start_deadline=$((SECONDS + profile_start_timeout_seconds))
  ready_posted=0
  record_started=0

  while kill -0 "${active_record_pid}" 2>/dev/null; do
    if ((record_started == 0)) && grep -q "Ctrl-C to stop the recording" "${record_log}"; then
      record_started=1
      if [[ -n "${profile_ready_notification}" ]]; then
        xcrun devicectl device notification post \
          --device "${profile_device}" \
          --name "${profile_ready_notification}" \
          --quiet
        ready_posted=1
        echo "Posted profiler-ready notification: ${profile_ready_notification}"
      fi
    fi
    state="$(ps -p "${active_record_pid}" -o stat= 2>/dev/null | tr -d '[:space:]')"
    [[ -z "${state}" || "${state}" == Z* ]] && break
    if ((record_started == 0 && SECONDS >= start_deadline)); then
      echo "xctrace did not start within ${profile_start_timeout_seconds}s; terminating before the long recording window." >&2
      stop_active_record
      return 125
    fi
    if ((SECONDS >= deadline)); then
      echo "xctrace exceeded ${profile_timeout_seconds}s; terminating incomplete recording." >&2
      stop_active_record
      return 124
    fi
    sleep 1
  done

  set +e
  wait "${active_record_pid}"
  local record_status=$?
  set -e
  active_record_pid=""
  if ((record_status != 0 && record_started == 1)); then
    return 126
  fi
  if [[ -n "${profile_ready_notification}" ]] && ((ready_posted == 0)); then
    echo "Trace ended before the profiler-ready notification could be posted." >&2
    return 1
  fi
  return "${record_status}"
}

for raw_template in "${templates[@]}"; do
  profile_template="${raw_template#"${raw_template%%[![:space:]]*}"}"
  profile_template="${profile_template%"${profile_template##*[![:space:]]}"}"
  if [[ -z "${profile_template}" ]]; then
    echo "SOMA_PROFILE_TEMPLATES contains an empty template name." >&2
    exit 1
  fi

  template_slug="$(printf '%s' "${profile_template}" | tr '[:upper:] ' '[:lower:]-' | tr -cd '[:alnum:]_-')"

  for ((run = 1; run <= profile_runs; run += 1)); do
    printf -v run_number '%02d' "${run}"
    output_path="${output_dir}/${template_slug}-run-${run_number}.trace"
    toc_path="${output_dir}/${template_slug}-run-${run_number}-toc.xml"
    summary_path=""

    if ((run > 1)) && [[ "${profile_pause_seconds}" != "0" ]]; then
      sleep "${profile_pause_seconds}"
    fi

    started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "[${profile_template} ${run}/${profile_runs}] Recording ${profile_duration} to ${output_path}"

    record_status=0
    record_trace "${profile_template}" "${output_path}" || record_status=$?
    if ((record_status == 0)); then
      status="passed"
    elif ((record_status == 124)); then
      status="timed_out"
    elif ((record_status == 125)); then
      status="start_timed_out"
    elif ((record_status == 126)); then
      status="record_failed_after_start"
    else
      status="record_failed"
    fi

    if [[ "${status}" == "passed" ]]; then
      if ! xcrun xctrace export \
        --input "${output_path}" \
        --toc \
        --output "${toc_path}" >/dev/null 2>&1 ||
        ! grep -q '<run number=' "${toc_path}" ||
        ! grep -q '<data>' "${toc_path}"; then
        status="invalid_trace"
      fi
    fi

    if [[ "${status}" == "passed" &&
      "${profile_interaction}" == "tabs" &&
      "${profile_template}" == "Time Profiler" ]]; then
      signposts_path="${output_dir}/${template_slug}-run-${run_number}-os-signpost.xml"
      summary_path="${output_dir}/${template_slug}-run-${run_number}-tabs.json"
      minimum_samples=$((profile_interaction_rounds * 4))
      if ! xcrun xctrace export \
        --input "${output_path}" \
        --xpath '/trace-toc/run[@number="1"]/data/table[@schema="os-signpost"]' \
        --output "${signposts_path}" >/dev/null 2>&1; then
        status="signpost_export_failed"
      elif ! ruby "$(dirname "$0")/analyze-tab-signposts.rb" \
        --process "${profile_process}" \
        --subsystem "${profile_subsystem}" \
        --minimum-samples "${minimum_samples}" \
        --minimum-per-target "${profile_interaction_rounds}" \
        --exact-samples "${minimum_samples}" \
        --exact-per-target "${profile_interaction_rounds}" \
        --maximum-p95-ms "${profile_tab_p95_budget_ms}" \
        --output "${summary_path}" \
        "${signposts_path}"; then
        status="analysis_failed"
      fi
    fi

    if [[ "${status}" == "passed" &&
      "${profile_interaction}" == "sessions" &&
      "${profile_template}" == "Time Profiler" ]]; then
      signposts_path="${output_dir}/${template_slug}-run-${run_number}-os-signpost.xml"
      summary_path="${output_dir}/${template_slug}-run-${run_number}-sessions.json"
      expected_samples=$((profile_interaction_rounds * 2))
      if ! xcrun xctrace export \
        --input "${output_path}" \
        --xpath '/trace-toc/run[@number="1"]/data/table[@schema="os-signpost"]' \
        --output "${signposts_path}" >/dev/null 2>&1; then
        status="signpost_export_failed"
      elif ! ruby "$(dirname "$0")/analyze-session-signposts.rb" \
        --process "${profile_process}" \
        --subsystem "${profile_subsystem}" \
        --expected-samples "${expected_samples}" \
        --maximum-p95-ms "${profile_session_p95_budget_ms}" \
        --output "${summary_path}" \
        "${signposts_path}"; then
        status="analysis_failed"
      fi
    fi

    finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "${run}" \
      "${profile_template}" \
      "${profile_duration}" \
      "${profile_interaction}" \
      "${profile_interaction_rounds}" \
      "${started_at}" \
      "${finished_at}" \
      "${status}" \
      "${output_path}" \
      "${toc_path}" \
      "${summary_path}" >>"${manifest_path}"

    if [[ "${status}" != "passed" ]]; then
      echo "Trace recording or analysis failed with status '${status}'. Partial evidence is listed in ${manifest_path}." >&2
      exit 1
    fi
  done
done

echo "Saved performance manifest: ${manifest_path}"
