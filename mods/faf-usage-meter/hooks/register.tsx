import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Breakdown, Limit, Model, Monthly, Snapshot } from '../types'

const PANE = 'faf-usage-meter'
const TITLE = 'Claude usage'

const snap = atom({ plugin: 'faf-usage-meter', key: 'snap' } as const, null)
const breakdown = atom({ plugin: 'faf-usage-meter', key: 'breakdown' } as const, null)
const isBandHidden = atom({ plugin: 'faf-usage-meter', key: 'isBandHidden' } as const, false)
const monthly = atom({ plugin: 'faf-usage-meter', key: 'monthly' } as const, null)
const model = atom({ plugin: 'faf-usage-meter', key: 'model' } as const, null)

// Endpoint que usa /usage: gasto de extra usage de la cuenta, común a todos los equipos.
const USAGE_URL = 'https://api.anthropic.com/api/oauth/usage'
const MONTHLY_TTL_MS = 5 * 60_000

const LIMIT_NAMES: Record<string, string> = {
  five_hour: '5h',
  seven_day: '7 days',
  seven_day_opus: '7 days Opus',
  seven_day_sonnet: '7 days Sonnet',
  spend_limit: 'Spend',
}

const EIGHTHS = ['', '▏', '▎', '▍', '▌', '▋', '▊', '▉']

const EFFORT_LEVELS = ['low', 'medium', 'high', 'xhigh', 'max']

// Barra de `width` celdas con resolución de 1/8 de celda.
export function bar(percent: number, width: number): { full: string; empty: string } {
  const p = Math.max(0, Math.min(100, percent))
  const eighths = Math.round((p / 100) * width * 8)
  const whole = Math.floor(eighths / 8)
  const part = EIGHTHS[eighths % 8]
  const used = '█'.repeat(whole) + part
  const rest = Math.max(0, width - whole - (part ? 1 : 0))

  return { full: used, empty: '░'.repeat(rest) }
}

export function levelColor(percent: number): 'success' | 'warning' | 'error' {
  if (percent >= 70) return 'error'
  if (percent >= 50) return 'warning'
  return 'success'
}

export function tokens(n: number | undefined): string {
  if (n === undefined) return '—'
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(n % 1_000_000 === 0 ? 0 : 1)}M`
  if (n >= 1000) return `${Math.round(n / 1000)}k`
  return String(n)
}

export function limitName(kind: string): string {
  return LIMIT_NAMES[kind] ?? kind.replace(/_/g, ' ')
}

// "2h 13m", "3d 4h", "12m"
export function untilReset(resetsAt: string | undefined, now: number): string | null {
  if (!resetsAt) return null
  const ms = Date.parse(resetsAt) - now
  if (!Number.isFinite(ms)) return null
  if (ms <= 0) return 'now'
  const min = Math.round(ms / 60_000)
  const d = Math.floor(min / 1440)
  const h = Math.floor((min % 1440) / 60)
  const m = min % 60
  if (d > 0) return `${d}d ${h}h`
  if (h > 0) return `${h}h ${m}m`
  return `${m}m`
}

function resetClock(resetsAt: string | undefined): string | null {
  if (!resetsAt) return null
  const date = new Date(resetsAt)
  if (Number.isNaN(date.getTime())) return null
  const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
  const hh = String(date.getHours()).padStart(2, '0')
  const mm = String(date.getMinutes()).padStart(2, '0')

  return `${days[date.getDay()]} ${hh}:${mm}`
}

// "claude-opus-5-5" → "Opus 5.5", "claude-sonnet-4-5-20250929[1m]" → "Sonnet 4.5 1M"; lo demás, tal cual.
export function modelName(id: string): string {
  const m = /^(?:claude-)?(fable|opus|sonnet|haiku)-(\d+)(?:-(\d{1,2}))?(?:-\d{8})?(\[1m\])?$/i.exec(id.trim())
  if (!m || !m[1] || !m[2]) return id
  const family = m[1][0]!.toUpperCase() + m[1].slice(1).toLowerCase()
  const version = m[3] ? `${m[2]}.${m[3]}` : m[2]

  return `${family} ${version}${m[4] ? ' 1M' : ''}`
}

// El esfuerzo es un nivel ("high") o un presupuesto de tokens ("8k").
export function effortLabel(effort: string | number | undefined): string | null {
  if (effort === undefined) return null
  return typeof effort === 'number' ? tokens(effort) : effort
}

// Nivel de esfuerzo en 5 puntos: high → ●●●○○
export function effortDots(effort: string | number | undefined): { full: string; empty: string } | null {
  const i = typeof effort === 'string' ? EFFORT_LEVELS.indexOf(effort) : -1
  if (i < 0) return null

  return { full: '●'.repeat(i + 1), empty: '○'.repeat(EFFORT_LEVELS.length - i - 1) }
}

const CURRENCY_SYMBOLS: Record<string, string> = { EUR: '€', USD: '$', GBP: '£' }

// "12,34 €"
export function money(amount: number, currency: string): string {
  const sign = CURRENCY_SYMBOLS[currency] ?? currency

  return `${amount.toFixed(2).replace('.', ',')} ${sign}`
}

type Money = { amount_minor: number; currency: string; exponent: number }

type UsageReply = {
  spend?: { used?: Money; limit?: Money; enabled?: boolean } | null
  extra_usage?: {
    is_enabled?: boolean
    monthly_limit?: number | null
    used_credits?: number | null
    currency?: string
  } | null
}

const fromMinor = (m: Money): number => m.amount_minor / 10 ** m.exponent

export function toMonthly(reply: UsageReply, now: number): Monthly | null {
  const spend = reply.spend
  if (spend?.used) {
    return {
      used: fromMinor(spend.used),
      limit: spend.limit ? fromMinor(spend.limit) : undefined,
      currency: spend.used.currency,
      enabled: spend.enabled ?? true,
      fetchedAt: now,
    }
  }
  const extra = reply.extra_usage
  if (extra && typeof extra.used_credits === 'number') {
    return {
      used: extra.used_credits,
      limit: extra.monthly_limit ?? undefined,
      currency: extra.currency ?? 'USD',
      enabled: extra.is_enabled ?? false,
      fetchedAt: now,
    }
  }

  return null
}

async function refreshMonthly($: EngineInterface, force = false): Promise<void> {
  try {
    const now = await $.clock.now()
    const current = await read($, monthly)
    if (!force && current && now - current.fetchedAt < MONTHLY_TTL_MS) return
    const auth = await $.session.authorize()
    if (!auth) return
    const res = await $.http.fetch(USAGE_URL, {
      auth: auth.handle,
      headers: { 'anthropic-beta': 'oauth-2025-04-20' },
    })
    if (!res.ok) return
    const value = toMonthly(JSON.parse(res.text) as UsageReply, now)
    if (value) await update($, monthly, () => value)
  } catch {
    // Sin red o sin login de claude.ai: se queda el último dato.
  }
}

type Measured = {
  context: { tokens?: number; window: number; percent?: number }
  rateLimits: Limit[]
  cost?: { usd: number }
}

function toSnapshot(m: Measured): Snapshot {
  return {
    tokens: m.context.tokens,
    window: m.context.window,
    percent: m.context.percent,
    limits: m.rateLimits.map(l => ({ kind: l.kind, percentUsed: l.percentUsed, resetsAt: l.resetsAt })),
    usd: m.cost?.usd,
  }
}

async function refreshBreakdown($: EngineInterface): Promise<void> {
  try {
    const usage = await $.session.usage({ breakdown: 'summary' })
    const b = usage.context.breakdown
    if (!b) return
    const value: Breakdown = {
      categories: b.categories
        .filter(c => !c.isDeferred)
        .map(c => ({ name: c.name, tokens: c.tokens, color: c.color, kind: c.kind })),
      totalTokens: b.totalTokens,
      maxTokens: b.rawMaxTokens,
      autoCompactAt: b.isAutoCompactEnabled ? b.autoCompactThreshold : undefined,
    }
    await update($, breakdown, () => value)
  } catch {
    // Sin sesión enlazada todavía: se reintenta en la siguiente medición.
  }
}

export const register: Register = on => {
  let isPaneOpen = false

  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'faf-usage',
      description: 'Open the pane with the context breakdown and quotas',
    })
    await $.command.register({
      name: 'faf-usage-band',
      description: 'Show or hide the context and quota bar below the prompt',
    })
    const ran = await next(e)
    await update($, snap, () => null)
    try {
      const usage = await $.session.usage()
      await update($, snap, () => toSnapshot(usage))
    } catch {
      // Se rellenará con la primera medición.
    }
    await refreshMonthly($, true)
    try {
      const id = await $.session.model()
      await update($, model, m => ({ id, effort: m?.effort }))
    } catch {
      // La primera petición dirá el modelo.
    }

    return ran
  })

  on('session.measure', async ($, e, next) => {
    await update($, snap, () => toSnapshot(e))
    if (isPaneOpen && e.changed.includes('context')) {
      await refreshBreakdown($)
    }
    if (e.changed.includes('rateLimits') || e.changed.includes('cost')) {
      await refreshMonthly($)
    }

    return next(e)
  })

  // Cada petición del bucle principal dice el modelo y el esfuerzo con que sale (tras /model, /effort o un fallback).
  on('turn.step', async function* ($, e, next) {
    if (e.agentId === undefined) {
      const m = await read($, model)
      if (m?.id !== e.model || m.effort !== e.effort) {
        const value: Model = { id: e.model, effort: e.effort }
        await update($, model, () => value)
      }
    }

    return yield* next(e)
  })

  on('command.run', { command: 'faf-usage' }, async $ => {
    await refreshBreakdown($)
    await refreshMonthly($, true)
    const { isPlaced } = await $.ui.open({ id: PANE, title: TITLE })
    isPaneOpen = true

    return { text: isPlaced ? 'Usage pane opened.' : 'Usage pane ready; it will appear when there is room.' }
  })

  on('command.run', { command: 'faf-usage-band' }, async $ => {
    const hidden = await update($, isBandHidden, v => !v)

    return { text: hidden ? 'Usage bar hidden.' : 'Usage bar shown.' }
  })

  // Bajo la caja de entrada: la línea de ayuda del motor tal cual y, debajo, las barras.
  on('ui.render', { component: 'PromptHint' }, async ($, e, next) => {
    const hint = await next(e)
    const s = await read($, snap)
    const mo = await read($, monthly)
    const mdl = await read($, model)
    if (s === null || (await read($, isBandHidden))) {
      return hint
    }

    const { Box, Text } = $.ui.resolve(e)
    const now = await $.clock.now()
    const columns = e.viewport?.columns ?? 100
    const width = columns >= 140 ? 16 : columns >= 100 ? 10 : 6
    const pct = s.percent ?? 0
    const ctx = bar(pct, width)

    return (
      <Box flexDirection="column" rowGap={1}>
        {hint}
        <Box flexDirection="row" flexWrap="wrap" columnGap={2}>
          {mdl && (
            <Box flexDirection="row">
              <Text>{modelName(mdl.id)}</Text>
              {effortLabel(mdl.effort) && <Text dimColor> · {effortLabel(mdl.effort)}</Text>}
            </Box>
          )}
          <Box flexDirection="row">
            <Text dimColor>ctx </Text>
            <Text color={levelColor(pct)}>{ctx.full}</Text>
            <Text color="inactive">{ctx.empty}</Text>
            <Text>
              {' '}
              {s.percent ?? '—'}% {tokens(s.tokens)}/{tokens(s.window)}
            </Text>
          </Box>
          {s.limits.length === 0 && <Text dimColor>quota: no data yet</Text>}
          {s.limits.map(l => {
            const b = bar(l.percentUsed, width)
            const left = untilReset(l.resetsAt, now)

            return (
              <Box flexDirection="row" key={l.kind}>
                <Text dimColor>{limitName(l.kind)} </Text>
                <Text color={levelColor(l.percentUsed)}>{b.full}</Text>
                <Text color="inactive">{b.empty}</Text>
                <Text> {Math.round(l.percentUsed)}%</Text>
                {left && <Text dimColor> ↻ {left}</Text>}
              </Box>
            )
          })}
          {s.usd !== undefined && <Text dimColor>${s.usd.toFixed(2)}</Text>}
          {mo && (
            <Text dimColor>
              month {money(mo.used, mo.currency)}
              {mo.limit ? `/${money(mo.limit, mo.currency)}` : ''}
            </Text>
          )}
        </Box>
      </Box>
    )
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    const s = await read($, snap)
    const bd = await read($, breakdown)
    const mo = await read($, monthly)
    const mdl = await read($, model)
    const now = await $.clock.now()
    const columns = e.viewport?.columns ?? 60
    const width = Math.max(10, Math.min(40, columns - 30))

    if (s === null) {
      return <Text dimColor>No measurements yet: they appear after the first response.</Text>
    }

    const pct = s.percent ?? 0
    const ctx = bar(pct, width)
    const stackMax = bd?.maxTokens ?? s.window
    const used = bd?.categories.filter(c => c.kind === 'used' && c.tokens > 0) ?? []
    const dots = effortDots(mdl?.effort)

    return (
      <Box flexDirection="column" rowGap={1}>
        {mdl && (
          <Box flexDirection="column">
            <Text weight="bold">Model</Text>
            <Text>
              {modelName(mdl.id)}
              {modelName(mdl.id) !== mdl.id && <Text dimColor> ({mdl.id})</Text>}
            </Text>
            <Box flexDirection="row">
              <Text>{'Effort'.padEnd(12)}</Text>
              {dots && <Text>{dots.full}</Text>}
              {dots && <Text color="inactive">{dots.empty}</Text>}
              <Text dimColor>
                {dots ? ' ' : ''}
                {effortLabel(mdl.effort) ?? 'not applicable to this model'}
              </Text>
            </Box>
          </Box>
        )}

        <Box flexDirection="column">
          <Text weight="bold">Context</Text>
          <Box flexDirection="row">
            <Text color={levelColor(pct)}>{ctx.full}</Text>
            <Text color="inactive">{ctx.empty}</Text>
            <Text> {s.percent ?? '—'}%</Text>
          </Box>
          <Text dimColor>
            {tokens(s.tokens)} of {tokens(s.window)} tokens
            {bd?.autoCompactAt ? ` · auto-compacts at ${tokens(bd.autoCompactAt)}` : ''}
          </Text>
        </Box>

        {used.length > 0 && (
          <Box flexDirection="column">
            <Text weight="bold">Breakdown (estimated)</Text>
            <Box flexDirection="row">
              {used.map(c => (
                <Text key={c.name} color={c.color}>
                  {'█'.repeat(Math.max(1, Math.round((c.tokens / stackMax) * width)))}
                </Text>
              ))}
            </Box>
            {used.map(c => (
              <Box flexDirection="row" key={`row-${c.name}`}>
                <Text color={c.color}>■ </Text>
                <Text>{c.name}</Text>
                <Text dimColor>
                  {' '}
                  {tokens(c.tokens)} ({((c.tokens / stackMax) * 100).toFixed(1)}%)
                </Text>
              </Box>
            ))}
          </Box>
        )}

        <Box flexDirection="column">
          <Text weight="bold">Quota</Text>
          {s.limits.length === 0 && (
            <Text dimColor>No data (arrives with the first response; subscriptions only).</Text>
          )}
          {s.limits.map(l => {
            const b = bar(l.percentUsed, width)
            const left = untilReset(l.resetsAt, now)
            const at = resetClock(l.resetsAt)

            return (
              <Box flexDirection="column" key={`lim-${l.kind}`}>
                <Box flexDirection="row">
                  <Text>{limitName(l.kind).padEnd(12)}</Text>
                  <Text color={levelColor(l.percentUsed)}>{b.full}</Text>
                  <Text color="inactive">{b.empty}</Text>
                  <Text> {l.percentUsed}% / 100%</Text>
                </Box>
                {left && (
                  <Text dimColor>
                    {'            '}resets in {left}
                    {at ? ` (${at})` : ''}
                  </Text>
                )}
              </Box>
            )
          })}
        </Box>

        <Box flexDirection="column">
          <Text weight="bold">Monthly spend (account)</Text>
          {mo === null && <Text dimColor>No data: sign in with a claude.ai account.</Text>}
          {mo && !mo.enabled && <Text dimColor>Extra usage disabled: no spend beyond the subscription.</Text>}
          {mo && mo.enabled && (
            <Box flexDirection="column">
              {mo.limit ? (
                <Box flexDirection="row">
                  <Text color={levelColor((mo.used / mo.limit) * 100)}>{bar((mo.used / mo.limit) * 100, width).full}</Text>
                  <Text color="inactive">{bar((mo.used / mo.limit) * 100, width).empty}</Text>
                  <Text>
                    {' '}
                    {money(mo.used, mo.currency)} of {money(mo.limit, mo.currency)}
                  </Text>
                </Box>
              ) : (
                <Text>
                  {money(mo.used, mo.currency)} <Text dimColor>(no limit set)</Text>
                </Text>
              )}
              <Text dimColor>Extra usage across all your teams; the fixed subscription quota is separate.</Text>
            </Box>
          )}
        </Box>

        {s.usd !== undefined && <Text dimColor>Estimated cost of this session (API pricing): ${s.usd.toFixed(2)}</Text>}
      </Box>
    )
  })
}
