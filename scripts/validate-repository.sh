#!/usr/bin/env bash

set -euo pipefail
shopt -s nullglob

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

fail() {
  echo "Repository validation failed: $*" >&2
  exit 1
}

service_file() {
  local name="$1"
  local matches=()
  while IFS= read -r line; do
    matches+=("$line")
  done < <(find Soma/Services -name "$name" -print)
  if [[ "${#matches[@]}" -ne 1 ]]; then
    fail "expected exactly one Soma/Services/**/${name}, found ${#matches[@]}"
  fi
  printf '%s' "${matches[0]}"
}

assert_link() {
  local path="$1"
  local expected="$2"

  [[ -L "$path" ]] || fail "$path must be a symbolic link"
  [[ "$(readlink "$path")" == "$expected" ]] ||
    fail "$path must point to $expected"
}

required_files=(
  CLAUDE.md
  README.md
  CHANGELOG.md
  CONTRIBUTING.md
  SECURITY.md
  project.yml
  docs/acceptance.md
  docs/prd/README.md
  docs/prd/000-origin-through-0.0.11.md
  docs/archive/0.0.13/prd/044-behavior-preserving-modernization.md
  docs/archive/0.0.14/prd/045-performance-reliability-and-bounded-data-access.md
  docs/archive/0.0.15/prd/046-coach-records-and-goal-directed-progress.md
  docs/archive/0.0.16/prd/047-root-aware-tab-reselection.md
  docs/archive/0.0.17/prd/048-reviewable-record-derivation-and-user-controlled-interruption.md
  docs/archive/0.0.18/prd/049-foreground-responsiveness-and-readable-monthly-progress.md
  docs/archive/0.0.18/prd/050-lightweight-progress-disclosure-and-coach-controls.md
  docs/archive/0.0.19/prd/051-self-healing-tool-arguments-and-wide-progress-disclosure.md
  docs/archive/0.0.19/prd/052-coach-training-and-lifecycle-reliability.md
  docs/archive/0.0.19/prd/053-adaptive-energy-estimation-and-progress.md
  docs/archive/0.0.19/prd/054-progress-history-and-periods.md
  docs/archive/0.0.22/prd/056-video-speech-and-share-readability.md
  docs/archive/0.0.22/prd/057-coach-focus-progress-rings-and-library-clarity.md
  docs/archive/0.0.22/prd/058-feedback-duration-and-editable-calories.md
  docs/adr/0000-origin-through-0.0.11.md
  docs/archive/0.0.13/adr/0099-behavior-preserving-modernization-and-three-version-docs.md
  docs/archive/0.0.14/adr/0100-bounded-snapshots-continuous-stream-rendering-and-query-first-data-access.md
  docs/archive/0.0.15/adr/0101-record-truth-and-agent-profile-context.md
  docs/archive/0.0.15/adr/0102-source-workout-plan-execution-materialization.md
  docs/archive/0.0.15/adr/0103-goal-directed-progress-energy-and-hypertrophy.md
  docs/archive/0.0.15/adr/0104-independent-react-timeouts-by-media.md
  docs/archive/0.0.16/adr/0105-root-aware-tab-reselection.md
  docs/archive/0.0.17/adr/0106-reviewable-derived-records-and-manual-interruption.md
  docs/archive/0.0.18/adr/0107-foreground-recovery-and-progress-evidence-projection.md
  docs/archive/0.0.18/adr/0108-contextual-progress-disclosure-and-reviewable-meal-order.md
  docs/archive/0.0.19/adr/0109-schema-guided-tool-argument-recovery.md
  docs/archive/0.0.19/adr/0110-workout-tool-and-calorie-evidence.md
  docs/archive/0.0.19/adr/0111-agent-response-identity-and-manual-recovery.md
  docs/archive/0.0.19/adr/0112-coach-scroll-and-session-behavior.md
  docs/archive/0.0.19/adr/0113-capture-and-foreground-lifecycle.md
  docs/archive/0.0.19/adr/0114-progress-periods-and-adaptive-energy.md
  docs/archive/0.0.19/adr/0115-energy-default-reference-and-compact-details.md
  docs/archive/0.0.19/adr/0116-progress-period-specific-focus.md
  docs/archive/0.0.22/adr/0119-full-video-and-append-only-dictation.md
  docs/archive/0.0.22/adr/0120-focused-shortcut-prompt.md
  docs/archive/0.0.22/adr/0121-live-dictation-preview.md
  docs/archive/0.0.22/adr/0122-nutrition-rings-and-period-deficit.md
  docs/archive/0.0.22/adr/0123-exercise-movement-kinds.md
  docs/archive/0.0.22/adr/0124-smtp-feedback-failure-taxonomy.md
  docs/archive/0.0.22/adr/0125-eager-loaded-coach-messages.md
  docs/archive/0.0.23/prd/059-coach-ids-progress-and-required-zeros.md
  docs/archive/0.0.23/prd/060-remove-healthkit-until-redesign.md
  docs/archive/0.0.23/prd/061-daily-energy-net-training.md
  docs/archive/0.0.23/prd/062-workout-share-fill-or-grow.md
  docs/archive/0.0.23/prd/063-video-compatibility-and-actionable-errors.md
  docs/archive/0.0.23/prd/064-progress-total-energy-deficit.md
  docs/archive/0.0.23/adr/0126-workout-share-pro-max-canvas.md
  docs/archive/0.0.23/adr/0127-agent-workout-weight-and-rest-zero.md
  docs/archive/0.0.23/adr/0128-remove-healthkit-until-redesign.md
  docs/archive/0.0.23/adr/0129-daily-energy-net-training-increment.md
  docs/archive/0.0.23/adr/0130-workout-share-fill-or-grow.md
  docs/archive/0.0.23/adr/0131-explicit-video-rejection-frame-fallback.md
  docs/archive/0.0.23/adr/0132-actionable-error-presentation.md
  docs/archive/0.0.23/adr/0133-paired-day-total-energy-deficit.md
  docs/archive/0.0.23/README.md
  docs/archive/README.md
  docs/archive/0.0.10/README.md
  docs/archive/0.0.11/README.md
  docs/archive/0.0.12/README.md
  docs/archive/0.0.13/README.md
  docs/archive/0.0.14/README.md
  docs/archive/0.0.15/README.md
  docs/archive/0.0.16/README.md
  docs/archive/0.0.17/README.md
  docs/archive/0.0.18/README.md
  docs/archive/0.0.19/README.md
  docs/archive/0.0.22/README.md
  docs/adr/README.md
  docs/bugs/README.md
  docs/changelog/README.md
  docs/engineering/training-domain-model.md
  docs/engineering/agent-job-protocol.md
  docs/engineering/implementation-sequence.md
  docs/research/README.md
  Soma/Resources/Info.plist
)

for required_file in "${required_files[@]}"; do
  [[ -f "$required_file" ]] || fail "$required_file is missing"
done

assert_link AGENTS.md CLAUDE.md
assert_link .cursor/skills ../.claude/skills
assert_link .codex/skills ../.claude/skills

adr_files=(docs/adr/[0-9][0-9][0-9][0-9]-*.md)
[[ ${#adr_files[@]} -gt 0 ]] || fail "no ADR files found"
for adr in "${adr_files[@]}"; do
  for heading in 背景 决策 结果; do
    grep -q "^## $heading$" "$adr" ||
      fail "$adr is missing the '$heading' section"
  done
done

bug_files=(docs/bugs/[0-9][0-9][0-9][0-9]-*.md)
[[ ${#bug_files[@]} -gt 0 ]] || fail "no critical bug records found"
for bug in "${bug_files[@]}"; do
  for heading in 症状 根因 修复 回归门禁; do
    grep -q "^## $heading$" "$bug" ||
      fail "$bug is missing the '$heading' section"
  done
done

skill_files=(.claude/skills/*/SKILL.md)
[[ ${#skill_files[@]} -gt 0 ]] || fail "no project skills found"
for skill in "${skill_files[@]}"; do
  grep -q "^name:" "$skill" || fail "$skill is missing a name"
  grep -q "^description:" "$skill" || fail "$skill is missing a description"
done

if git ls-files | grep -qE '(^|/)[^/]+\.xcodeproj/'; then
  fail "generated Xcode projects must not be tracked"
fi

if grep -R -n \
  --exclude=validate-repository.sh \
  "FormCoach" Soma SomaTests project.yml scripts README.md >/dev/null 2>&1; then
  fail "current product files still contain the retired FormCoach name"
fi

if grep -R -n \
  --include='*.swift' \
  '\.buttonStyle(\.borderedProminent)' \
  Soma >/dev/null 2>&1; then
  fail "raw borderedProminent buttons can lose foreground contrast; use an App filled button style"
fi

grep -q "PRODUCT_BUNDLE_IDENTIFIER: top.hedon.soma" project.yml ||
  fail "project.yml must define the Soma bundle identifier"
grep -q "exactVersion:" project.yml ||
  fail "Swift package versions must be pinned"

grep -q 'NWEndpoint.Host("smtp.qq.com")' \
  "$(service_file FeedbackSMTPTransport.swift)" ||
  fail "personal-only feedback must use the fixed QQ SMTP endpoint"
grep -q 'static let recipient = "hedonwang@gmail.com"' \
  "$(service_file FeedbackSubmission.swift)" ||
  fail "personal-only feedback must keep the fixed Gmail recipient"
if grep -R -n \
  --exclude=validate-repository.sh \
  'SOMA_FEEDBACK_BASE_URL\|SOMAFeedbackBaseURL' \
  Soma project.yml scripts >/dev/null 2>&1; then
  fail "feedback must not expose or inject a service URL"
fi
if grep -nE 'Soma Server|hedonwang@gmail\.com|Base URL|SMTP|QQ 邮箱' \
  Soma/Views/FeedbackView.swift >/dev/null 2>&1; then
  fail "FeedbackView must not expose delivery implementation details"
fi
if grep -nE '随反馈附带的上下文|contextDisclosure' \
  Soma/Views/FeedbackView.swift >/dev/null 2>&1; then
  fail "per-reply feedback must not show the removed context disclosure"
fi
if grep -n '@Query.*AgentTrace' Soma/Views/CoachView.swift >/dev/null 2>&1; then
  fail "CoachView must not observe every AgentTrace just to present feedback"
fi
if grep -n 'AssistantFeedbackContextBuilder\.make' \
  Soma/Views/CoachView.swift >/dev/null 2>&1; then
  fail "feedback context must be deferred until submission, not built during sheet presentation"
fi
if grep -nE 'case assistantFeedback|sheet = \.assistantFeedback|func openFeedback' \
  Soma/Views/CoachView.swift >/dev/null 2>&1; then
  fail "BUG 0031: per-reply feedback presentation state must stay in its leaf button, not invalidate CoachView"
fi
grep -q 'struct AssistantFeedbackButton: View' \
  Soma/Views/AssistantFeedbackButton.swift ||
  fail "BUG 0031: per-reply feedback must use the leaf presentation component"
grep -q '@State private var isExpanded = false' \
  Soma/Views/AssistantFeedbackButton.swift ||
  fail "BUG 0031: inline feedback expansion state must be owned by the leaf button"
feedback_sheet_pattern=".sheet(isPresented: \$isPresented)"
if grep -nF "$feedback_sheet_pattern" \
  Soma/Views/AssistantFeedbackButton.swift >/dev/null 2>&1; then
  fail "BUG 0031: per-reply feedback must expand inline instead of presenting a sheet"
fi
if ! grep -q 'FeedbackView(' Soma/Views/AssistantFeedbackButton.swift ||
  ! grep -q 'isEmbedded: true' Soma/Views/AssistantFeedbackButton.swift; then
  fail "BUG 0031: per-reply feedback must reuse the inline embedded composer"
fi
if grep -n 'AssistantFeedbackContextBuilder\.make' \
  Soma/Views/AssistantFeedbackButton.swift >/dev/null 2>&1; then
  fail "BUG 0031: the leaf feedback button must never assemble submission context"
fi
grep -q '\.id(scrollTarget)' \
  Soma/Views/AssistantFeedbackButton.swift ||
  fail "BUG 0031: inline feedback must expose a message-scoped bottom scroll target"
grep -q 'onExpanded(scrollTarget)' \
  Soma/Views/AssistantFeedbackButton.swift ||
  fail "BUG 0031: expanding feedback must request scrolling only after the user taps"
grep -q 'proxy.scrollTo(target, anchor: \.bottom)' \
  Soma/Views/CoachConversationStarter.swift ||
  fail "BUG 0031: feedback expansion must scroll its editor bottom into view"
grep -q 'onSubmitted:' \
  Soma/Views/AssistantFeedbackButton.swift ||
  fail "BUG 0031: successful per-reply feedback must notify its leaf presentation owner"
grep -q 'isExpanded = false' \
  Soma/Views/AssistantFeedbackButton.swift ||
  fail "BUG 0031: successful per-reply feedback must collapse its inline editor"
if grep -nE 'enqueueSentinelReport|source: "sentinel"' \
  "$(service_file CrashDiagnosticsCoordinator.swift)" >/dev/null 2>&1; then
  fail "BUG 0032: sentinel state must never generate a crash report"
fi
grep -q 'evidenceSource: \.metricKit' \
  "$(service_file CrashDiagnosticsCoordinator.swift)" ||
  fail "BUG 0032: crash reports require MetricKit evidence"
if grep -nE 'verifiedPrefixes|supportsDirectVideo\([^)]*provider|supportsDirectVideo\([^)]*model' \
  "$(service_file AIProvider.swift)" >/dev/null 2>&1; then
  fail "BUG 0033: model/provider names must never determine multimodal capability"
fi
grep -q 'source.map { "来源：平台模型目录' "$(service_file AIProvider.swift)" ||
  fail "BUG 0033: model capability decisions must expose their source"
grep -q 'SOMA_PROVIDER_SUPPORTS_DIRECT_VIDEO' Server/src/main.ts ||
  fail "BUG 0033: remote direct-video capability must come from explicit deployment evidence"
if grep -n 'SOMA_PROVIDER_MODEL' Server/src/main.ts | grep -q 'directVideo'; then
  fail "BUG 0033: remote direct-video capability must not be inferred from the model name"
fi
if grep -n '\.prefix(3)' Soma/Views/InsightsView.swift >/dev/null 2>&1; then
  fail "recent activity must not be truncated to three rows"
fi
grep -q 'ForEach(records, id:' Soma/Views/ProgressHistoryRecordsView.swift ||
  fail "progress day view must expose every record through shared detail navigation"
grep -q 'yStart: .value("基线", 0)' Soma/Views/ProgressEnergyHistoryCard.swift ||
  fail "progress intake columns must originate at the zero baseline"
if rg -q 'DailyEnergyProjectionCalculator|activeKilocaloriesSoFar.*fraction' Soma; then
  fail "progress must not extrapolate today's partial activity by elapsed clock time"
fi
grep -q '^Soma/Resources/FeedbackCredentials\.plist$' .gitignore ||
  fail "the local mail credential resource must stay ignored"
grep -q 'online-check.sh' scripts/archive-testflight.sh ||
  fail "TestFlight archive must run the feedback online check"
grep -q 'make db-migrate-create name=<snake_case_name>' CLAUDE.md ||
  fail "AGENTS.md must require the PostgreSQL migration creation command"
grep -q 'make db-migrate-status' CLAUDE.md ||
  fail "AGENTS.md must require PostgreSQL migration status review"
grep -q 'make db-migrate' CLAUDE.md ||
  fail "AGENTS.md must require applying PostgreSQL migrations through the runner"

if grep -R -nE \
  '\.(configurationDisplayName|description)\(Text\(' \
  SomaWidget >/dev/null 2>&1; then
  fail "Widget configuration metadata must use static String or LocalizedStringKey values"
fi

grep -q 'MainActor.assertIsolated' Soma/Models/AgentJob.swift ||
  fail "BUG 0024: agent event projection must assert main actor isolation"
grep -q 'project: @escaping @MainActor' "$(service_file AgentStreamWorker.swift)" ||
  fail "BUG 0024: only the batched event projection must cross to the main actor"
grep -q 'skipMovieOutputGeometry = state == .startingRecording' \
  "$(service_file WorkoutCameraCaptureLifecycle.swift)" ||
  fail "BUG 0025: capture geometry must skip movie output while starting or recording"
grep -q 'guard !skipMovieOutputGeometry, !resources.movieOutput.isRecording else' \
  "$(service_file WorkoutCameraCaptureLifecycle.swift)" ||
  fail "BUG 0025: capture geometry must not rewrite movie output while recording"
grep -q 'startRecordingAfterPhaseTransition' \
  "$(service_file GuidedWorkoutCoordinator.swift)" ||
  fail "BUG 0026: beginCurrentSet must hand recording start to the phase transition coordinator"
grep -q 'waitUntilPreviewHostSettled' \
  "$(service_file GuidedWorkoutCoordinator+Recording.swift)" ||
  fail "BUG 0026: phase recording start must wait for the set preview host"
grep -q 'shouldRebuildCaptureConnections' \
  "$(service_file WorkoutCameraService.swift)" ||
  fail "BUG 0026: live recording must not rebuild capture connections on preview host handoff"
grep -q 'hasLivePreview' \
  Soma/Views/GuidedWorkoutInteractionState.swift ||
  fail "BUG 0026: live preview host handoff must not rebuild capture connections"
grep -q 'prepare-reused-running-session' \
  "$(service_file WorkoutCameraService.swift)" ||
  fail "BUG 0026: startRecording must reuse a running capture session instead of reconfiguring"
grep -q 'shouldIgnoreTransientPreviewInterruption' \
  Soma/Views/GuidedWorkoutInteractionState.swift ||
  fail "BUG 0026: previewing session-interruption must not stop an owned capture session"

share_aggregation_calls="$({
  grep -F -c 'return makeModel(workouts: workouts, scope: scope)' \
    Soma/Views/WorkoutSharePosterBuilder.swift || true
})"
[[ "$share_aggregation_calls" -eq 2 ]] ||
  fail "daily workout and plan execution sharing must use the same aggregation path"
grep -q 'WorkoutSharePosterBuilder.makeModel(' Soma/Views/HistoryViews.swift ||
  fail "workout history day sharing must use the shared workout poster aggregator"
grep -q 'forDay: day' Soma/Views/HistoryViews.swift ||
  fail "workout history day sharing must refetch the complete natural-day batch"

for privacy_key in \
  NSCameraUsageDescription \
  NSMicrophoneUsageDescription \
  NSPhotoLibraryUsageDescription \
  NSSpeechRecognitionUsageDescription; do
  grep -q "<key>$privacy_key</key>" Soma/Resources/Info.plist ||
    fail "Info.plist is missing $privacy_key"
done

plutil -lint Soma/Resources/Info.plist ExportOptions.plist >/dev/null
./scripts/check-markdown-links.rb
./scripts/check-document-lifecycle-links.rb
./scripts/check-secrets.sh
ruby ./scripts/check-agent-tool-registry.rb
ruby ./scripts/check-agent-model-input-parity.rb
ruby ./scripts/check-user-facing-errors.rb
ruby ./scripts/check-database-schema-doc.rb

echo "Repository contract passed."
