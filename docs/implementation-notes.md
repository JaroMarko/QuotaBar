# QuotaBar implementation notes

Evidence, design decisions and validation are recorded here per stage.

## Phase 0/1 evidence
- Both baseline live probes succeeded: Claude 2 quota windows, Codex 1. No credentials were printed. Sandbox auth status differed from the unsandboxed successful request; do not interpret sandbox failure as logged out.
- Monitoring started only from a SwiftUI MenuBarExtra label task. Moved startup to NSApplicationDelegate; GUI confirmation remains required.
- ProcessRunner waited before draining pipes (deadlock risk); concurrent bounded draining added. Codex stderr now drained and initialized notification sent.
- Added finite-number validation, source/account metadata and distinct expiry/network/access errors. Existing auth files are not rewritten.
- Official Codex protocol reference: https://learn.chatgpt.com/docs/app-server

Phase 1 validation: build and 27 regression checks passed; both live probes succeeded after changes.
