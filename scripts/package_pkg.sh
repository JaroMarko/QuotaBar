#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h}"
output_dir="${1:-$project_root/dist}"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_root/Resources/Info.plist")"
pkg_path="$output_dir/QuotaBar-$version-arm64.pkg"
"$project_root/scripts/build_app.sh"
mkdir -p "$output_dir"
stage_dir="$(mktemp -d /private/tmp/quotabar-package.XXXXXX)"
trap '/bin/rm -rf "$stage_dir"' EXIT
ditto --norsrc --noextattr "$project_root/dist/QuotaBar.app" "$stage_dir/QuotaBar.app"
# Remove only attributes that invalidate signatures; provenance is managed by macOS.
python3 - "$stage_dir/QuotaBar.app" <<'PYATTR'
import os,sys,subprocess
for base, dirs, files in os.walk(sys.argv[1]):
    for path in [base] + [os.path.join(base,f) for f in files]:
        for name in ('com.apple.FinderInfo','com.apple.ResourceFork'):
            names = subprocess.run(['/usr/bin/xattr',path],capture_output=True,text=True,check=True).stdout.splitlines()
            if name in names: subprocess.run(['/usr/bin/xattr','-d',name,path],check=True)
PYATTR
codesign --verify --deep --strict "$stage_dir/QuotaBar.app"
pkgbuild --root "$stage_dir" --install-location /Applications \
  --identifier com.jaroslavmarko.planmeter.pkg --version "$version" "$pkg_path"
pkgutil --payload-files "$pkg_path" >/dev/null
echo "$pkg_path"
