// No prompts, credentials, network requests, UI changes, or model calls.
// Measurement events are used instead of an idle timer that would make old data look fresh.
export async function publish($) {
  const usage = await $.session.usage()
  const rateLimits = (usage.rateLimits || []).flatMap(limit => {
    if (!['five_hour', 'seven_day'].includes(limit.kind) || !Number.isFinite(limit.percentUsed) ||
        limit.percentUsed < 0 || limit.percentUsed > 100) return []
    const clean = { kind: limit.kind, percentUsed: limit.percentUsed }
    if (limit.resetsAt !== undefined) {
      // session.usage uses an optional ISO8601 string, unlike statusline's epoch number.
      if (typeof limit.resetsAt !== 'string') return []
      const reset = Date.parse(limit.resetsAt)
      if (!Number.isFinite(reset)) return []
      clean.resetsAt = reset / 1000
    }
    return [clean]
  })
  const payload = JSON.stringify({ version: 1, capturedAt: (await $.clock.now()) / 1000, rateLimits })
  // Only this small allowlisted quota payload is passed; never the full session object.
  const result = await $.process.run(['/Applications/QuotaBar.app/Contents/MacOS/QuotaBar', '--capture-claude-usage', payload])
  if (result.exitCode !== 0) throw new Error('QuotaBar could not store the local quota measurement')
  return rateLimits.length
}

export function register(on) {
  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'quotabar-sync', description: 'Send current plan limits locally to QuotaBar' })
    // Starting/resuming may not yet have plan limits. Never turn an absence into zero.
    try { await publish($) } catch { /* QuotaBar may not be installed on a remote host. */ }
    return next(e)
  })
  on('session.measure', async ($, e, next) => {
    const result = await next(e)
    try { await publish($) } catch { /* A quota export must not interrupt Claude's work. */ }
    return result
  })
  on('command.run', { command: 'quotabar-sync' }, async ($) => {
    try {
      const count = await publish($)
      return { text: count ? 'QuotaBar: local plan limits updated.' : 'QuotaBar: no current plan limits in this Code session yet. Use Claude Code and retry after its response.' }
    } catch {
      return { text: 'QuotaBar: could not write the local measurement. Check that QuotaBar is installed in Applications.' }
    }
  })
}
