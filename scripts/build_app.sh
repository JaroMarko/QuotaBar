#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
sdk_path="${QUOTABAR_SDK_PATH:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"
build_root="$project_root/.build-quotabar"
app_path="$project_root/dist/QuotaBar.app"

if [[ ! -d "$sdk_path" ]]; then
  sdk_path="$(xcrun --show-sdk-path)"
fi

export CLANG_MODULE_CACHE_PATH="$build_root/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$build_root/module-cache"
export SDKROOT="$sdk_path"

swift build \
  --build-system native \
  --package-path "$project_root" \
  --disable-sandbox \
  --scratch-path "$build_root" \
  --cache-path "$project_root/.swiftpm-cache" \
  --config-path "$project_root/.swiftpm-config" \
  --security-path "$project_root/.swiftpm-security" \
  --sdk "$sdk_path" \
  -c release

mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$build_root/release/QuotaBar" "$app_path/Contents/MacOS/QuotaBar"
cp "$project_root/Resources/Info.plist" "$app_path/Contents/Info.plist"
cp "$project_root/Resources/Icons/openai-blossom.svg" "$app_path/Contents/Resources/openai-blossom.svg"
chmod 755 "$app_path/Contents/MacOS/QuotaBar"

plutil -lint "$app_path/Contents/Info.plist"
xattr -cr "$app_path"
codesign --force --deep --sign - --timestamp=none "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"

echo "$app_path"
