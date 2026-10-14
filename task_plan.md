# QuotaBar implementation plan

## Goal
Deliver a functioning local macOS Claude/Codex quota monitor with graphical menu-bar icons, diagnostics, adaptive refresh, trustworthy notifications and local history/pace. Commit each reviewed stage locally.

## Phases
- [ ] 0. Preserve baseline and analyse current code/live failures.
- [ ] 1. Repair acquisition, bounded subprocesses, schema validation and diagnostics; confirm live sources.
- [ ] 2. Add graphical provider icons without text, quota details and freshness/account/source display.
- [ ] 3. Adaptive refresh, wake/offline recovery, notification deduplication and confirmed resets.
- [ ] 4. Bounded local history, charts and conservative pace/forecast; alternative provider overview.
- [ ] 5. Build/package checks, app installation, documented limitations and memory update.

## Scope
No new backend, telemetry, provider purchases, account switching, mobile sync or leaderboard. No push requested. Use existing provider logins without rewriting auth files. Signing/notarization for public distribution depends on an existing Developer ID identity; do not claim notarization without it.

## Decisions
- Menu bar: two distinguishable graphical provider meters; consumed quota, no text/numeric percentages. Details on click.
- Unknown data stays unknown; stale measurements keep original timestamp.
- Initial analysis will refine each stage before implementation.

## Errors
None recorded yet.

## Status
Phase 0: analysing baseline.
