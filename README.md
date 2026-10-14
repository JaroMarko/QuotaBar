# QuotaBar

QuotaBar is a private, local-first macOS menu-bar app for Claude/Claude Code and ChatGPT Work/Codex subscription usage.

## Requirements

- macOS 14 or newer on Apple Silicon
- Codex CLI signed in with ChatGPT
- Claude Code signed in with `claude auth login`

QuotaBar never stores or logs provider credentials. It reads the existing CLI sessions only during refresh and stores only preferences plus the last successful usage snapshot.

## Build and check

```sh
SDKROOT="$(xcrun --show-sdk-path)" \
CLANG_MODULE_CACHE_PATH=.build-quotabar/module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=.build-quotabar/module-cache \
swift run --disable-sandbox \
  --scratch-path .build-quotabar \
  --cache-path .swiftpm-cache \
  --config-path .swiftpm-config \
  --security-path .swiftpm-security \
  --sdk "$(xcrun --show-sdk-path)" \
  QuotaBarChecks

./scripts/build_app.sh
./scripts/package_pkg.sh
```

The app bundle is created at `dist/QuotaBar.app`. The package is written to the project `dist` directory by default.

The included check executable is used because this Mac's standalone Command Line Tools installation does not include a compatible XCTest runtime. It exercises the decoding, calculation, error, and notification logic and exits nonzero on failure.

The bundle and installer identifiers retain `com.jaroslavmarko.planmeter` for compatibility with existing settings.

The app build uses the native SwiftPM build system and macOS 26.5 SDK when available. Set `QUOTABAR_SDK_PATH` to override the SDK.
