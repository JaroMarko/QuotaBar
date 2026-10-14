# QuotaBar

QuotaBar is a private, local-first macOS menu-bar app for Claude/Claude Code and ChatGPT Work/Codex subscription usage.

## Requirements

- macOS 14 or newer on Apple Silicon
- Codex CLI signed in with ChatGPT
- Claude Code signed in with `claude auth login`

QuotaBar never stores or logs provider credentials. It reads the existing CLI sessions only during refresh and stores only preferences plus the last successful usage snapshot.

## Build and check

```sh
./scripts/verify.sh
./scripts/verify.sh --live  # also checks the existing provider logins
./scripts/package_pkg.sh
```

The app bundle is created at `dist/QuotaBar.app`. The package is written to the project `dist` directory by default.

The included check executable is used because this Mac's standalone Command Line Tools installation does not include a compatible XCTest runtime. It exercises the decoding, calculation, error, and notification logic and exits nonzero on failure.

The bundle and installer identifiers retain `com.jaroslavmarko.planmeter` for compatibility with existing settings.

The app build uses the native SwiftPM build system and macOS 26.5 SDK when available. Set `QUOTABAR_SDK_PATH` to override the SDK.

## Monitoring and privacy

- Menu bar: graphical Claude/Codex consumed-quota rings, no text. The most-used reported window is displayed; dotted rings mean current data is unavailable/stale.
- Menu: all returned windows, exact reset time, measurement timestamp and data source. Claude's usage endpoint does not supply confirmed account identity; its history is scoped to an opaque session fingerprint. Token renewal starts a new scope.
- Refresh: 1 minute while usage changes, usage is high or reset is near; 5 minutes when quiet. Errors back off to 15 minutes, and 429 responses enforce a 10-minute cooldown even for manual refresh.
- Quota history: local `~/Library/Application Support/QuotaBar/history.json`, limited to 30 days and 10,000 samples. No prompts/transcripts are read. Clear it from the menu's trash button.
- Forecasts need >=3 recent monotonic samples spanning >=10 minutes in the same account/window/reset cycle. They are estimates and disappear when their assumptions fail.
- Settings and notification deduplication use the existing `com.jaroslavmarko.planmeter` preferences domain. Original provider credentials are never rewritten.

## Verification

Run `scripts/verify.sh`; live checks are optional via `scripts/verify.sh --live` and reuse existing provider logins. App smoke commands: `QuotaBar --verify-store`, `QuotaBar --preview-icons /absolute/output.png`, and `QuotaBar --smoke-report /absolute/report.json`. Smoke reports omit account identifiers and credentials.

Local builds use an ad-hoc signature. Public distribution still requires Developer ID signing and notarization; a successful local build is not a notarized release.
