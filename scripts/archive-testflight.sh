#!/usr/bin/env bash

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
team_id="${DEVELOPMENT_TEAM:-}"
archive_path="${project_dir}/build/Soma.xcarchive"
export_path="${project_dir}/build/TestFlight"

if [[ -z "${team_id}" ]]; then
  echo "请先执行：DEVELOPMENT_TEAM=你的10位TeamID make archive" >&2
  exit 2
fi

"${project_dir}/scripts/online-check.sh"

if [[ -e "$archive_path" || -e "$export_path" ]]; then
  echo "归档输出已存在，请先移动它们或执行 make clean：" >&2
  echo "  $archive_path" >&2
  echo "  $export_path" >&2
  exit 1
fi

xcodegen generate --spec "${project_dir}/project.yml"
mkdir -p "${project_dir}/build"

xcodebuild archive \
  -project "${project_dir}/Soma.xcodeproj" \
  -scheme Soma \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "${archive_path}" \
  DEVELOPMENT_TEAM="${team_id}" \
  CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates

xcodebuild -exportArchive \
  -archivePath "${archive_path}" \
  -exportPath "${export_path}" \
  -exportOptionsPlist "${project_dir}/ExportOptions.plist" \
  -allowProvisioningUpdates

echo "TestFlight IPA 已导出到：${export_path}"
