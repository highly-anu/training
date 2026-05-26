import { useQuery } from '@tanstack/react-query'
import {
  ResponsiveContainer,
  ComposedChart,
  Line,
  Bar,
  Cell,
  XAxis,
  YAxis,
  Tooltip,
  ReferenceLine,
  Legend,
} from 'recharts'
import { parseISO, format } from 'date-fns'
import { fetchPMC } from '@/api/userdata'
import type { PMCEntry } from '@/api/types'

interface TooltipProps {
  active?: boolean
  payload?: Array<{ name: string; value: number; color: string }>
  label?: string
}

function CustomTooltip({ active, payload, label }: TooltipProps) {
  if (!active || !payload?.length) return null
  return (
    <div className="rounded-md border border-border bg-card px-3 py-2 text-xs shadow-md space-y-0.5">
      <p className="font-medium text-muted-foreground">{label}</p>
      {payload.map((p) => (
        <p key={p.name} style={{ color: p.color }}>
          {p.name}: {typeof p.value === 'number' ? p.value.toFixed(1) : p.value}
        </p>
      ))}
    </div>
  )
}

function formatXAxis(dateStr: string): string {
  try {
    return format(parseISO(dateStr), 'MMM d')
  } catch {
    return dateStr
  }
}

export function PMCChart() {
  const { data: raw = [] } = useQuery({
    queryKey: ['pmc'],
    queryFn: fetchPMC,
    staleTime: 10 * 60 * 1000,
  })

  if (raw.length === 0) {
    return (
      <div className="flex h-48 items-center justify-center rounded-lg border border-dashed border-border">
        <p className="text-sm text-muted-foreground">No workout history yet</p>
      </div>
    )
  }

  // Show every 14th label to avoid crowding
  const interval = Math.max(1, Math.floor(raw.length / 6))

  return (
    <div className="space-y-2">
      <div className="grid grid-cols-3 gap-3 text-[11px]">
        <div className="flex items-center gap-1.5 text-muted-foreground">
          <span className="inline-block h-0.5 w-4 rounded-full bg-blue-500" />
          <span>CTL — Fitness (42d)</span>
        </div>
        <div className="flex items-center gap-1.5 text-muted-foreground">
          <span className="inline-block h-0.5 w-4 rounded-full bg-orange-500" />
          <span>ATL — Fatigue (7d)</span>
        </div>
        <div className="flex items-center gap-1.5 text-muted-foreground">
          <span className="inline-block size-2 rounded-sm bg-emerald-500" />
          <span>TSB — Form</span>
        </div>
      </div>

      <ResponsiveContainer width="100%" height={200}>
        <ComposedChart data={raw} margin={{ top: 4, right: 8, left: -20, bottom: 0 }}>
          <XAxis
            dataKey="date"
            tickFormatter={formatXAxis}
            tick={{ fontSize: 9, fill: 'var(--color-muted-foreground)' }}
            axisLine={false}
            tickLine={false}
            interval={interval - 1}
          />
          <YAxis
            tick={{ fontSize: 9, fill: 'var(--color-muted-foreground)' }}
            axisLine={false}
            tickLine={false}
          />
          <Tooltip content={<CustomTooltip />} cursor={{ fill: 'rgba(255,255,255,0.03)' }} />
          <ReferenceLine y={0} stroke="var(--color-border)" strokeOpacity={0.6} />
          <Bar dataKey="tsb" name="TSB" barSize={4} radius={[1, 1, 0, 0]}>
            {raw.map((entry: PMCEntry, i: number) => (
              <Cell key={i} fill={entry.tsb >= 0 ? '#10b981' : '#ef4444'} fillOpacity={0.7} />
            ))}
          </Bar>
          <Line
            type="monotone"
            dataKey="atl"
            name="ATL"
            stroke="#f97316"
            strokeWidth={1.5}
            dot={false}
          />
          <Line
            type="monotone"
            dataKey="ctl"
            name="CTL"
            stroke="#3b82f6"
            strokeWidth={2}
            dot={false}
          />
        </ComposedChart>
      </ResponsiveContainer>

      <p className="text-[10px] text-muted-foreground">
        Positive TSB (green) = fresh · Negative (red) = building fatigue · TSB &lt; −20 = overreached
      </p>
    </div>
  )
}
