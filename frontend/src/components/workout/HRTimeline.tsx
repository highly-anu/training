import { useMemo, useState } from 'react'
import {
  ResponsiveContainer,
  AreaChart,
  Area,
  XAxis,
  YAxis,
  Tooltip,
  ReferenceLine,
  ReferenceArea,
} from 'recharts'
import { parseISO } from 'date-fns'
import type { HRSample } from '@/api/types'

interface HRTimelineProps {
  samples: HRSample[]
  avgHR?: number | null
  maxHR?: number
}

interface DataPoint {
  elapsed: number // minutes from start
  bpm: number
}

// Zone boundaries as fractions of maxHR (upper bounds)
// Z1: <60%, Z2: 60-70%, Z3: 70-80%, Z4: 80-90%, Z5: 90%+
const ZONE_THRESHOLDS = [0.60, 0.70, 0.80, 0.90]

// Must match HRZoneChart ZONE_META colors
const ZONE_COLORS = [
  '#94a3b8', // Z1 — slate (Recovery)
  '#38bdf8', // Z2 — sky blue (Aerobic)
  '#fbbf24', // Z3 — amber (Tempo)
  '#f97316', // Z4 — orange (Threshold)
  '#ef4444', // Z5 — red (Max)
]

const ZONE_BG = [
  'rgba(148,163,184,0.06)', // Z1
  'rgba(56,189,248,0.06)',  // Z2
  'rgba(251,191,36,0.06)',  // Z3
  'rgba(249,115,22,0.06)',  // Z4
  'rgba(239,68,68,0.06)',   // Z5
]

function zoneForBpm(bpm: number, maxHR: number): number {
  const pct = bpm / maxHR
  for (let i = 0; i < ZONE_THRESHOLDS.length; i++) {
    if (pct < ZONE_THRESHOLDS[i]) return i
  }
  return 4
}

function CustomTooltip({ active, payload }: { active?: boolean; payload?: Array<{ value: number; payload: DataPoint }> }) {
  if (!active || !payload?.length) return null
  const d = payload[0]
  const mins = Math.floor(d.payload.elapsed)
  const secs = Math.round((d.payload.elapsed - mins) * 60)
  return (
    <div className="rounded-md border border-border bg-card px-2.5 py-1.5 text-xs shadow-md">
      <p className="font-semibold text-foreground">{d.value} bpm</p>
      <p className="text-muted-foreground">{mins}:{secs.toString().padStart(2, '0')}</p>
    </div>
  )
}

let instanceCounter = 0

export function HRTimeline({ samples, avgHR, maxHR = 190 }: HRTimelineProps) {
  const [gradientId] = useState(() => `hrZone-${++instanceCounter}`)

  const data = useMemo(() => {
    if (samples.length === 0) return []
    const startMs = parseISO(samples[0].timestamp).getTime()

    // Filter bad data and downsample to ~300 points max for performance
    const valid = samples.filter((s) => s.bpm > 0)
    if (valid.length === 0) return []

    const step = Math.max(1, Math.floor(valid.length / 300))
    const points: DataPoint[] = []
    for (let i = 0; i < valid.length; i += step) {
      const s = valid[i]
      points.push({
        elapsed: (parseISO(s.timestamp).getTime() - startMs) / 60000,
        bpm: s.bpm,
      })
    }
    return points
  }, [samples])

  // Compute avg from displayed data (more accurate than session summary)
  const computedAvg = useMemo(() => {
    if (data.length === 0) return avgHR ?? null
    const sum = data.reduce((s, d) => s + d.bpm, 0)
    return Math.round(sum / data.length)
  }, [data, avgHR])

  // Build a vertical linearGradient that maps bpm values to zone colors
  const { gradientStops, yMin, yMax } = useMemo(() => {
    if (data.length === 0) return { gradientStops: [], yMin: 60, yMax: 200 }
    const bpms = data.map((d) => d.bpm)
    const min = Math.min(...bpms) - 10
    const max = Math.max(...bpms) + 10

    // Zone boundaries in bpm
    const boundaries = ZONE_THRESHOLDS.map((t) => t * maxHR)

    // Build gradient stops from top (high bpm) to bottom (low bpm)
    // In SVG y1=0 is top (high bpm), y2=1 is bottom (low bpm)
    const range = max - min
    const stops: { offset: string; color: string }[] = []

    // For each zone boundary, add two stops (one for each side of the boundary)
    // to create sharp color transitions
    const allBoundaries = [min, ...boundaries.filter((b) => b > min && b < max), max]

    for (let i = allBoundaries.length - 1; i >= 0; i--) {
      const bpm = allBoundaries[i]
      const offset = 1 - (bpm - min) / range // flip: top=0, bottom=1
      const zone = zoneForBpm(bpm, maxHR)
      const belowZone = i > 0 ? zoneForBpm(allBoundaries[i] - 0.1, maxHR) : zone

      if (i === allBoundaries.length - 1) {
        stops.push({ offset: `${(offset * 100).toFixed(1)}%`, color: ZONE_COLORS[zone] })
      } else if (i === 0) {
        stops.push({ offset: `${(offset * 100).toFixed(1)}%`, color: ZONE_COLORS[belowZone] })
      } else {
        // Sharp transition: end previous zone color, start new zone color
        stops.push({ offset: `${(offset * 100).toFixed(1)}%`, color: ZONE_COLORS[zone] })
        stops.push({ offset: `${(offset * 100).toFixed(1)}%`, color: ZONE_COLORS[belowZone] })
      }
    }

    return { gradientStops: stops, yMin: min, yMax: max }
  }, [data, maxHR])

  if (data.length === 0) return null

  const maxElapsed = data[data.length - 1].elapsed

  // Zone boundaries that fall within the visible range
  const visibleZoneBounds = ZONE_THRESHOLDS
    .map((t) => Math.round(t * maxHR))
    .filter((b) => b > yMin && b < yMax)

  // Zone reference areas
  const zoneBands: { y1: number; y2: number; zone: number }[] = []
  const allBounds = [yMin, ...visibleZoneBounds, yMax]
  for (let i = 0; i < allBounds.length - 1; i++) {
    zoneBands.push({
      y1: allBounds[i],
      y2: allBounds[i + 1],
      zone: zoneForBpm((allBounds[i] + allBounds[i + 1]) / 2, maxHR),
    })
  }

  return (
    <div className="space-y-1">
      <ResponsiveContainer width="100%" height={160}>
        <AreaChart data={data} margin={{ top: 4, right: 24, left: -8, bottom: 0 }}>
          <defs>
            <linearGradient id={`${gradientId}-stroke`} x1="0" y1="0" x2="0" y2="1">
              {gradientStops.map((s, i) => (
                <stop key={i} offset={s.offset} stopColor={s.color} />
              ))}
            </linearGradient>
            <linearGradient id={`${gradientId}-fill`} x1="0" y1="0" x2="0" y2="1">
              {gradientStops.map((s, i) => (
                <stop key={i} offset={s.offset} stopColor={s.color} stopOpacity={0.15} />
              ))}
            </linearGradient>
          </defs>

          {/* Zone background bands */}
          {zoneBands.map((band) => (
            <ReferenceArea
              key={band.zone}
              y1={band.y1}
              y2={band.y2}
              fill={ZONE_BG[band.zone]}
              fillOpacity={1}
              ifOverflow="hidden"
            />
          ))}

          {/* Zone boundary lines with labels */}
          {visibleZoneBounds.map((bpm) => {
            const zone = zoneForBpm(bpm + 0.1, maxHR) + 1
            return (
              <ReferenceLine
                key={bpm}
                y={bpm}
                stroke={ZONE_COLORS[zone - 1] ?? 'var(--color-border)'}
                strokeDasharray="2 3"
                strokeWidth={0.5}
                label={{
                  value: `Z${zone}`,
                  position: 'right',
                  fill: ZONE_COLORS[zone - 1] ?? 'var(--color-muted-foreground)',
                  fontSize: 9,
                  fontWeight: 600,
                }}
              />
            )
          })}

          <XAxis
            dataKey="elapsed"
            tick={{ fontSize: 10, fill: 'var(--color-muted-foreground)' }}
            axisLine={false}
            tickLine={false}
            tickFormatter={(v: number) => `${Math.round(v)}m`}
            domain={[0, maxElapsed]}
          />
          <YAxis
            tick={{ fontSize: 10, fill: 'var(--color-muted-foreground)' }}
            axisLine={false}
            tickLine={false}
            domain={[yMin, yMax]}
            tickFormatter={(v: number) => `${Math.round(v)}`}
          />
          <Tooltip content={<CustomTooltip />} />
          {computedAvg != null && (
            <ReferenceLine
              y={computedAvg}
              stroke="#f97316"
              strokeDasharray="4 4"
              strokeWidth={1}
            />
          )}
          <Area
            type="monotone"
            dataKey="bpm"
            stroke={`url(#${gradientId}-stroke)`}
            fill={`url(#${gradientId}-fill)`}
            strokeWidth={1.5}
            dot={false}
            isAnimationActive={false}
          />
        </AreaChart>
      </ResponsiveContainer>
      {computedAvg != null && (
        <p className="text-[10px] text-muted-foreground/60 text-right">
          <span className="inline-block w-3 h-px bg-orange-400 align-middle mr-1" style={{ borderTop: '1px dashed #f97316' }} />
          avg {computedAvg} bpm
        </p>
      )}
    </div>
  )
}
