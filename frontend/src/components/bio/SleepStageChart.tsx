import { useMemo } from 'react'
import {
  ResponsiveContainer,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  Tooltip,
  Legend,
} from 'recharts'
import { subDays, parseISO, isAfter, format } from 'date-fns'
import type { DailyBioLog } from '@/api/types'

interface SleepStageChartProps {
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
  const total = payload.reduce((sum, p) => sum + (p.value ?? 0), 0)
  return (
    <div className="rounded-md border border-border bg-card px-3 py-2 text-xs shadow-md space-y-1">
      <p className="font-medium text-muted-foreground">{label}</p>
      {payload.map((p) =>
        p.value > 0 ? (
          <p key={p.name} style={{ color: p.color }}>
            {p.name}: {Math.round(p.value)}m
          </p>
        ) : null
      )}
      {total > 0 && (
        <p className="text-muted-foreground border-t border-border pt-1 mt-1">
          Total: {Math.floor(total / 60)}h {Math.round(total % 60)}m
        </p>
      )}
    </div>
  )
}

export function SleepStageChart({ bioLogs, days = 30 }: SleepStageChartProps) {
  const data = useMemo(() => {
    const cutoff = subDays(new Date(), days)
    return Object.values(bioLogs)
      .filter(
        (l) =>
          isAfter(parseISO(l.date), cutoff) &&
          l.sleepDurationMin != null
      )
      .sort((a, b) => a.date.localeCompare(b.date))
      .map((l) => ({
        date: format(parseISO(l.date), 'MMM d'),
        Deep: l.deepSleepMin ?? 0,
        REM: l.remSleepMin ?? 0,
        Light: l.lightSleepMin ?? 0,
        Awake: l.awakeMins ?? 0,
      }))
  }, [bioLogs, days])

  if (data.length === 0) {
    return (
      <div className="flex h-40 items-center justify-center rounded-lg border border-dashed border-border">
        <p className="text-sm text-muted-foreground">
          No sleep data yet — sync via the iOS app
        </p>
      </div>
    )
  }

  return (
    <ResponsiveContainer width="100%" height={200}>
      <BarChart data={data} margin={{ top: 4, right: 8, left: -20, bottom: 0 }} barSize={10}>
        <XAxis
          dataKey="date"
          tick={{ fontSize: 10, fill: 'var(--color-muted-foreground)' }}
          axisLine={false}
          tickLine={false}
          interval="preserveStartEnd"
        />
        <YAxis
          tickFormatter={(v) => `${Math.floor(v / 60)}h`}
          tick={{ fontSize: 9, fill: 'var(--color-muted-foreground)' }}
          axisLine={false}
          tickLine={false}
        />
        <Tooltip content={<CustomTooltip />} />
        <Legend iconSize={8} wrapperStyle={{ fontSize: 10 }} />
        <Bar dataKey="Deep" stackId="sleep" fill="#1d4ed8" radius={[0, 0, 0, 0]} />
        <Bar dataKey="REM" stackId="sleep" fill="#7c3aed" radius={[0, 0, 0, 0]} />
        <Bar dataKey="Light" stackId="sleep" fill="#38bdf8" radius={[0, 0, 0, 0]} />
        <Bar dataKey="Awake" stackId="sleep" fill="#6b7280" radius={[4, 4, 0, 0]} />
      </BarChart>
    </ResponsiveContainer>
  )
}
