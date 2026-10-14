# QuotaBar

QuotaBar is a private, local-first macOS menu-bar app for Claude/Claude Code and ChatGPT Work/Codex subscription usage.

## Requirements

- macOS 14 or newer on Apple Silicon
- Codex CLI signed in with ChatGPT
- Local Claude Code session (Desktop Code>=2.1.286 or CLI>=2.1.287), signed in, with the included QuotaBar mod installed

QuotaBar never stores or logs provider credentials. It reads the existing CLI sessions only during refresh and stores preferences, the last successful usage snapshot, notification deduplication and bounded local usage history.

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

## Claude local bridge

After installing QuotaBar in `/Applications`, run `./scripts/install_claude_bridge.sh`. It adds only the bundled local marketplace and mod, preserving existing Claude plugins and Caveman statusline. In an existing local Code session, run `/reload-plugins` then `/quotabar-sync`, or open a new session. The mod exports on `session.measure` (turn completion / reported plan usage changes), and offers a manual sync command without an LLM request.

Only the 5-hour/weekly percentages, reset timestamps and measurement time are saved to `~/Library/Application Support/QuotaBar/claude-session-usage.json` using an atomic0600 write. No prompts, transcript, context percent, costs, credentials or session ID are saved. Missing windows never become zero. Read interval20s does not fetch the server or make data newer; after10min without an observation it is labelled last known. Its ring remains visible while that specific window has a known future reset; expired windows and old windows without reset timestamps are hidden. Chat/Cowork-only and remote/cloud sessions without the local QuotaBar app cannot provide this bridge.

`claude plugin uninstall quotabar-usage@quotabar-local` removes the bridge; it does not affect other plugins. A future public distribution must bundle setup instead of relying on the local repo marketplace path.

## Monitoring and privacy

- Menu bar: one compact24pt image (28pt status item), no text. Settings selects concentric rings (default:outer Claude,inner Codex),left/right semicircles (Claude/Codex),Claude only,Codex only or QuotaBar icon only. Provider-only modes retain their logo; combined modes have a refined Q matching the app identity in the centre. Combined rings use terracotta for Claude (#D97757) and cyan for Codex (#0891B2 on light backgrounds, #67E8F9 on dark backgrounds), with neutral unused tracks; the centre adapts to the menu bar appearance. Claude displays the shared 5-hour session; Codex displays its most-used reported window. Dotted rings mean current data is unavailable/stale, including a missing Claude 5h value.
- Interaction: left-click opens/closes the centred popup; right-click or Control-click opens a native Quit menu. Popup size follows the current content; macOS keeps it within screen edges.
- Popup: shared quota tiles side by side, circular usage rings with centred percentages and reset countdowns without scrolling. A Bar badge marks the ring window. Additional model windows, history, forecast, exact resets and source/account diagnostics are available in separate resizable Details windows. Claude session.usage does not supply account identity. Its source is shown in Details; Claude forecasts and automatic quota notifications are withheld while identity is unknown. Codex notifications and test notifications remain available.
- Activity: each provider pauses quota checks while neither its desktop app nor native CLI is running. Claude desktop/Claude Code and Codex/ChatGPT/Codex CLI are detected separately; inactive cards show Vypnutá and hide cached percentages/rings. App launch/quit updates promptly; CLI activity is checked by the20-second background loop and when refreshing. Failed detection stays unknown,not inactive. Own app-server and other users’ CLI processes are excluded.
- Errors: ? explains the problem on hover or click; popup shows the next retry time. A429 pause survives app restarts. Claude uses local session.usage measurements without OAuth/Keychain or HTTP quota requests; the old Claude429 cooldown is removed during migration. Provider contracts: `docs/data-sources-2026-10-14.md`.
- Refresh: 1 minute while usage changes, usage is high or reset is near; 5 minutes when quiet. Errors back off to 15 minutes, and 429 responses enforce a 10-minute cooldown even for manual refresh.
- Quota history: local `~/Library/Application Support/QuotaBar/history.json`, limited to 30 days and 10,000 samples. No prompts/transcripts are read. Clear it from the menu's trash button.
- Forecasts need >=3 recent monotonic samples spanning >=10 minutes in the same account/window/reset cycle. They are estimates and disappear when their assumptions fail.
- Settings → Notifications includes Send test notification; it reports missing permission/errors and never modifies quota history or notification deduplication. Banners can also appear while QuotaBar is active, subject to macOS notification and Focus settings.
- Settings and notification deduplication use the existing `com.jaroslavmarko.planmeter` preferences domain. Original provider credentials are never rewritten.

## Verification

Run `scripts/verify.sh`; live checks are optional via `scripts/verify.sh --live` and reuse existing provider logins. App smoke commands: `QuotaBar --verify-store`, `QuotaBar --verify-menu`, `QuotaBar --preview-icons /absolute/output.png`, `QuotaBar --preview-popup /absolute/output.png`, and `QuotaBar --smoke-report /absolute/report.json`. Smoke reports omit account identifiers and credentials.

Local builds use an ad-hoc signature. Public distribution still requires Developer ID signing and notarization; a successful local build is not a notarized release.
