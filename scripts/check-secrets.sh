#!/usr/bin/env bash

set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

patterns=(
  'sk-[A-Za-z0-9_-]{20,}'
  'ghp_[A-Za-z0-9]{20,}'
  'github_pat_[A-Za-z0-9_]{20,}'
  'AKIA[A-Z0-9]{16}'
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'
)

failed=0
while IFS= read -r -d '' file_path; do
  [[ -f "$file_path" ]] || continue
  case "$file_path" in
    *.jpg | *.jpeg | *.png | *.gif | *.pdf | *.xcassets/*) continue ;;
  esac

  for pattern in "${patterns[@]}"; do
    if LC_ALL=C grep -I -nE -- "$pattern" "$file_path" >/dev/null; then
      echo "Potential secret in $file_path matching: $pattern" >&2
      failed=1
    fi
  done
done < <(git ls-files --cached --others --exclude-standard -z)

if [[ "$failed" -ne 0 ]]; then
  echo "Secret check failed. Remove the credential before committing." >&2
  exit 1
fi

echo "Secret patterns passed."
