export type Limit = { kind: string; percentUsed: number; resetsAt?: string }

export type Snapshot = {
  tokens?: number
  window: number
  percent?: number
  limits: Limit[]
  usd?: number
}

export type Category = { name: string; tokens: number; color: string; kind: string }

export type Breakdown = {
  categories: Category[]
  totalTokens: number
  maxTokens: number
  autoCompactAt?: number
}

// Gasto de la cuenta en el mes (extra usage), en unidades de la moneda.
export type Monthly = {
  used: number
  limit?: number
  currency: string
  enabled: boolean
  fetchedAt: number
}

// Modelo con que sale la última petición del bucle principal y su esfuerzo (nivel o presupuesto de tokens).
export type Model = {
  id: string
  effort?: string | number
}

declare module 'claude-code' {
  interface PluginState {
    'faf-usage-meter': {
      snap: Snapshot | null
      breakdown: Breakdown | null
      isBandHidden: boolean
      monthly: Monthly | null
      model: Model | null
    }
  }
}
