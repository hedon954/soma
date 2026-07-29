#!/usr/bin/env bash

set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${1:-}"

if [[ -z "$version" ]]; then
  echo "Usage: $0 <MAJOR.MINOR.PATCH>" >&2
  exit 2
fi

awk -v version="$version" '
  $0 == "## [" version "]" || index($0, "## [" version "] - ") == 1 {
    found = 1
  }
  found && /^## \[/ && $0 != "## [" version "]" && index($0, "## [" version "] - ") != 1 {
    exit
  }
  found {
    print
  }
  END {
    if (!found) {
      exit 1
    }
  }
' "$root_dir/CHANGELOG.md"
