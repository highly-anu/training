import { useMemo } from 'react'
import {
  ResponsiveContainer,
  AreaChart,
  Area,
  XAxis,
  YAxis,
  Tooltip,
} from 'recharts'
import { parseISO } from 'date-fns'
import type { GPSPoint } from '@/api/types'

interface Props {
  track: GPSPoint[]
}

interface DataPoint {
  elapsed: number // minutes from start
  altitude: number // metres
}

function CustomTooltip({ active, payload }: { active?: boolean; payload?: Array<{ value: number; payload: DataPoint }> }) {
  if (!active || !payload?.length) return null
  const d = payload[0]
  const mins = Math.floor(d.payload.elapsed)
  const secs = Math.round((d.payload.elapsed - mins) * 60)
  return (
    <div className="rounded-md border border-border bg-card px-2.5 py-1.5 text-xs shadow-md">
      <p className="font-semibold text-foreground">{Math.round(d.value)} m</p>
      <p className="text-muted-foreground">{mins}:{secs.toString().padStart(2, '0')}</p>
    </div>
  )
}

export function ElevationChart({ track }: Props) {
  const data = useMemo((): DataPoint[] => {
    const withAlt = track.filter(p => p.altitude != null)
    if (withAlt.length < 2) return []

    const startMs = parseISO(withAlt[0].timestamp).getTime()
    const step = Math.max(1, Math.floor(withAlt.length / 300))
    const points: DataPoint[] = []
    for (let i = 0; i < withAlt.length; i += step) {
      const p = withAlt[i]
      points.push({
        elapsed: (parseISO(p.timestamp).getTime() - startMs) / 60000,
        altitude: p.altitude!,
      })
    }
    return points
  }, [track])

  if (data.length < 2) return null

  const altitudes = data.map(d => d.altitude)
  const yMin = Math.floor(Math.min(...altitudes) - 5)
  const yMax = Math.ceil(Math.max(...altitudes) + 5)
  const maxElapsed = data[data.length - 1].elapsed

  return (
    <ResponsiveContainer width="100%" height={120}>
      <AreaChart data={data} margin={{ top: 4, right: 24, left: -8, bottom: 0 }}>
        <defs>
          <linearGradient id="elevGrad" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="#14b8a6" stopOpacity={0.4} />
            <stop offset="100%" stopColor="#14b8a6" stopOpacity={0.05} />
          </linearGradient>
        </defs>
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
        <Area
          type="monotone"
          dataKey="altitude"
          stroke="#14b8a6"
          strokeWidth={1.5}
          fill="url(#elevGrad)"
          dot={false}
          isAnimationActive={false}
        />
      </AreaChart>
    </ResponsiveContainer>
  )
}
