import { useMemo } from 'react'
import { format } from 'date-fns'
import {
  ResponsiveContainer, ComposedChart, Line, XAxis, YAxis, Tooltip, Legend, ReferenceArea, ReferenceLine, CartesianGrid,
} from 'recharts'
import type { AnalyticsProgressEntry, ExerciseFinding, ExerciseSeriesSection } from '@/api/types'
import { chartableMeasures, deloadSpans, measureKey, seriesFor, type ChartPoint, type ChartSelection } from '@/lib/progressChart'
import { cn } from '@/lib/utils'

// The one actual/expected pair, everywhere: done emerald, planned indigo dashed.
const DONE = '#10b981'
const PLANNED = '#6366f1'
const HALF_WEEK = 3.5 * 24 * 3600 * 1000

/** 1, 2, 2.5 or 5 × a power of ten, at least `raw`; whole for counts. */
function niceStep(raw: number, whole: boolean): number {
  const mag = 10 ** Math.floor(Math.log10(Math.max(raw, 1e-9)))
  const step = [1, 2, 2.5, 5, 10].map((m) => m * mag).find((s) => s >= raw) ?? 10 * mag
  return whole ? Math.max(1, Math.round(step)) : step
}

interface TooltipProps { active?: boolean; payload?: Array<{ payload: ChartPoint }> }

function PointTooltip({ active, payload, unit, plannedLabel }: TooltipProps & { unit: string; plannedLabel: string }) {
  if (!active || !payload?.length) return null
  const p = payload[0].payload
  const n = (v: number | null) => (v == null ? '—' : `${v}${unit ? ` ${unit}` : ''}`)
  return (
    <div className="max-w-64 rounded-md border border-border bg-card px-3 py-2 text-xs shadow-md space-y-1">
      <p className="font-medium text-muted-foreground">
        {format(new Date(p.t), 'EEE d MMM')}{p.sessionName ? ` · ${p.sessionName}` : ''}{p.isDeload ? ' · deload' : ''}
      </p>
      <p className="text-foreground">
        <span className="text-muted-foreground">{plannedLabel}:</span> <span className="font-semibold tabular-nums">{n(p.planned)}</span>
        {p.prescribedText && <span className="block text-[11px] text-muted-foreground">{p.prescribedText}</span>}
      </p>
      {p.elapsed && (
        <p className="text-foreground">
          <span className="text-muted-foreground">Done:</span> <span className="font-semibold tabular-nums">{p.done == null ? 'not logged' : n(p.done)}</span>
          {p.doneText && <span className="block text-[11px] text-muted-foreground">{p.doneText}</span>}
        </p>
      )}
    </div>
  )
}

/**
 * Every time series of the program on one chart: each exercise's metrics,
 * done against prescribed, and each methodology measure against its
 * expectation. The picker chooses the series, the chips its metric; both live
 * in the URL (`exercise` | `measure`, `metric`) so a measure row or a link can
 * select one.
 */
export function ProgressChart({ section, progress, selection, onSelect, findings }: {
  section: ExerciseSeriesSection | undefined
  progress: AnalyticsProgressEntry[]
  selection: ChartSelection | null
  onSelect: (s: ChartSelection) => void
  findings?: Map<string, ExerciseFinding>
}) {
  const exercises = section?.exercises ?? []
  const measures = useMemo(() => chartableMeasures(section, progress), [section, progress])
  const series = useMemo(() => (selection ? seriesFor(selection, section, progress) : null), [selection, section, progress])
  const today = useMemo(() => new Date(`${format(new Date(), 'yyyy-MM-dd')}T12:00:00`).getTime(), [])

  if (!selection || !series) {
    return (
      <div className="rounded-lg border bg-card p-6 text-center text-sm text-muted-foreground">
        Nothing to chart yet: this program has no exercises with a prescription.
      </div>
    )
  }

  const exercise = selection.kind === 'exercise' ? exercises.find((e) => e.exerciseId === selection.id) : undefined
  const pickerValue = selection.kind === 'exercise' ? `ex:${selection.id}` : `m:${selection.id}`
  const hasDone = series.points.some((p) => p.done != null)
  const hasPlanned = series.points.some((p) => p.planned != null)
  const spans = deloadSpans(series.points)
  // The review's change line is in the exercise's own unit: shown beside that metric only.
  const found = exercise ? findings?.get(exercise.exerciseId) : undefined
  const finding = found && found.unit === series.unit ? found : undefined
  const latest = [...series.points].reverse().find((p) => p.done != null)
  // The axis spans the sessions with something to draw: a lift the method
  // works up on the day has no prescribed kg ahead, and its future sessions
  // were an empty half of the chart.
  const drawn = series.points.filter((p) => p.done != null || p.planned != null)
  const ts = (drawn.length ? drawn : series.points).map((p) => p.t)
  // Counts are whole; and a one-rep change must not fill the height.
  const whole = ['reps', 'sets', 'rounds'].includes(series.unit)
  const values = drawn.flatMap((p) => [p.done, p.planned]).filter((v): v is number => v != null)
  const lo = values.length ? Math.min(...values) : 0
  const hi = values.length ? Math.max(...values) : 1
  const pad = Math.max((hi - lo) * 0.2, Math.abs(hi) * 0.1, whole ? 1 : 0.5)
  // Ticks on round numbers (100, 110, 120 kg), not on the padded edges.
  const step = niceStep((hi - lo + 2 * pad) / 4, whole)
  const yDomain: [number, number] = [Math.max(0, Math.floor((lo - pad) / step) * step), Math.ceil((hi + pad) / step) * step]
  const yTicks = Array.from({ length: Math.round((yDomain[1] - yDomain[0]) / step) + 1 }, (_, i) => yDomain[0] + i * step)

  return (
    <section className="rounded-lg border bg-card p-4 space-y-3" aria-label="Progress chart">
      <div className="flex flex-wrap items-center gap-2">
        <select
          aria-label="Series"
          value={pickerValue}
          onChange={(e) => {
            const [kind, id] = [e.target.value.slice(0, e.target.value.indexOf(':')), e.target.value.slice(e.target.value.indexOf(':') + 1)]
            if (kind === 'ex') {
              const ex = exercises.find((x) => x.exerciseId === id)
              if (ex) onSelect({ kind: 'exercise', id, metric: ex.defaultMetric })
            } else onSelect({ kind: 'measure', id })
          }}
          className="h-8 max-w-full rounded-md border border-border bg-background px-2 text-sm font-medium"
        >
          {exercises.length > 0 && (
            <optgroup label="Exercises">
              {exercises.map((ex) => (
                <option key={ex.exerciseId} value={`ex:${ex.exerciseId}`}>
                  {ex.name}{ex.logged ? ` · ${ex.logged} logged` : ''}
                </option>
              ))}
            </optgroup>
          )}
          {measures.length > 0 && (
            <optgroup label="Measures">
              {measures.map((m) => <option key={measureKey(m)} value={`m:${measureKey(m)}`}>{m.label}</option>)}
            </optgroup>
          )}
        </select>
        {exercise && exercise.metrics.length > 1 && (
          <div className="flex flex-wrap gap-1" role="group" aria-label="Metric">
            {exercise.metrics.map((id) => {
              const m = section?.metrics.find((x) => x.id === id)
              const active = selection.kind === 'exercise' && selection.metric === id
              return (
                <button key={id} type="button" aria-pressed={active}
                  onClick={() => onSelect({ kind: 'exercise', id: exercise.exerciseId, metric: id })}
                  className={cn('px-2 py-0.5 text-[11px] rounded border transition-colors',
                    active ? 'bg-primary/15 border-primary/40 text-primary' : 'border-border text-muted-foreground hover:bg-muted')}>
                  {m?.label ?? id}
                </button>
              )
            })}
          </div>
        )}
      </div>

      <div className="flex flex-wrap items-baseline justify-between gap-2 text-xs">
        <p className="text-muted-foreground">
          {latest
            ? <>Last done <span className="font-semibold text-foreground tabular-nums">{latest.done}{series.unit ? ` ${series.unit}` : ''}</span> on {format(new Date(latest.t), 'd MMM')}{latest.doneText ? ` · ${latest.doneText}` : ''}</>
            : 'Nothing logged yet: the dashed line is the plan.'}
        </p>
        {exercise && <p className="text-muted-foreground tabular-nums">{exercise.logged} of {exercise.scheduled} sessions logged</p>}
      </div>

      {hasDone || hasPlanned ? (
        <ResponsiveContainer width="100%" height={240}>
          <ComposedChart data={drawn} margin={{ top: 8, right: 12, left: -12, bottom: 0 }}>
            <CartesianGrid vertical={false} stroke="var(--color-border)" strokeOpacity={0.5} />
            <XAxis dataKey="t" type="number" scale="time" domain={[Math.min(...ts) - HALF_WEEK / 3, Math.max(...ts) + HALF_WEEK / 3]}
                   tickFormatter={(t: number) => format(new Date(t), 'd MMM')}
                   tick={{ fontSize: 10, fill: 'var(--color-muted-foreground)' }} axisLine={false} tickLine={false} minTickGap={24} />
            <YAxis tick={{ fontSize: 10, fill: 'var(--color-muted-foreground)' }} axisLine={false} tickLine={false}
                   unit={series.unit ? ` ${series.unit}` : ''} domain={yDomain} ticks={yTicks} allowDecimals={!whole}
                   tickFormatter={(v: number) => `${Math.round(v * 10) / 10}`} width={64} />
            {spans.map(([a, b]) => (
              <ReferenceArea key={a} x1={a - HALF_WEEK / 3} x2={b + HALF_WEEK / 3} fill="var(--color-muted-foreground)" fillOpacity={0.08}
                             label={{ value: 'deload', position: 'insideTop', fontSize: 9, fill: 'var(--color-muted-foreground)' }} />
            ))}
            {today >= ts[0] && today <= ts[ts.length - 1] && (
              <ReferenceLine x={today} stroke="var(--color-muted-foreground)" strokeDasharray="2 3"
                             label={{ value: 'today', position: 'insideTopRight', fontSize: 9, fill: 'var(--color-muted-foreground)' }} />
            )}
            <Tooltip content={<PointTooltip unit={series.unit} plannedLabel={series.plannedLabel} />} />
            <Legend iconSize={8} wrapperStyle={{ fontSize: 11 }} />
            {hasPlanned && (
              <Line type="linear" dataKey="planned" name={series.plannedLabel} stroke={PLANNED} strokeWidth={2}
                    strokeDasharray="5 3" dot={false} connectNulls isAnimationActive={false} />
            )}
            <Line type="linear" dataKey="done" name="Done" stroke={DONE} strokeWidth={2} connectNulls isAnimationActive={false}
                  dot={(props: { cx?: number; cy?: number; payload?: ChartPoint }) => props.payload?.done == null
                    ? <g key={`${props.cx}-${props.cy}`} />
                    : <circle key={`${props.cx}-${props.cy}`} cx={props.cx} cy={props.cy} r={4}
                              fill={props.payload?.isDeload ? 'var(--color-card)' : DONE}
                              stroke={props.payload?.isDeload ? DONE : 'var(--color-card)'} strokeWidth={props.payload?.isDeload ? 1.5 : 2} />} />
          </ComposedChart>
        </ResponsiveContainer>
      ) : (
        <p className="py-8 text-center text-xs text-muted-foreground">No values for this metric yet.</p>
      )}

      {finding?.change_summary && <p className="text-[11px] text-muted-foreground">{finding.change_summary}</p>}
    </section>
  )
}
