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

## Phase 4
History persists only percentages, window/account scope and measurement/reset times in Application Support/QuotaBar/history.json (atomic save, 0700 directory/0600 file). Retention is 30 days/10,000 samples. Malformed existing files are retained rather than overwritten. Charts show the current account/reset cycle and at most 96 recent points. Forecast requires 3 monotonic recent samples spanning >=10 minutes, a fresh last sample and known reset/account scope; it remains explicitly an estimate. Headroom is shown per provider without automated switching.

## Phase 5 startup investigation
The application smoke process hung in SwiftUI MenuBarExtraController.updateButton / NSStatusBarButton.setImage during finish-launching (sampled main thread). Native NSStatusItem replaces that bridge, while NSPopover/NSWindow host the existing SwiftUI content. This is a concrete GUI failure beyond successful provider CLI probes. Developer ID query returned 0 valid signing identities; no public notarization can be claimed.

Native startup smoke succeeded with both live providers and local history. Additional unknown opaque top-level fields are not inferred as quota windows; known five-hour/seven-day families and model-scoped limits are decoded. Icon preview rendered from the actual AppKit code. Release version is 1.1.0.

Final review: bounded subprocess input, cleanup on input errors and history suppression for unknown reset cycles added. 47 checks and store integration passed. Expanded package signature/hash passed. GUI screenshot tooling returned a blank Finder surface; no interactive GUI validation claim is made. Public signing/notarization needs an existing Developer ID certificate.

## Readable provider icons (1.1.1)
Jaro reported the 9pt symbols were illegible. Replaced them with a bold 16x14pt Clawd-style pixel mascot and OpenAI's official unmodified Blossom SVG; increased ring canvas from 20pt to 24pt and total icon width from 46pt to 60pt. Numeric text stays outside the menu bar.

## Claude recognisability (1.1.2)
Jaro found the custom pixel robot too large and not recognisable as Claude. Replaced it with the actual 24pt Claude spark geometry from the installed official app, rendered at 15pt inside the same quota ring. OpenAI artwork and status-item width are unchanged.
