# QuotaBar implementation plan

## Goal
Deliver a functioning local macOS Claude/Codex quota monitor with graphical menu-bar icons, diagnostics, adaptive refresh, trustworthy notifications and local history/pace. Commit each reviewed stage locally.

## Phases
- [x] 0. Preserve baseline and analyse current code/live failures.
- [x] 1. Repair acquisition, bounded subprocesses, schema validation and diagnostics; confirm live sources.
- [x] 2. Add graphical provider icons without text, quota details and freshness/account/source display.
- [x] 3. Adaptive refresh, wake/offline recovery, notification deduplication and confirmed resets.
- [x] 4. Bounded local history, charts and conservative pace/forecast; alternative provider overview.
- [x] 5. Build/package checks, app installation, documented limitations and memory update.

## Scope
No new backend, telemetry, provider purchases, account switching, mobile sync or leaderboard. No push requested. Use existing provider logins without rewriting auth files. Signing/notarization for public distribution depends on an existing Developer ID identity; do not claim notarization without it.

## Decisions
- Menu bar: two distinguishable graphical provider meters; consumed quota, no text/numeric percentages. Details on click.
- Unknown data stays unknown; stale measurements keep original timestamp.
- Initial analysis will refine each stage before implementation.

## Errors
- UI automation getApp timed out; retry GUI inspection after rebuilding.
- Initial write attempted without filesystem escalation and was denied before mutation; rerun under authorised escalation succeeded.

- Phase 4 diff check found trailing whitespace; removed before commit.

- Phase 5 app smoke hung during SwiftUI MenuBarExtra image-update startup; stack sampling identified the main-thread loop. Replaced MenuBarExtra with native NSStatusItem and hosted SwiftUI content.

- Package expansion carried FinderInfo on its app root; packaging now strips only signature-invalid attributes and verifies staging before building. Validate expanded contents separately from extraction metadata.

- macOS Python lacks os.listxattr; packaging attribute cleanup uses the native xattr utility instead.

## Status
Local implementation complete; public notarization and manual long-term GUI/sleep/wake verification remain external follow-ups.

## Acceptance criteria
1. Both live provider checks return nonempty validated quota windows; noisy child and stuck child probes terminate within bounds.
2. Menu bar contains only two graphical meters. Dotted meters represent unavailable/stale data, never zero. Detail cards show timestamps, source and exact reset.
3. Refresh interval responds to observed activity, risk and resets, with bounded retries and network/wake triggers. Repeated crossings in the same account/window emit at most one alert per threshold.
4. Local history is bounded by age/count, account and window. Charts never join different reset cycles; forecasts require multiple recent monotonic samples.
5. Build, regression suite, live checks, package payload and GUI inspection pass or any external limitation is stated explicitly. Public notarization only if an existing identity is available.

## Validation so far
- Phase 1: release build/codesign passed; 27 checks passed; live Claude (2 windows) and Codex (1 window) succeeded.

- Phase 3: release build and 35 checks passed. Real sleep/wake and GUI network recovery still need system-level verification.

- Phase 4: release build and 44 checks passed, including account/reset isolation, retention and forecast guards.

## Final verification
- Release 1.1.0 builds; local ad-hoc codesign validates.
- 47 core regression checks passed; application store integration checks passed.
- Both live provider probes and actual application startup report passed (Claude 2 windows, Codex 1; neither stale).
- Installer expanded successfully; app signature valid after expansion and binary SHA-256 matches the build.
- Final app installed at /Applications/QuotaBar.app; previous version retained in workspace work backup.
- No Developer ID identities found; public notarization unavailable.
- CUA cannot select the accessory app; Finder screenshot returned blank. Native icon rendering was inspected, but full interactive GUI and real sleep/wake remain unverified.
- Packaging emits four platform metadata write warnings; staging and final expanded signature/hash validation pass.

## Compact UX and optimisation (1.2.0)
- [x] Analyse meter semantics: highest finite reported percentage across all windows initially; user now requires Claude fixed to 5h, Codex unchanged.
- [x] Compact no-scroll overview with selected ring window visible; details/history in a separate window.
- [x] Remove duplicated presentation and avoid work for hidden history; consolidate selection logic.
- [x] Regression/build/live checks plus deterministic light/dark and stale/error popup rendering.
- [x] Install, commit locally, and update external memory.

Preserve authentication, refresh/backoff, notifications, privacy and cache formats. Avoid broad rewrites or speculative micro-optimisations.

Validated: 53 core checks, store integration, live Claude2/Codex1 windows; native light/dark478pt, stale520pt, 20-window543pt, error611pt, unknown260pt previews. Installed1.2.0 signature and binary match. Interactive CUA accessory-app selection remains unavailable.
