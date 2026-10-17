import { useMemo } from 'react'
import {
  ResponsiveContainer, LineChart, Line, XAxis, YAxis, Tooltip, ReferenceLine, ReferenceArea,
} from 'recharts'
import { format } from 'date-fns'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import { levelName, STANDARD_LEVELS } from '@/lib/standards'
import type { ModalityId, StandardBlock, StandardEntry } from '@/api/types'

const DAY = 86_400_000
// Room on the right for the longest level label ("intermediate 1.5×BW"), and
// the rough plot width and 9 px glyph width that decide whether a block's
// name fits inside its band.
const LABEL_GUTTER = 108
const PLOT_WIDTH = 340
const CHAR_WIDTH = 5

function dayMs(iso: string): number {
  return new Date(`${iso}T12:00:00`).getTime()
}

const SOURCE_LABEL: Record<string, string> = {
  manual: 'Typed in', session: 'From a session', garmin: 'Garmin', apple_watch: 'Apple Watch', workout: 'From a workout',
}

interface Props {
  entries: StandardEntry[]
  /** Threshold values and their text, for the dashed level lines. */
  thresholds?: Partial<Record<string, number>>
  thresholdText?: Partial<Record<string, string>>
  domain?: string | null
  blocks?: StandardBlock[]
}

interface TooltipProps { active?: boolean; payload?: Array<{ payload: StandardEntry & { x: number } }> }

function PointTooltip({ active, payload }: TooltipProps) {
  if (!active || !payload?.length) return null
  const e = payload[0].payload
  return (
    <div className="rounded-md border border-border bg-card px-3 py-2 text-xs shadow-md space-y-0.5">
      <p className="font-medium text-muted-foreground">{format(new Date(e.x), 'd MMM yyyy')}</p>
      <p className="text-foreground"><span className="font-semibold tabular-nums">{e.valueText}</span> · {levelName(e.level).toLowerCase()}</p>
      {e.inputText && <p className="text-muted-foreground">{e.inputText}</p>}
      <p className="text-muted-foreground">{SOURCE_LABEL[e.source] ?? e.source}{e.block ? ` · ${e.block.name}` : ''}</p>
    </div>
  )
}

/**
 * A standard's results over time. One series in the colour of the modality the
 * standard measures (no legend: the sheet's title names it), each level as a
 * dashed threshold line labelled with its word and value (the y-axis has no
 * ticks of its own), and the program blocks the
 * results fell in as alternating bands — results belong to the athlete and run
 * across programs. Hover a point for its day, value, level and source.
 */
export function StandardHistoryChart({ entries, thresholds, thresholdText, domain, blocks = [] }: Props) {
  const color = (domain && MODALITY_COLORS[domain as ModalityId]?.hex) || 'var(--color-primary)'
  const data = useMemo(() => entries.map((e) => ({ ...e, x: dayMs(e.date) })), [entries])

  if (data.length === 0) return null
  const first = data[0].x
  const last = data[data.length - 1].x
  // A lone result still gets a readable span either side of it.
  const pad = Math.max((last - first) * 0.06, 10 * DAY)
  const domainX: [number, number] = [first - pad, last + pad]
  const levels = STANDARD_LEVELS.filter((l) => thresholds?.[l] != null)
  const values = [...data.map((d) => d.value), ...levels.map((l) => thresholds![l]!)]
  const lo = Math.min(...values)
  const hi = Math.max(...values)
  const span = hi - lo || Math.abs(hi) || 1
  const domainY: [number, number] = [Math.max(0, lo - span * 0.08), hi + span * 0.08]
  const bands = blocks
    .map((b) => ({ ...b, x1: Math.max(dayMs(b.from), domainX[0]), x2: Math.min(b.to ? dayMs(b.to) + DAY : domainX[1], domainX[1]) }))
    .filter((b) => b.x2 > b.x1)

  return (
    <div className="space-y-1" role="img" aria-label={`${data.length} results over time`}>
      <ResponsiveContainer width="100%" height={200}>
        <LineChart data={data} margin={{ top: 16, right: LABEL_GUTTER, left: 8, bottom: 0 }}>
                    {bands.map((b, i) => (
            // A block too narrow for its name stays unlabelled; the tooltip names it.
            <ReferenceArea key={b.id} x1={b.x1} x2={b.x2} fill="var(--color-muted-foreground)"
                           fillOpacity={i % 2 === 0 ? 0.07 : 0.03} strokeOpacity={0} ifOverflow="hidden"
                           label={(b.x2 - b.x1) / (domainX[1] - domainX[0]) * PLOT_WIDTH >= b.name.length * CHAR_WIDTH
                             ? { value: b.name, position: 'insideTopLeft', fontSize: 9, fill: 'var(--color-muted-foreground)' }
                             : undefined} />
          ))}
          {levels.map((l) => (
            <ReferenceLine key={l} y={thresholds![l]!} stroke="var(--color-muted-foreground)" strokeOpacity={0.5}
                           strokeDasharray="4 4" ifOverflow="extendDomain"
                           label={{ value: `${l} ${thresholdText?.[l] ?? ''}`.trim(), position: 'right', fontSize: 9,
                                    fill: 'var(--color-muted-foreground)' }} />
          ))}
          <XAxis dataKey="x" type="number" scale="time" domain={domainX}
                 tickFormatter={(v: number) => format(new Date(v), 'MMM yy')}
                 tick={{ fontSize: 10, fill: 'var(--color-muted-foreground)' }} axisLine={false} tickLine={false} />
          {/* No value ticks: the level lines carry the server's text ("5:00",
              "1.5×BW") and the tooltip each point's — the client formats nothing. */}
          <YAxis domain={domainY} hide />
          <Tooltip content={<PointTooltip />} cursor={{ stroke: 'var(--color-muted-foreground)', strokeWidth: 1 }} />
          <Line type="linear" dataKey="value" stroke={color} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"
                isAnimationActive={false}
                dot={{ r: 4, fill: color, stroke: 'var(--color-card)', strokeWidth: 2 }}
                activeDot={{ r: 6, fill: color, stroke: 'var(--color-card)', strokeWidth: 2 }} />
        </LineChart>
      </ResponsiveContainer>
    </div>
  )
}
