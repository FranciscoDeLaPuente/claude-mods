import { expect, mock, test } from 'claude-code/testing'

import { effortDots, effortLabel, modelName } from '../hooks/register'

const PANE_PROPS = {
  title: 'Claude usage',
  isFocused: false,
  bodyColumns: 80,
  placement: 'dock' as const,
  scroll: { offset: 0, bodyRows: 40 },
  view: {},
}

test('model ids read as family and version', async () => {
  expect(modelName('claude-opus-5-5')).toBe('Opus 5.5')
  expect(modelName('claude-sonnet-4-5-20250929')).toBe('Sonnet 4.5')
  expect(modelName('claude-opus-4-20250514')).toBe('Opus 4')
  expect(modelName('claude-opus-4-6[1m]')).toBe('Opus 4.6 1M')
  expect(modelName('opus')).toBe('opus')
  expect(effortLabel('high')).toBe('high')
  expect(effortLabel(8000)).toBe('8k')
  expect(effortLabel(undefined)).toBe(null)
  expect(effortDots('high')).toEqual({ full: '●●●', empty: '○○' })
  expect(effortDots('max')).toEqual({ full: '●●●●●', empty: '' })
  expect(effortDots(8000)).toBe(null)
})

test('band and pane show the main loop model and its effort', async ($, on) => {
  mock.clock(on, { now: Date.parse('2026-10-15T10:00:00Z') })
  on('session.measure', ($, e) => ({ changed: e.changed }))
  on('ui.render', { component: 'PromptHint' }, ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>{e.props.hint}</Text>
  })
  on('turn.step', async function* ($, e) {
    return { turnId: e.turnId, index: e.index, answer: '', toolUses: [], stopReason: 'end_turn' as const, usage: null }
  })
  await $.session.measure({
    context: { tokens: 1000, window: 200_000, percent: 1 },
    rateLimits: [],
    changed: ['context'],
  })

  const step = async (model: string, effort: 'high' | 'low' | undefined, agentId?: string) => {
    for await (const _ of $.turn.step({ turnId: 't', index: 0, model, effort, messageCount: 1, agentId })) {
      // Sin trozos: solo cuenta el resultado.
    }
  }
  await step('claude-opus-5-5', 'high')
  // Un subagente con otro modelo no cambia lo que se muestra.
  await step('claude-haiku-5-5', 'low', 'agent-1')

  for (const surface of ['terminal', 'desktop'] as const) {
    const band = await $.ui.mount({
      plugin: 'faf-usage-meter',
      surface,
      component: 'PromptHint',
      props: { isDraft: false, isWorking: false, hint: '?' },
    })
    expect(await band.find({ type: 'Text', text: /^Opus 5\.5$/ })).toBeDefined()
    expect(await band.find({ type: 'Text', text: /· high/ })).toBeDefined()
    expect(await band.find({ type: 'Text', text: /Haiku/ })).toBeUndefined()
    await band.unmount()

    const pane = await $.ui.mount({
      plugin: 'faf-usage-meter',
      surface,
      component: 'Pane',
      requestId: 'faf-usage-meter',
      props: PANE_PROPS,
    })
    expect(await pane.find({ type: 'Text', text: /claude-opus-5-5/ })).toBeDefined()
    expect(await pane.find({ type: 'Text', text: /^●●●$/ })).toBeDefined()
    await pane.unmount()
  }

  // Sin esfuerzo (un modelo que no lo admite): el panel lo dice.
  await step('claude-opus-5-5', undefined)
  const pane = await $.ui.mount({
    plugin: 'faf-usage-meter',
    surface: 'terminal',
    component: 'Pane',
    requestId: 'faf-usage-meter',
    props: PANE_PROPS,
  })
  expect(await pane.find({ type: 'Text', text: /not applicable/ })).toBeDefined()
  await pane.unmount()
})
