import { useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import {
  ResponsiveContainer,
  BarChart,
  Bar,
  Cell,
  XAxis,
  YAxis,
  Tooltip,
  ReferenceLine,
} from 'recharts'
import { startOfISOWeek, format, addDays } from 'date-fns'
import { fetchWeeklyLoad } from '@/api/userdata'
import type { WeeklyLoad } from '@/api/types'

interface TooltipProps {
  active?: boolean
  payload?: Array<{ value: number; payload: WeeklyLoad & { label: string } }>
  label?: string
}

function CustomTooltip({ active, payload }: TooltipProps) {
  if (!active || !payload?.length) return null
  const d = payload[0].payload
  return (
    <div className="rounded-md border border-border bg-card px-3 py-2 text-xs shadow-md space-y-0.5">
      <p className="font-medium text-muted-foreground">{d.label}</p>
      <p className="text-foreground">TRIMP: <span className="font-semibold">{d.trimp}</span></p>
      <p className="text-muted-foreground">{d.sessions} session{d.sessions !== 1 ? 's' : ''}</p>
    </div>
  )
}

function weekLabel(isoWeek: string): string {
  try {
    const [year, w] = isoWeek.split('-W')
    const jan4 = new Date(parseInt(year), 0, 4)
    const startOfYear = startOfISOWeek(jan4)
    const weekStart = addDays(startOfYear, (parseInt(w) - 1) * 7)
    const weekEnd = addDays(weekStart, 6)
    if (weekStart.getMonth() === weekEnd.getMonth()) {
      return format(weekStart, 'MMM d')
    }
    return format(weekStart, 'MMM d')
  } catch {
    return isoWeek
  }
}

function barColor(trimp: number, median: number): string {
  if (median === 0) return '#38bdf8'
  const ratio = trimp / median
  if (ratio < 0.75) return '#10b981'   // light week — emerald
  if (ratio < 1.25) return '#38bdf8'   // normal — sky
  if (ratio < 1.5)  return '#f59e0b'   // heavy — amber
  return '#ef4444'                      // overload — red
}

export function WeeklyLoadChart() {
  const { data: raw = [] } = useQuery({
    queryKey: ['weeklyLoad'],
    queryFn: fetchWeeklyLoad,
    staleTime: 10 * 60 * 1000,
  })

  const { data, median } = useMemo(() => {
    if (!raw.length) return { data: [], median: 0 }
    const sorted = [...raw].map((d) => ({ ...d, label: weekLabel(d.week) }))
    const trimpValues = sorted.map((d) => d.trimp).sort((a, b) => a - b)
    const mid = Math.floor(trimpValues.length / 2)
    const med =
      trimpValues.length % 2 === 0
        ? (trimpValues[mid - 1] + trimpValues[mid]) / 2
        : trimpValues[mid]
    return { data: sorted, median: med }
  }, [raw])

  if (data.length === 0) {
    return (
      <div className="flex h-40 items-center justify-center rounded-lg border border-dashed border-border">
        <p className="text-sm text-muted-foreground">No workout data yet</p>
      </div>
    )
  }

  return (
    <div className="space-y-1">
      <div className="flex items-center gap-3 text-[11px] text-muted-foreground">
        <span className="flex items-center gap-1"><span className="inline-block size-2 rounded-sm bg-emerald-500" /> Light</span>
        <span className="flex items-center gap-1"><span className="inline-block size-2 rounded-sm bg-sky-400" /> Normal</span>
        <span className="flex items-center gap-1"><span className="inline-block size-2 rounded-sm bg-amber-400" /> Heavy</span>
        <span className="flex items-center gap-1"><span className="inline-block size-2 rounded-sm bg-red-500" /> Overload</span>
      </div>
      <ResponsiveContainer width="100%" height={160}>
        <BarChart data={data} margin={{ top: 4, right: 8, left: -20, bottom: 0 }}>
          <XAxis
            dataKey="label"
            tick={{ fontSize: 9, fill: 'var(--color-muted-foreground)' }}
            axisLine={false}
            tickLine={false}
            interval={Math.floor(data.length / 6)}
          />
          <YAxis
            tick={{ fontSize: 9, fill: 'var(--color-muted-foreground)' }}
            axisLine={false}
            tickLine={false}
          />
          <Tooltip content={<CustomTooltip />} cursor={{ fill: 'rgba(255,255,255,0.04)' }} />
          {median > 0 && (
            <ReferenceLine
              y={median}
              stroke="var(--color-muted-foreground)"
              strokeDasharray="3 3"
              strokeOpacity={0.4}
            />
          )}
          <Bar dataKey="trimp" radius={[2, 2, 0, 0]}>
            {data.map((entry, i) => (
              <Cell key={i} fill={barColor(entry.trimp, median)} />
            ))}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </div>
  )
}
