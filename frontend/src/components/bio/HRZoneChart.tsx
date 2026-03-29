import {
  ResponsiveContainer,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  Tooltip,
  Cell,
} from 'recharts'
import type { HRZoneDistribution } from '@/api/types'

interface HRZoneChartProps {
  zones: HRZoneDistribution
  showEstimateLabel?: boolean
}

const ZONE_META = [
  { key: 'z1', label: 'Z1', description: 'Recovery', color: '#94a3b8' },
  { key: 'z2', label: 'Z2', description: 'Aerobic', color: '#38bdf8' },
  { key: 'z3', label: 'Z3', description: 'Tempo', color: '#fbbf24' },
  { key: 'z4', label: 'Z4', description: 'Threshold', color: '#f97316' },
  { key: 'z5', label: 'Z5', description: 'Max', color: '#ef4444' },
] as const

interface TooltipPayload {
  label?: string
  payload?: Array<{ value: number }>
}

function CustomTooltip({ label, payload }: TooltipPayload) {
  const meta = ZONE_META.find((z) => z.label === label)
  if (!payload?.length || !meta) return null
  return (
    <div className="rounded-md border border-border bg-card px-2.5 py-1.5 text-xs shadow-md">
      <p className="font-semibold" style={{ color: meta.color }}>
        {meta.label} — {meta.description}
      </p>
      <p className="text-muted-foreground mt-0.5">{payload[0].value}% of session</p>
    </div>
  )
}

export function HRZoneChart({ zones, showEstimateLabel = true }: HRZoneChartProps) {
  const data = ZONE_META.map((z) => ({
    label: z.label,
    description: z.description,
    value: zones[z.key as keyof HRZoneDistribution] as number,
    color: z.color,
  }))

  return (
    <div className="space-y-1">
      <ResponsiveContainer width="100%" height={100}>
        <BarChart data={data} margin={{ top: 4, right: 4, left: -28, bottom: 0 }}>
          <XAxis
            dataKey="label"
            tick={{ fontSize: 10, fill: 'var(--color-muted-foreground)' }}
            axisLine={false}
            tickLine={false}
          />
          <YAxis
            tick={{ fontSize: 9, fill: 'var(--color-muted-foreground)' }}
            axisLine={false}
            tickLine={false}
            domain={[0, 100]}
          />
          <Tooltip content={<CustomTooltip />} cursor={{ fill: 'transparent' }} />
          <Bar dataKey="value" radius={[3, 3, 0, 0]}>
            {data.map((entry, i) => (
              <Cell key={i} fill={entry.color} />
            ))}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
      {showEstimateLabel && zones.method === 'summary_estimate' && (
        <p className="text-[10px] text-muted-foreground/60 text-center italic">
          Estimated — no sample-level HR data available
        </p>
      )}
    </div>
  )
}
