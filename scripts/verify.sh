#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h}"
"$project_root/scripts/build_app.sh"
"$project_root/.build-quotabar/release/QuotaBarChecks"
"$project_root/dist/QuotaBar.app/Contents/MacOS/QuotaBar" --verify-store
git -C "$project_root" diff --check
if [[ "${1:-}" == "--live" ]]; then
  "$project_root/.build-quotabar/release/QuotaBarChecks" --live-codex --live-claude
fi
