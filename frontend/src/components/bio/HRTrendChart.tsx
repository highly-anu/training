import { useMemo } from 'react'
import {
  ResponsiveContainer,
  LineChart,
  Line,
  XAxis,
  YAxis,
  Tooltip,
  Legend,
} from 'recharts'
import { subDays, parseISO, isAfter, format } from 'date-fns'
import type { DailyBioLog } from '@/api/types'

interface HRTrendChartProps {
  bioLogs: Record<string, DailyBioLog>
  days?: number
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
      {payload.map((p) => (
        <p key={p.name} style={{ color: p.color }}>
          {p.name}: {p.value}
        </p>
      ))}
    </div>
  )
}

export function HRTrendChart({ bioLogs, days = 30 }: HRTrendChartProps) {
  const data = useMemo(() => {
    const cutoff = subDays(new Date(), days)
    return Object.values(bioLogs)
      .filter((l) => isAfter(parseISO(l.date), cutoff))
      .sort((a, b) => a.date.localeCompare(b.date))
      .map((l) => ({
        date: format(parseISO(l.date), 'MMM d'),
        'Resting HR': l.restingHR,
        HRV: l.hrv,
      }))
  }, [bioLogs, days])

  if (data.length === 0) {
    return (
      <div className="flex h-40 items-center justify-center rounded-lg border border-dashed border-border">
        <p className="text-sm text-muted-foreground">No check-in data yet</p>
      </div>
    )
  }

  const hasRHR = data.some((d) => d['Resting HR'] != null)
  const hasHRV = data.some((d) => d.HRV != null)

  return (
    <ResponsiveContainer width="100%" height={180}>
      <LineChart data={data} margin={{ top: 4, right: 8, left: -20, bottom: 0 }}>
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
        />
        <Tooltip content={<CustomTooltip />} />
        <Legend iconSize={8} wrapperStyle={{ fontSize: 10 }} />
        {hasRHR && (
          <Line
            type="monotone"
            dataKey="Resting HR"
            stroke="#ef4444"
            strokeWidth={1.5}
            dot={false}
            connectNulls
          />
        )}
        {hasHRV && (
          <Line
            type="monotone"
            dataKey="HRV"
            stroke="#38bdf8"
            strokeWidth={1.5}
            dot={false}
            connectNulls
          />
        )}
      </LineChart>
    </ResponsiveContainer>
  )
}
