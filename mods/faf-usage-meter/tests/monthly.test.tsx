import { expect, mock, test } from 'claude-code/testing'

import { money, toMonthly } from '../hooks/register'

const REPLY = {
  spend: {
    used: { amount_minor: 1234, currency: 'EUR', exponent: 2 },
    limit: { amount_minor: 5000, currency: 'EUR', exponent: 2 },
    enabled: true,
  },
}

test('monthly spend is read from spend in minor units', async () => {
  expect(toMonthly(REPLY, 0)).toEqual({ used: 12.34, limit: 50, currency: 'EUR', enabled: true, fetchedAt: 0 })
  expect(toMonthly({}, 0)).toBe(null)
  expect(money(12.345, 'EUR')).toBe('12,35 €')
})

test('band and pane show the account monthly spend', async ($, on) => {
  mock.clock(on, { now: Date.parse('2026-10-15T10:00:00Z') })
  let calls = 0
  on('session.authorize', () => ({ value: { handle: 'h', kind: 'bearer' as const } }))
  on('http.fetch', ($, e) => {
    calls++
    expect(e.url).toBe('https://api.anthropic.com/api/oauth/usage')
    expect(e.init?.auth).toBe('h')
    return { value: { status: 200, ok: true, headers: {}, text: JSON.stringify(REPLY) } }
  })
  on('session.measure', ($, e) => ({ changed: e.changed }))
  on('ui.render', { component: 'PromptHint' }, ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>{e.props.hint}</Text>
  })
  const m = {
    context: { tokens: 1000, window: 200_000, percent: 1 },
    rateLimits: [],
    cost: { usd: 0.5 },
    changed: ['cost'] as const,
  }
  await $.session.measure({ ...m, changed: ['cost'] })
  await $.session.measure({ ...m, changed: ['cost'] })
  expect(calls).toBe(1)

  for (const surface of ['terminal', 'desktop'] as const) {
    const band = await $.ui.mount({
      plugin: 'faf-usage-meter',
      surface,
      component: 'PromptHint',
      props: { isDraft: false, isWorking: false, hint: '?' },
    })
    expect(await band.find({ type: 'Text', text: /month 12,34 €\/50,00 €/ })).toBeDefined()
    await band.unmount()
  }
})
