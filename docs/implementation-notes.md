# QuotaBar implementation notes

Evidence, design decisions and validation are recorded here per stage.

## Phase 0/1 evidence
- Both baseline live probes succeeded: Claude 2 quota windows, Codex 1. No credentials were printed. Sandbox auth status differed from the unsandboxed successful request; do not interpret sandbox failure as logged out.
- Monitoring started only from a SwiftUI MenuBarExtra label task. Moved startup to NSApplicationDelegate; GUI confirmation remains required.
- ProcessRunner waited before draining pipes (deadlock risk); concurrent bounded draining added. Codex stderr now drained and initialized notification sent.
- Added finite-number validation, source/account metadata and distinct expiry/network/access errors. Existing auth files are not rewritten.
- Official Codex protocol reference: https://learn.chatgpt.com/docs/app-server

Phase 1 validation: build and 27 regression checks passed; both live probes succeeded after changes.

## Phase 2 design
Menu bar is a single monochrome template image containing Claude sparkle and Codex code symbols with independent consumed-quota rings. Each ring uses the most-used reported window. Unknown/stale values use dotted rings, never a 0% fill. Exact windows, timestamps, source/account availability and reset dates are in the menu.

Phase 2: release build and 27 checks passed. Graphical rendering and GUI startup will also be inspected in final smoke verification.

## Phase 3
Observed quota changes, >=90% usage and upcoming resets select 60s refresh; quiet quotas select 300s. Failures back off to 900s, 429 cooldown is 600s and manual refresh cannot bypass it. NWPathMonitor and workspace wake/sleep callbacks drive recovery. AlertLedger persists bounded account/window/cycle keys to suppress duplicate crossings across restarts. Claude scope is a nonreversible session-token fingerprint because the usage endpoint supplies no confirmed account identity; rotating login tokens starts a new history scope rather than mixing accounts.
