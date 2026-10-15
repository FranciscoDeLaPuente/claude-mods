import { expect, mock, test } from 'claude-code/testing'

import { bar, levelColor, limitName, tokens, untilReset } from '../hooks/register'

test('bars honour width and percentage', async () => {
  const half = bar(50, 10)
  expect(half.full).toBe('█████')
  expect(half.empty).toBe('░░░░░')
  expect(bar(0, 8).full).toBe('')
  expect(bar(130, 8).full).toBe('████████')
  expect(levelColor(75)).toBe('error')
  expect(levelColor(70)).toBe('error')
  expect(levelColor(50)).toBe('warning')
  expect(levelColor(49)).toBe('success')
  expect(tokens(200_000)).toBe('200k')
  expect(tokens(1_000_000)).toBe('1M')
  expect(limitName('five_hour')).toBe('5h')
  const now = Date.parse('2026-10-15T10:00:00Z')
  expect(untilReset('2026-10-15T12:13:00Z', now)).toBe('2h 13m')
  expect(untilReset('2026-10-18T14:00:00Z', now)).toBe('3d 4h')
})

test('below the prompt: the hint line, then context and quotas', async ($, on) => {
  mock.clock(on, { now: Date.parse('2026-10-15T10:00:00Z') })
  on('session.measure', ($, e) => ({ changed: e.changed }))
  on('ui.render', { component: 'PromptHint' }, ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text dimColor>{e.props.hint}</Text>
  })
  await $.session.measure({
    context: { tokens: 124_000, window: 200_000, percent: 62 },
    rateLimits: [
      { kind: 'five_hour', percentUsed: 34, resetsAt: '2026-10-15T12:13:00Z' },
      { kind: 'seven_day', percentUsed: 91.5 },
    ],
    cost: { usd: 1.234 },
    changed: ['context', 'rateLimits', 'cost'],
  })
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({
      plugin: 'faf-usage-meter',
      surface,
      component: 'PromptHint',
      props: { isDraft: false, isWorking: false, hint: '? for shortcuts' },
    })
    expect(await ui.find({ type: 'Text', text: /\? for shortcuts/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /62% 124k\/200k/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /5h/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /↻ 2h 13m/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /7 days/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /\$1\.23/ })).toBeDefined()
    await ui.unmount()
  }
})
