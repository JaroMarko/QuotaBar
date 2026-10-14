# QuotaBar implementation plan

## Goal
Deliver a functioning local macOS Claude/Codex quota monitor with graphical menu-bar icons, diagnostics, adaptive refresh, trustworthy notifications and local history/pace. Commit each reviewed stage locally.

## Phases
- [x] 0. Preserve baseline and analyse current code/live failures.
- [x] 1. Repair acquisition, bounded subprocesses, schema validation and diagnostics; confirm live sources.
- [x] 2. Add graphical provider icons without text, quota details and freshness/account/source display.
- [x] 3. Adaptive refresh, wake/offline recovery, notification deduplication and confirmed resets.
- [ ] 4. Bounded local history, charts and conservative pace/forecast; alternative provider overview.
- [ ] 5. Build/package checks, app installation, documented limitations and memory update.

## Scope
No new backend, telemetry, provider purchases, account switching, mobile sync or leaderboard. No push requested. Use existing provider logins without rewriting auth files. Signing/notarization for public distribution depends on an existing Developer ID identity; do not claim notarization without it.

## Decisions
- Menu bar: two distinguishable graphical provider meters; consumed quota, no text/numeric percentages. Details on click.
- Unknown data stays unknown; stale measurements keep original timestamp.
- Initial analysis will refine each stage before implementation.

## Errors
- UI automation getApp timed out; retry GUI inspection after rebuilding.
- Initial write attempted without filesystem escalation and was denied before mutation; rerun under authorised escalation succeeded.

## Status
Phase 4: bounded history, charts and conservative forecasts.

## Acceptance criteria
1. Both live provider checks return nonempty validated quota windows; noisy child and stuck child probes terminate within bounds.
2. Menu bar contains only two graphical meters. Dotted meters represent unavailable/stale data, never zero. Detail cards show timestamps, source and exact reset.
3. Refresh interval responds to observed activity, risk and resets, with bounded retries and network/wake triggers. Repeated crossings in the same account/window emit at most one alert per threshold.
4. Local history is bounded by age/count, account and window. Charts never join different reset cycles; forecasts require multiple recent monotonic samples.
5. Build, regression suite, live checks, package payload and GUI inspection pass or any external limitation is stated explicitly. Public notarization only if an existing identity is available.

## Validation so far
- Phase 1: release build/codesign passed; 27 checks passed; live Claude (2 windows) and Codex (1 window) succeeded.

- Phase 3: release build and 35 checks passed. Real sleep/wake and GUI network recovery still need system-level verification.
