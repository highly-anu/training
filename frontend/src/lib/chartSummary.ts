/**
 * A chart's numbers in words, for a reader who cannot see it. The wording is
 * the phone's (`ChartSummary`, ios/TrainingCompanion/AppAccessibility.swift),
 * so the two clients say a chart the same way. `ChartFrame` reads them out
 * (docs/frontend-design.md §12.11).
 */

type Format = (value: number) => string

const whole: Format = (v) => String(Math.round(v))
/** One decimal, a whole number written whole. */
export const oneDecimal: Format = (v) => String(Math.round(v * 10) / 10)
const suffix = (unit: string) => (unit ? ` ${unit}` : '')
const finite = (values: readonly (number | null | undefined)[]) =>
  values.filter((v): v is number => typeof v === 'number' && Number.isFinite(v))

/** "Average 142 bpm, from 98 to 171": a recording, where no point is the latest. */
export function range(values: readonly (number | null | undefined)[], unit = '', format: Format = whole): string | null {
  const vs = finite(values)
  if (!vs.length) return null
  const low = Math.min(...vs)
  const high = Math.max(...vs)
  const mean = vs.reduce((a, b) => a + b, 0) / vs.length
  if (low === high) return `${format(mean)}${suffix(unit)} throughout`
  return `Average ${format(mean)}${suffix(unit)}, from ${format(low)} to ${format(high)}`
}

/** "Latest 4 sessions, average 3, from 1 to 5": a series over time. */
export function series(values: readonly (number | null | undefined)[], unit = '', format: Format = whole): string | null {
  const vs = finite(values)
  if (!vs.length) return null
  const last = vs[vs.length - 1]
  if (vs.length === 1) return `${format(last)}${suffix(unit)}`
  const rest = range(vs, '', format)!
  return `Latest ${format(last)}${suffix(unit)}, ${rest[0].toLowerCase()}${rest.slice(1)}`
}

/** "Zone 2 62 percent, Zone 3 20 percent": shares of a whole, largest first, zeros left out. */
export function shares(parts: readonly { name: string; value: number }[]): string | null {
  const total = parts.reduce((sum, p) => sum + Math.max(p.value, 0), 0)
  if (total <= 0) return null
  const said = parts
    .map((p) => ({ name: p.name, percent: Math.round((Math.max(p.value, 0) / total) * 100) }))
    .filter((p) => p.percent > 0)
    .sort((a, b) => b.percent - a.percent)
  return said.length ? said.map((p) => `${p.name} ${p.percent} percent`).join(', ') : null
}

/** Several summaries as one sentence run; the ones with nothing to say are left out. */
export function join(...parts: (string | null | undefined | false)[]): string | null {
  const said = parts.filter((p): p is string => Boolean(p))
  return said.length ? said.join('. ') : null
}

/** A named series: "Fitness: latest 42, average 38, from 30 to 45". */
export function named(name: string, summary: string | null): string | null {
  return summary ? `${name}: ${summary[0].toLowerCase()}${summary.slice(1)}` : null
}
