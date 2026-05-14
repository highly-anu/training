import { useMemo, useState } from 'react'
import {
  ResponsiveContainer,
  LineChart,
  Line,
  XAxis,
  YAxis,
  Tooltip,
  Legend,
  ReferenceLine,
} from 'recharts'
import type { ExerciseHistoryItem } from '@/api/types'

interface TooltipProps {
  active?: boolean
  payload?: Array<{ name: string; value: number | null; color: string }>
  label?: string
}

function CustomTooltip({ active, payload, label }: TooltipProps) {
  if (!active || !payload?.length) return null
  return (
    <div className="rounded-md border border-border bg-card px-3 py-2 text-xs shadow-md space-y-1">
      <p className="font-medium text-muted-foreground">Wk {label}</p>
      {payload.map((p) =>
        p.value != null ? (
          <p key={p.name} style={{ color: p.color }}>
            {p.name}: {p.value}
          </p>
        ) : null,
      )}
    </div>
  )
}

interface ExerciseTrendChartProps {
  exercises: ExerciseHistoryItem[]
}

export function ExerciseTrendChart({ exercises }: ExerciseTrendChartProps) {
  const [selectedId, setSelectedId] = useState<string>(exercises[0]?.exerciseId ?? '')

  const exercise = exercises.find((e) => e.exerciseId === selectedId) ?? exercises[0]

  const { chartData, unit, currentExpected } = useMemo(() => {
    if (!exercise) return { chartData: [], unit: '', currentExpected: null }

    const metricType = exercise.expected[0]?.metric_type ?? 'weight'
    const unit       = exercise.expected[0]?.unit ?? ''

    const actualByWeek = new Map<number, number>()
    for (const pt of exercise.history) {
      const val =
        metricType === 'weight'   ? pt.best_weight_kg :
        metricType === 'time'     ? (pt.duration_sec != null ? +(pt.duration_sec / 60).toFixed(1) : null) :
        metricType === 'distance' ? pt.distance_km :
        metricType === 'rounds'   ? pt.rounds_completed :
        metricType === 'reps'     ? pt.best_reps :
        pt.best_weight_kg
      if (val != null) actualByWeek.set(pt.week_number, val)
    }

    const allWeeks = Array.from(
      new Set([
        ...exercise.expected.map((e) => e.week_number),
        ...exercise.history.map((h) => h.week_number),
      ]),
    ).sort((a, b) => a - b)

    const chartData = allWeeks.map((wn) => ({
      week:     wn,
      Actual:   actualByWeek.get(wn) ?? null,
      Expected: exercise.expected.find((e) => e.week_number === wn)?.expected_value ?? null,
    }))

    const lastActualWeek = Math.max(...[...actualByWeek.keys()], 0)
    const currentExpected =
      exercise.expected.find((e) => e.week_number === lastActualWeek)?.expected_value ?? null

    return { chartData, unit, currentExpected }
  }, [exercise])

  if (!exercise || chartData.length === 0) {
    return (
      <div className="flex h-40 items-center justify-center rounded-lg border border-dashed border-border">
        <p className="text-sm text-muted-foreground">No exercise data yet</p>
      </div>
    )
  }

  const hasActual   = chartData.some((d) => d.Actual   != null)
  const hasExpected = chartData.some((d) => d.Expected != null)

  return (
    <div className="space-y-2">
      {/* Exercise picker */}
      {exercises.length > 1 && (
        <div className="flex flex-wrap gap-1">
          {exercises.map((ex) => (
            <button
              key={ex.exerciseId}
              type="button"
              onClick={() => setSelectedId(ex.exerciseId)}
              className={[
                'px-2 py-0.5 text-[10px] rounded border transition-colors',
                ex.exerciseId === selectedId
                  ? 'bg-primary/15 border-primary/40 text-primary'
                  : 'border-border text-muted-foreground hover:bg-muted',
              ].join(' ')}
            >
              {ex.name}
            </button>
          ))}
        </div>
      )}

      <p className="text-xs font-medium">{exercise.name}</p>

      <ResponsiveContainer width="100%" height={180}>
        <LineChart data={chartData} margin={{ top: 4, right: 8, left: -20, bottom: 0 }}>
          <XAxis
            dataKey="week"
            tick={{ fontSize: 10, fill: 'var(--color-muted-foreground)' }}
            tickFormatter={(v) => `W${v}`}
            axisLine={false}
            tickLine={false}
          />
          <YAxis
            tick={{ fontSize: 9, fill: 'var(--color-muted-foreground)' }}
            axisLine={false}
            tickLine={false}
            unit={` ${unit}`}
          />
          <Tooltip content={<CustomTooltip />} />
          <Legend iconSize={8} wrapperStyle={{ fontSize: 10 }} />
          {currentExpected != null && (
            <ReferenceLine
              y={currentExpected}
              stroke="#6366f1"
              strokeDasharray="4 2"
              strokeOpacity={0.5}
              label={{ value: `target ${currentExpected}${unit}`, fontSize: 9, fill: '#6366f1' }}
            />
          )}
          {hasActual && (
            <Line
              type="monotone"
              dataKey="Actual"
              stroke="#10b981"
              strokeWidth={2}
              dot={{ r: 3, fill: '#10b981' }}
              connectNulls
            />
          )}
          {hasExpected && (
            <Line
              type="monotone"
              dataKey="Expected"
              stroke="#6366f1"
              strokeWidth={1.5}
              strokeDasharray="5 3"
              dot={false}
              connectNulls
            />
          )}
        </LineChart>
      </ResponsiveContainer>
    </div>
  )
}
