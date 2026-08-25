#!/usr/bin/env bash

set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "profile-device-tab-loop.sh no longer uses the unstable physical-device XCUITest Runner." >&2
echo "Forwarding to the canonical installed-Release harness." >&2
exec "$root_dir/scripts/profile-device-harness.sh"
