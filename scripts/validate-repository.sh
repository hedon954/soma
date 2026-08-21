#!/usr/bin/env bash

set -euo pipefail
shopt -s nullglob

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

fail() {
  echo "Repository validation failed: $*" >&2
  exit 1
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
  docs/prd/004-soma-current-product.md
  docs/prd/010-exercise-library-plans-guided-training.md
  docs/prd/011-durable-agent-jobs-remote-continuity.md
  docs/adr/README.md
  docs/bugs/README.md
  docs/changelog/README.md
  docs/engineering/training-domain-model.md
  docs/engineering/agent-job-protocol.md
  docs/engineering/implementation-sequence.md
  docs/research/README.md
  Soma/Resources/Info.plist
  Soma/Soma.entitlements
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

grep -q "PRODUCT_BUNDLE_IDENTIFIER: top.hedon.soma" project.yml ||
  fail "project.yml must define the Soma bundle identifier"
grep -q "exactVersion:" project.yml ||
  fail "Swift package versions must be pinned"

grep -q 'NWEndpoint.Host("smtp.qq.com")' \
  Soma/Services/FeedbackSMTPTransport.swift ||
  fail "personal-only feedback must use the fixed QQ SMTP endpoint"
grep -q 'static let recipient = "hedonwang@gmail.com"' \
  Soma/Services/FeedbackSubmission.swift ||
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
grep -q 'onChunk: @MainActor' Soma/Services/AgentStreamDeadline.swift ||
  fail "BUG 0024: streaming chunk handling must stay isolated to the main actor"
grep -q 'skipMovieOutputGeometry = state == .startingRecording' \
  Soma/Services/WorkoutCameraService.swift ||
  fail "BUG 0025: capture geometry must skip movie output while starting or recording"
grep -q 'guard !skipMovieOutputGeometry, !resources.movieOutput.isRecording else' \
  Soma/Services/WorkoutCameraService.swift ||
  fail "BUG 0025: capture geometry must not rewrite movie output while recording"
grep -q 'waitUntilPreviewHostSettled' \
  Soma/Services/GuidedWorkoutCoordinator.swift ||
  fail "BUG 0026: beginCurrentSet must wait for the set preview host before recording"
grep -q 'shouldRebuildCaptureConnections' \
  Soma/Services/WorkoutCameraService.swift ||
  fail "BUG 0026: live recording must not rebuild capture connections on preview host handoff"
grep -q 'hasLivePreview' \
  Soma/Views/GuidedWorkoutInteractionState.swift ||
  fail "BUG 0026: live preview host handoff must not rebuild capture connections"
grep -q 'prepare-reused-running-session' \
  Soma/Services/WorkoutCameraService.swift ||
  fail "BUG 0026: startRecording must reuse a running capture session instead of reconfiguring"
grep -q 'shouldIgnoreTransientPreviewInterruption' \
  Soma/Views/GuidedWorkoutInteractionState.swift ||
  fail "BUG 0026: previewing session-interruption must not stop an owned capture session"

for privacy_key in \
  NSCameraUsageDescription \
  NSMicrophoneUsageDescription \
  NSPhotoLibraryUsageDescription \
  NSSpeechRecognitionUsageDescription \
  NSHealthShareUsageDescription; do
  grep -q "<key>$privacy_key</key>" Soma/Resources/Info.plist ||
    fail "Info.plist is missing $privacy_key"
done

grep -q "<key>com.apple.developer.healthkit</key>" Soma/Soma.entitlements ||
  fail "HealthKit entitlement is missing"

plutil -lint Soma/Resources/Info.plist Soma/Soma.entitlements ExportOptions.plist >/dev/null
./scripts/check-markdown-links.rb
./scripts/check-document-lifecycle-links.rb
./scripts/check-secrets.sh
ruby ./scripts/check-agent-tool-registry.rb
ruby ./scripts/check-agent-model-input-parity.rb
ruby ./scripts/check-database-schema-doc.rb

echo "Repository contract passed."
