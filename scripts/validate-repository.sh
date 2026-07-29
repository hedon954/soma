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
  docs/adr/README.md
  docs/changelog/README.md
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
./scripts/check-secrets.sh

echo "Repository contract passed."
