import { useMemo, useState } from 'react'
import { ResponsiveContainer, LineChart, Line, XAxis, YAxis, Tooltip, Legend } from 'recharts'
import type { AnalyticsProgressEntry, AnalyticsExerciseResult } from '@/api/types'
import { StandardLadder, StandardLevelBadge } from '@/components/standards/StandardLadder'
import { thresholdTexts } from '@/lib/standards'
import { cn } from '@/lib/utils'
import { StatusBadge } from './StatusBadge'
import { CoverageNotice } from './CoverageNotice'

// The one actual/expected pair, everywhere: actual emerald, expected indigo dashed.
const ACTUAL = '#10b981'
const EXPECTED = '#6366f1'

interface TooltipProps { active?: boolean; payload?: Array<{ name: string; value: number | null; color: string; payload: Record<string, unknown> }>; label?: string }

function PointTooltip({ active, payload, label }: TooltipProps) {
  if (!active || !payload?.length) return null
  const p = payload[0].payload as { isDeload?: boolean; date?: string; reps?: number; est1rm?: number }
  return (
    <div className="rounded-md border border-border bg-card px-3 py-2 text-xs shadow-md space-y-0.5">
      <p className="font-medium text-muted-foreground">{p.date ?? `#${label}`}{p.isDeload ? ' · deload' : ''}</p>
      {payload.map((s) => s.value != null && (
        <p key={s.name} className="text-foreground">{s.name}: <span className="font-semibold">{s.value}</span></p>
      ))}
      {p.reps != null && <p className="text-muted-foreground">× {p.reps} reps{p.est1rm ? ` · est 1RM ${p.est1rm}` : ''}</p>}
    </div>
  )
}

function SeriesChart({ series, expected, unit }: {
  series: AnalyticsProgressEntry['series']; expected: AnalyticsProgressEntry['expected']; unit: string
}) {
  const data = useMemo(() => {
    const byX = new Map<number, Record<string, unknown>>()
    for (const p of series) byX.set(p.x, { ...p, Actual: p.value })
    for (const e of expected) byX.set(e.x, { ...(byX.get(e.x) ?? { x: e.x }), Expected: e.value })
    return [...byX.values()].sort((a, b) => (a.x as number) - (b.x as number))
  }, [series, expected])
  if (data.length === 0) return null
  const hasExpected = expected.some((e) => e.value != null)
  return (
    <ResponsiveContainer width="100%" height={160}>
      <LineChart data={data} margin={{ top: 4, right: 8, left: -20, bottom: 0 }}>
        <XAxis dataKey="x" tick={{ fontSize: 9, fill: 'var(--color-muted-foreground)' }} axisLine={false} tickLine={false} />
        <YAxis tick={{ fontSize: 9, fill: 'var(--color-muted-foreground)' }} axisLine={false} tickLine={false} unit={` ${unit}`} domain={['auto', 'auto']} />
        <Tooltip content={<PointTooltip />} />
        {hasExpected && <Legend iconSize={8} wrapperStyle={{ fontSize: 10 }} />}
        <Line type="monotone" dataKey="Actual" stroke={ACTUAL} strokeWidth={2} connectNulls
              dot={(props: { cx?: number; cy?: number; payload?: { isDeload?: boolean } }) => (
                <circle key={`${props.cx}-${props.cy}`} cx={props.cx} cy={props.cy} r={4}
                        fill={props.payload?.isDeload ? 'var(--color-card)' : ACTUAL}
                        stroke={ACTUAL} strokeWidth={props.payload?.isDeload ? 1.5 : 0} />
              )} />
        {hasExpected && <Line type="monotone" dataKey="Expected" stroke={EXPECTED} strokeWidth={1.5} strokeDasharray="5 3" dot={false} connectNulls />}
      </LineChart>
    </ResponsiveContainer>
  )
}

function ExercisePicker({ exercises, selected, onSelect }: {
  exercises: AnalyticsExerciseResult[]; selected: string; onSelect: (id: string) => void
}) {
  if (exercises.length < 2) return null
  return (
    <div className="flex flex-wrap gap-1">
      {exercises.map((ex) => (
        <button key={ex.exerciseId} type="button" onClick={() => onSelect(ex.exerciseId)}
          className={cn('px-2 py-0.5 text-[10px] rounded border transition-colors',
            ex.exerciseId === selected ? 'bg-primary/15 border-primary/40 text-primary' : 'border-border text-muted-foreground hover:bg-muted')}>
          {ex.name}{ex.series.length ? ` · ${ex.series.length}` : ''}
        </button>
      ))}
    </div>
  )
}

function Unlocks({ entry }: { entry: AnalyticsProgressEntry }) {
  const practised = entry.practised ?? []
  const available = entry.available ?? []
  const total = entry.programTotal
  // Practice opens nothing the athlete's level had not already opened (all of
  // Wildman's library, all of Starting Strength's): say so, not an empty list.
  const levelOpensAll = !available.length && !entry.lockedCount && (entry.assumedCount ?? 0) > 0
  return (
    <div className="grid gap-3 sm:grid-cols-2 text-xs">
      <div>
        <p className="font-semibold text-foreground">
          Practised ({practised.length}{total ? ` of ${total} in this program` : ''})
        </p>
        <ul className="mt-1 space-y-0.5 text-muted-foreground">
          {practised.slice(0, 8).map((p) => <li key={p.exerciseId}>{p.name} <span className="text-[10px]">· {p.sessions}×</span></li>)}
        </ul>
      </div>
      <div>
        <p className="font-semibold text-foreground">Now available ({available.length})</p>
        {levelOpensAll ? (
          <p className="mt-1 text-muted-foreground">Your level already opens every movement in this library.</p>
        ) : (
          <ul className="mt-1 space-y-0.5 text-muted-foreground">
            {available.slice(0, 8).map((a) => <li key={a.exerciseId}>{a.name}</li>)}
          </ul>
        )}
      </div>
    </div>
  )
}

function Benchmarks({ entry }: { entry: AnalyticsProgressEntry }) {
  const rows = (entry.benchmarks ?? []) as Array<{
    benchmarkId: string; name?: string; unit?: string; domain?: string | null; latest?: number | null; latestText?: string | null
    level?: string | null; levelIndex?: number; standards?: Record<string, number>; standardsText?: Record<string, string>
    target?: string; targetText?: string | null; met?: boolean | null; missing?: boolean
  }>
  return (
    <div className="space-y-3">
      {rows.filter((r) => !r.missing).map((r) => (
        <div key={r.benchmarkId} className="space-y-1">
          <div className="flex items-center justify-between gap-2 text-xs">
            <span className="font-medium">{r.name}</span>
            <span className="text-muted-foreground">
              {r.latest != null
                ? <><span className="font-semibold text-foreground tabular-nums">{r.latestText ?? `${r.latest}${r.unit ?? ''}`}</span>{' '}
                    <StandardLevelBadge level={r.level} domain={r.domain} /></>
                : 'No result yet'}
              {r.target && <> · target {r.target}{r.met === true ? ' ✓' : r.met === false ? ' ✗' : ''}</>}
            </span>
          </div>
          {r.standards && (
            <StandardLadder thresholds={thresholdTexts(r.standardsText, r.standards, r.unit ?? '')}
                            levelIndex={r.latest != null ? r.levelIndex : undefined} domain={r.domain} />
          )}
        </div>
      ))}
    </div>
  )
}

/** One progress entry — a methodology's own metric, in its own currency. */
export function ProgressCard({ entry }: { entry: AnalyticsProgressEntry }) {
  const exercises = entry.exercises ?? []
  const [selected, setSelected] = useState(entry.leadExerciseId ?? exercises[0]?.exerciseId ?? '')
  const ex = exercises.find((e) => e.exerciseId === selected) ?? exercises[0]
  const series = ex ? ex.series : entry.series
  const expected = ex ? ex.expected : entry.expected
  const status = ex ? ex.status : entry.status
  const trend = ex ? ex.trend : entry.trend
  // A bodyweight lift beside a loaded one: each exercise says its own unit.
  const unit = ex?.unit ?? entry.unit

  return (
    <div className={cn('rounded-lg border bg-card p-4 space-y-3', entry.headline && 'border-primary/40')}>
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="truncate text-sm font-semibold text-foreground">{entry.label}</p>
          <p className="text-[11px] text-muted-foreground">
            {entry.metric.replace(/_/g, ' ')}{unit ? ` · ${unit}` : ''}
            {trend.direction !== 'insufficient_data' && <> · {trend.direction} ({trend.slopePct > 0 ? '+' : ''}{trend.slopePct}%/pt)</>}
            {entry.headline && <> · headline</>}
          </p>
        </div>
        <StatusBadge status={status} />
      </div>

      <CoverageNotice coverage={entry.coverage} />

      {entry.primitive === 'unlocks' ? <Unlocks entry={entry} />
        : entry.primitive === 'benchmark_level' ? <Benchmarks entry={entry} />
        : (
          <>
            <ExercisePicker exercises={exercises} selected={selected} onSelect={setSelected} />
            <SeriesChart series={series} expected={expected} unit={unit} />
            {ex?.stalled && (
              <p className="text-xs text-red-700 dark:text-red-300">
                Stalled: {ex.name} has not moved for the last sessions this methodology allows.
              </p>
            )}
          </>
        )}

      {entry.evidence.length > 0 && (
        <ul className="text-[11px] text-muted-foreground space-y-0.5">
          {entry.evidence.slice(0, 4).map((e, i) => <li key={i}>{e}</li>)}
        </ul>
      )}
    </div>
  )
}
