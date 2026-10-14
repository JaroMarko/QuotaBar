import { expect, test } from 'claude-code/testing'

test('exports only plan windows and leaves private session fields out', async ($, on) => {
  let request
  on('session.usage', () => ({ value: { context: { percent: 99 }, cost: { secret: 'PRIVATE' },
    rateLimits: [{ kind: 'five_hour', percentUsed: 28, resetsAt: '2033-05-18T03:50:00Z' },
                 { kind: 'seven_day', percentUsed: 72, resetsAt: '2033-05-18T06:03:20Z' },
                 { kind: 'spend_limit', percentUsed: 10, resetsAt: '2033-05-18T06:03:20Z' }] } }))
  on('clock.now', () => ({ value: 2000000000000 }))
  on('process.run', (api, e) => { request = e; return { value: { exitCode: 0, stdout: '', stderr: '' } } })
  const answer = await $.command.run({ command: 'quotabar-sync', args: '' })
  expect(answer.text).toBe('QuotaBar: local plan limits updated.')
  const serialized = JSON.stringify(request)
  expect(serialized.includes('PRIVATE')).toBe(false)
  expect(serialized.includes('spend_limit')).toBe(false)
  expect(serialized.includes('percentUsed')).toBe(true)
})

test('missing plan windows produce absence, never zero', async ($, on) => {
  let serialized = ''
  on('session.usage', () => ({ value: { rateLimits: [] } }))
  on('clock.now', () => ({ value: 2000000000000 }))
  on('process.run', (api, e) => { serialized = JSON.stringify(e); return { value: { exitCode: 0, stdout: '', stderr: '' } } })
  const answer = await $.command.run({ command: 'quotabar-sync', args: '' })
  expect(answer.text.includes('no current plan limits')).toBe(true)
  expect(serialized.includes('percentUsed')).toBe(false)
})

test('export failure returns an actionable message without throwing', async ($, on) => {
  on('session.usage', () => ({ value: { rateLimits: [] } }))
  on('clock.now', () => ({ value: 2000000000000 }))
  on('process.run', () => ({ value: { exitCode: 1, stdout: '', stderr: '' } }))
  const answer = await $.command.run({ command: 'quotabar-sync', args: '' })
  expect(answer.text.includes('installed in Applications')).toBe(true)
})


test('missing reset still exports a reported percent without invented reset', async ($, on) => {
  let serialized = ''
  on('session.usage', () => ({ value: { rateLimits: [{ kind: 'five_hour', percentUsed: 22 }] } }))
  on('clock.now', () => ({ value: 2000000000000 }))
  on('process.run', (api, e) => { serialized = JSON.stringify(e); return { value: { exitCode: 0, stdout: '', stderr: '' } } })
  const answer = await $.command.run({ command: 'quotabar-sync', args: '' })
  expect(answer.text).toBe('QuotaBar: local plan limits updated.')
  expect(serialized.includes('percentUsed')).toBe(true)
  expect(serialized.includes('resetsAt')).toBe(false)
})
