#!/usr/bin/env bash

set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

smtp_file="$(find Soma/Services -name FeedbackSMTPTransport.swift -print)"
if [[ -z "$smtp_file" ]]; then
  echo "Online check failed: FeedbackSMTPTransport.swift is missing." >&2
  exit 1
fi

if grep -q 'NWEndpoint.Host("smtp.qq.com")' "$smtp_file"; then
  cat >&2 <<'MESSAGE'
Online check failed: feedback still sends directly from the iOS app with a bundled QQ Mail authorization code.

Before TestFlight, App Store, or any external distribution:
1. Move mail credentials to an authenticated server-side or serverless boundary.
2. Remove FeedbackCredentials.plist from the app bundle and rotate the embedded SMTP authorization code.
3. Keep the feedback UI free of service URLs and mail implementation details.
4. Re-run make online-check and the production feedback smoke test.
MESSAGE
  exit 1
fi

echo "Online feedback credential boundary passed."
