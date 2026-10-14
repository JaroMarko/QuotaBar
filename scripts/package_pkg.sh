#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
output_dir="${1:-$project_root/dist}"
pkg_path="$output_dir/QuotaBar-1.0.0-arm64.pkg"
stage_dir="/private/tmp/quotabar-package-stage"

"$project_root/scripts/build_app.sh"
mkdir -p "$output_dir"
/bin/rm -rf /private/tmp/quotabar-package-stage
mkdir -p "$stage_dir"
ditto --norsrc --noextattr "$project_root/dist/QuotaBar.app" "$stage_dir/QuotaBar.app"
xattr -cr "$stage_dir/QuotaBar.app"

pkgbuild \
  --component "$stage_dir/QuotaBar.app" \
  --install-location /Applications \
  --identifier com.jaroslavmarko.planmeter.pkg \
  --version 1.0.0 \
  "$pkg_path"

pkgutil --payload-files "$pkg_path" >/dev/null
/bin/rm -rf /private/tmp/quotabar-package-stage
echo "$pkg_path"
