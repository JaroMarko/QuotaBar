# QuotaBar usage bridge

Official Claude Code mod using `$.session.usage()`. Exports only plan limits locally on `session.measure`; does not invoke the OAuth usage endpoint or call a model. Requires QuotaBar1.4.0 in Applications and local Desktop Code>=2.1.286 / CLI>=2.1.287.

Install from the repo with `scripts/install_claude_bridge.sh`. Existing sessions need `/reload-plugins`; `/quotabar-sync` exports without starting a model turn. Normal Chat/Cowork do not run this mod. Existing statusline/plugins are preserved.

Validate/test: `claude plugin validate integrations/claude-quotabar --strict` and `claude plugin test integrations/claude-quotabar`. Tests stub runtime calls and never use real quotas or network. The app writer revalidates the bounded JSON, drops non-quota fields, serializes writers and atomically replaces a0600 file. Empty limits invalidate previous values. No idle timer refreshes capturedAt.

Sources: [mods](https://code.claude.com/docs/en/plugins/mods/overview), [session usage API](https://code.claude.com/docs/en/plugins/mods/reference).

Install from this local checkout: `claude plugin install quotabar-usage --marketplace ./integrations`.
