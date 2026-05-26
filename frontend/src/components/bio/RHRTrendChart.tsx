import { useMemo } from 'react'
import {
  ResponsiveContainer,
  ComposedChart,
  Line,
  XAxis,
  YAxis,
  Tooltip,
  ReferenceArea,
} from 'recharts'
import { subDays, parseISO, isAfter, format } from 'date-fns'
import type { DailyBioLog } from '@/api/types'

interface Props {
  bioLogs: Record<string, DailyBioLog>
  days?: number
}

interface DataPoint {
  date: string
  rhr: number | null
  rolling: number | null
}

interface TooltipProps {
  active?: boolean
  payload?: Array<{ name: string; value: number; color: string }>
  label?: string
}

function CustomTooltip({ active, payload, label }: TooltipProps) {
  if (!active || !payload?.length) return null
  return (
    <div className="rounded-md border border-border bg-card px-3 py-2 text-xs shadow-md space-y-1">
      <p className="font-medium text-muted-foreground">{label}</p>
      {payload.map((p) =>
        p.value != null ? (
          <p key={p.name} style={{ color: p.color }}>
            {p.name}: {Math.round(p.value)} bpm
          </p>
        ) : null
      )}
    </div>
  )
}

function rollingMean(values: (number | null)[], windowSize: number, index: number): number | null {
  const window: number[] = []
  for (let i = Math.max(0, index - windowSize + 1); i <= index; i++) {
    const v = values[i]
    if (v != null) window.push(v)
  }
  if (window.length < 3) return null
  return window.reduce((s, v) => s + v, 0) / window.length
}

export function RHRTrendChart({ bioLogs, days = 30 }: Props) {
  const { data, trend, baseline } = useMemo(() => {
    const cutoff = subDays(new Date(), days)
    const sorted = Object.values(bioLogs)
      .filter((l) => l.restingHR != null && isAfter(parseISO(l.date), cutoff))
      .sort((a, b) => a.date.localeCompare(b.date))

    const rawValues = sorted.map((l) => l.restingHR ?? null)
    const points: DataPoint[] = sorted.map((l, i) => ({
      date: format(parseISO(l.date), 'MMM d'),
      rhr: l.restingHR ?? null,
      rolling: rollingMean(rawValues, 7, i),
    }))

    // Trend: compare mean of last 5 vs prior 5 data points with valid RHR
    const valid = sorted.map((l) => l.restingHR).filter((v): v is number => v != null)
    const last5 = valid.slice(-5)
    const prior5 = valid.slice(-10, -5)
    let trendDir: 'rising' | 'stable' | 'falling' = 'stable'
    if (last5.length >= 3 && prior5.length >= 3) {
      const lastMean = last5.reduce((s, v) => s + v, 0) / last5.length
      const priorMean = prior5.reduce((s, v) => s + v, 0) / prior5.length
      if (lastMean > priorMean + 2) trendDir = 'rising'
      else if (lastMean < priorMean - 2) trendDir = 'falling'
    }

    const rollingValues = points.map((p) => p.rolling).filter((v): v is number => v != null)
    const avg = rollingValues.length
      ? rollingValues.reduce((s, v) => s + v, 0) / rollingValues.length
      : null

    return { data: points, trend: trendDir, baseline: avg }
  }, [bioLogs, days])

  if (data.length === 0) {
    return (
      <div className="flex h-40 items-center justify-center rounded-lg border border-dashed border-border">
        <p className="text-sm text-muted-foreground">No resting HR data yet</p>
      </div>
    )
  }

  const bandColor =
    trend === 'falling' ? '#10b981' : trend === 'rising' ? '#ef4444' : '#f59e0b'
  const hasRolling = data.some((d) => d.rolling != null)

  return (
    <div className="space-y-1">
      <div className="flex items-center gap-2 text-[11px] text-muted-foreground">
        <span className={`font-medium ${
          trend === 'falling' ? 'text-emerald-400' :
          trend === 'rising'  ? 'text-red-400'     : 'text-amber-400'
        }`}>
          {trend === 'falling' ? 'Trending down' :
           trend === 'rising'  ? 'Trending up'   : 'Stable'}
        </span>
        <span>· 7-day rolling average</span>
      </div>
      <ResponsiveContainer width="100%" height={160}>
        <ComposedChart data={data} margin={{ top: 4, right: 8, left: -20, bottom: 0 }}>
          <XAxis
            dataKey="date"
            tick={{ fontSize: 10, fill: 'var(--color-muted-foreground)' }}
            axisLine={false}
            tickLine={false}
            interval="preserveStartEnd"
          />
          <YAxis
            tick={{ fontSize: 9, fill: 'var(--color-muted-foreground)' }}
            axisLine={false}
            tickLine={false}
            domain={['auto', 'auto']}
          />
          <Tooltip content={<CustomTooltip />} />
          {baseline != null && (
            <ReferenceArea
              y1={baseline - 5}
              y2={baseline + 5}
              fill={bandColor}
              fillOpacity={0.08}
              strokeOpacity={0}
            />
          )}
          <Line
            type="monotone"
            dataKey="rhr"
            name="Resting HR"
            stroke="#ef4444"
            strokeWidth={1}
            dot={{ r: 2, fill: '#ef4444', strokeWidth: 0 }}
            connectNulls
            opacity={0.5}
          />
          {hasRolling && (
            <Line
              type="monotone"
              dataKey="rolling"
              name="7-day avg"
              stroke="#ef4444"
              strokeWidth={2}
              dot={false}
              connectNulls
            />
          )}
        </ComposedChart>
      </ResponsiveContainer>
    </div>
  )
}
