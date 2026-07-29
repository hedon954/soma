#!/usr/bin/env bash

set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

tag="${1:-}"
if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 vMAJOR.MINOR.PATCH" >&2
  exit 2
fi

version="${tag#v}"
marketing_version="$(
  awk '/MARKETING_VERSION:/ { print $2; exit }' project.yml
)"

if [[ "$version" != "$marketing_version" ]]; then
  echo "Tag $tag does not match MARKETING_VERSION $marketing_version." >&2
  exit 1
fi

if ! grep -qE "^## \\[$version\\]( - [0-9]{4}-[0-9]{2}-[0-9]{2})?$" CHANGELOG.md; then
  echo "CHANGELOG.md does not contain a release section for $version." >&2
  exit 1
fi

if git rev-parse "$tag" >/dev/null 2>&1; then
  if [[ "$(git cat-file -t "$tag")" != "tag" ]]; then
    echo "$tag must be an annotated tag." >&2
    exit 1
  fi
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "The worktree must be clean before release." >&2
  exit 1
fi

./scripts/release-notes.sh "$version" >/dev/null
echo "Release metadata for $tag passed."
