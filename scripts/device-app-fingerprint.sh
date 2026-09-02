#!/usr/bin/env bash

set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
configuration="${SOMA_DEVICE_CONFIGURATION:-Release}"

if [[ ! "$configuration" =~ ^(Debug|Release)$ ]]; then
  echo "SOMA_DEVICE_CONFIGURATION must be Debug or Release." >&2
  exit 2
fi

cd "$root_dir"

# 只纳入会改变 App/Widget 二进制的输入。测试、文档和 profiling 脚本变化不会
# 让已经安装的 Release 失效；产品源码、资源、依赖或工程配置变化则一定失效。
source_paths="$(
  {
    printf '%s\n' project.yml
    [[ ! -f Package.resolved ]] || printf '%s\n' Package.resolved
    # Use the deterministic Git tracked/untracked contract. This includes new product
    # files while excluding ignored machine-local inputs such as feedback credentials.
    git ls-files --cached --others --exclude-standard -- Soma SomaWidget |
      while IFS= read -r path; do
        # A valid dirty worktree can contain tracked deletions. Those paths are
        # still reported by `git ls-files --cached`, but they were not inputs to
        # the just-built app and must not be handed to shasum.
        [[ ! -f "$path" ]] || printf '%s\n' "$path"
      done
  } | LC_ALL=C sort -u
)"
{
  printf 'schema=soma-device-app-fingerprint-v2\n'
  printf 'configuration=%s\n' "$configuration"
  xcodebuild -version
  # One shasum process keeps this preflight fast. Repository source paths may contain
  # spaces, so pass the sorted manifest to xargs as NUL-delimited arguments.
  printf '%s\n' "$source_paths" | tr '\n' '\0' | xargs -0 shasum -a 256
} | shasum -a 256 | awk '{ print $1 }'
