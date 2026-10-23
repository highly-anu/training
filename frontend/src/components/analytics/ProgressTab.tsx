import { useMemo, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { differenceInCalendarDays, parseISO } from 'date-fns'
import { fetchProgressionReview } from '@/api/progression'
import { useProgramAnalytics } from '@/api/analytics'
import { useApplyAdjustment } from '@/api/programs'
import { useProgramStore } from '@/store/programStore'
import type { ExerciseFinding, ProgressionAdjustment } from '@/api/types'
import { EmptyState } from '@/components/shared/EmptyState'
import { LoadingCard } from '@/components/shared/LoadingCard'
import { ErrorBanner } from '@/components/shared/ErrorBanner'
import { ProgressSummary } from '@/components/progression/ProgressSummary'
import { chartableMeasures, resolveSelection, type ChartSelection } from '@/lib/progressChart'
import { ProgramFrame } from './ProgramFrame'
import { ProgressChart } from './ProgressChart'
import { MeasureList } from './MeasureList'
import { Scorecard } from './Scorecard'
import { IntensitySplit } from './IntensitySplit'
import { BenchmarkLadder } from './BenchmarkLadder'
import { ArchetypeTable } from './ArchetypeTable'
import { StatusBadge } from './StatusBadge'

/**
 * Analytics ▸ Progress: what the athlete did against what the program asked,
 * and whether it is working — from one server document (src/analytics); this
 * tab only lays it out. The frame and the score, then the one chart (every
 * exercise's sets, reps and load, done against prescribed, and each
 * methodology measure), the measures, the scorecard and intensity split, the
 * program's standards, the workouts and the load. Program and Progress were
 * two tabs until 2026-10-23; Movement balance is parked (the server still
 * builds it).
 */
export function ProgressTab() {
  const { data, isLoading, isError, error } = useProgramAnalytics()
  const [params, setParams] = useSearchParams()

  // The review's period changes nothing it computes — compliance covers the
  // program so far (its scope_label says so) — so there is no toggle.
  const { data: review } = useQuery({
    queryKey: ['progression', 'review', 'weekly'],
    queryFn: () => fetchProgressionReview('weekly'),
    staleTime: 5 * 60 * 1000,
  })
  const findings = useMemo(() => {
    const m = new Map<string, ExerciseFinding>()
    for (const f of review?.exercise_findings ?? []) m.set(f.exercise_id, f)
    return m
  }, [review?.exercise_findings])

  const doc = data && data.status !== 'no_program' ? data : null
  const section = doc?.exerciseSeries && !('error' in doc.exerciseSeries) ? doc.exerciseSeries : undefined
  const progress = useMemo(() => doc?.progress ?? [], [doc?.progress])
  const selection = useMemo(
    () => resolveSelection({ exercise: params.get('exercise'), measure: params.get('measure'), metric: params.get('metric') },
      section, progress),
    [params, section, progress])
  const chartable = useMemo(
    () => new Set(chartableMeasures(section, progress).map((p) => `${p.philosophy}:${p.id}`)),
    [section, progress])

  function select(s: ChartSelection) {
    setParams((prev) => {
      const next = new URLSearchParams(prev)
      next.delete('exercise'); next.delete('measure'); next.delete('metric')
      if (s.kind === 'exercise') { next.set('exercise', s.id); next.set('metric', s.metric) }
      else next.set('measure', s.id)
      return next
    }, { replace: true })
  }

  if (isLoading) return <div className="p-6 space-y-3"><LoadingCard lines={4} /><LoadingCard lines={6} /></div>
  if (isError) return <div className="p-6"><ErrorBanner error={error as Error} title="Could not load program analytics" /></div>
  if (!doc) {
    return (
      <div className="p-6">
        <EmptyState title="No active program"
          description="Progress measures your training against what your program is for. Generate a program and it will appear here." />
      </div>
    )
  }

  const sectionErr = (s: unknown) => (s && typeof s === 'object' && 'error' in s) ? String((s as { error: string }).error) : null
  // Advice holds from the first session due — consistency above all — not
  // only once a measure has a trend (the score is the trends alone).
  const isInsufficient = !review || review.score_breakdown?.basis === 'not_started'
    || (review.score_breakdown == null && review.overall_score === null)
  const recommendations = isInsufficient ? [] : (review?.recommendations ?? [])
  const adjustments = isInsufficient ? [] : (review?.adjustments ?? [])

  return (
    <div className="p-6 space-y-6 max-w-6xl">
      <ProgramFrame frame={doc.frame} />
      {review && <ProgressSummary review={review} />}

      {sectionErr(doc.exerciseSeries)
        ? <ErrorBanner error={new Error(sectionErr(doc.exerciseSeries)!)} title="Chart" />
        : <ProgressChart section={section} progress={progress} selection={selection} onSelect={select} findings={findings} />}

      <MeasureList methodologies={doc.methodologies} progress={progress} frame={doc.frame} chartable={chartable}
                   selectedId={selection?.kind === 'measure' ? selection.id : null}
                   onChart={(id) => select({ kind: 'measure', id })} />

      <div className="grid gap-4 lg:grid-cols-2">
        {sectionErr(doc.scorecard) ? <ErrorBanner error={new Error(sectionErr(doc.scorecard)!)} title="Scorecard" /> : <Scorecard scorecard={doc.scorecard} />}
        {sectionErr(doc.intensity) ? <ErrorBanner error={new Error(sectionErr(doc.intensity)!)} title="Intensity" /> : <IntensitySplit intensity={doc.intensity} />}
      </div>

      {!sectionErr(doc.benchmarks) && <BenchmarkLadder benchmarks={doc.benchmarks} />}
      {!sectionErr(doc.archetypes) && <ArchetypeTable rows={doc.archetypes} />}

      <div className="rounded-lg border bg-card p-4 flex flex-wrap items-center justify-between gap-2 text-xs">
        <div className="text-muted-foreground">
          Training load, read in the light of the phase
          {doc.load.phase && <> ({doc.load.phase}{doc.load.isDeload ? ', deload' : ''})</>}:
          {doc.load.tsb != null && <> TSB <span className="font-semibold text-foreground">{doc.load.tsb}</span></>}
          {doc.load.readiness && <> · readiness <span className="font-semibold text-foreground">{doc.load.readiness.score}</span></>}
          {' '}<Link to="/analytics?tab=recovery" className="underline underline-offset-2">Recovery →</Link>
        </div>
        {doc.load.reading && <StatusBadge status={doc.load.reading} />}
      </div>

      {adjustments.length > 0 && <AdjustmentList adjustments={adjustments} />}
      {!isInsufficient && recommendations.length === 0 && adjustments.length === 0 && (
        <p className="border-t border-border/40 pt-4 text-[11px] text-muted-foreground">Nothing to change — keep going.</p>
      )}
      {recommendations.length > 0 && (
        <div className="space-y-1 border-t border-border/40 pt-4">
          {recommendations.slice(0, 3).map((r, i) => <p key={i} className="text-[11px] text-muted-foreground">· {r}</p>)}
        </div>
      )}

      <p className="text-[11px] text-muted-foreground">
        Every completed session, linked or not, is in{' '}
        <Link to="/log?show=sessions" className="underline underline-offset-2 hover:text-foreground">Log ▸ Activity</Link>
        {' '}and{' '}
        <Link to="/log?tab=linking" className="underline underline-offset-2 hover:text-foreground">Linking</Link>.
      </p>
    </div>
  )
}

// ── Adjustments ────────────────────────────────────────────────────────────────

const ADJUSTMENT_LABEL: Record<string, string> = {
  hold_load: 'Hold the load',
  reduce_volume_10pct: 'Reduce volume 10 %',
  early_deload: 'Deload this week',
  increase_increment: 'Raise the increment',
  rebuild_habit: 'Rebuild the habit',
}
// rebuild_habit is about consistency, not the plan — the server refuses it.
const APPLIABLE = new Set(['hold_load', 'reduce_volume_10pct', 'early_deload', 'increase_increment'])

/**
 * The review's adjustments were advice nothing could act on. Each appliable
 * one edits the stored program from the current week on, under the revision
 * check, and reloads it.
 */
function AdjustmentList({ adjustments }: { adjustments: ProgressionAdjustment[] }) {
  const apply = useApplyAdjustment()
  const programStartDate = useProgramStore((s) => s.programStartDate)
  const weekCount = useProgramStore((s) => s.currentProgram?.weeks.length ?? 0)
  const [appliedType, setAppliedType] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)

  const fromWeekIndex = (() => {
    if (!programStartDate || weekCount === 0) return null
    const days = differenceInCalendarDays(new Date(), parseISO(programStartDate))
    return Math.max(0, Math.min(Math.floor(days / 7), weekCount - 1))
  })()

  function run(adj: ProgressionAdjustment) {
    setMessage(null)
    apply.mutate(
      { adjustment: adj, fromWeekIndex },
      {
        onSuccess: (res) => {
          setAppliedType(adj.type)
          const weeks = res.applied.weeks.map((w) => w + 1)
          setMessage(
            res.applied.exercises > 0
              ? `Applied to ${res.applied.exercises} exercise${res.applied.exercises === 1 ? '' : 's'} in week${weeks.length === 1 ? '' : 's'} ${weeks.join(', ')}.`
              : 'Nothing in the remaining weeks matched this adjustment.'
          )
        },
        onError: (err) => {
          setMessage(err instanceof Error && err.message === 'stale_revision'
            ? 'Your program changed elsewhere — reloaded; try again.'
            : (err instanceof Error ? err.message : 'Could not apply'))
        },
      }
    )
  }

  return (
    <div className="space-y-2 border-t border-border/40 pt-4">
      <h3 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">Suggested adjustments</h3>
      {adjustments.map((adj, i) => (
        <div key={`${adj.type}-${i}`} className="flex items-start justify-between gap-3 rounded-xl border border-border/60 bg-card px-4 py-3">
          <div className="min-w-0">
            <p className="text-sm font-medium">{ADJUSTMENT_LABEL[adj.type] ?? adj.type}
              {adj.target && adj.target !== 'all' && adj.target !== 'schedule' && (
                <span className="ml-1.5 text-xs font-normal text-muted-foreground">· {adj.target}</span>
              )}
            </p>
            <p className="text-[11px] text-muted-foreground">{adj.reason}</p>
          </div>
          {APPLIABLE.has(adj.type) ? (
            <button
              type="button"
              disabled={apply.isPending || appliedType === adj.type}
              onClick={() => run(adj)}
              className="shrink-0 rounded-md border border-primary/40 bg-primary/10 px-2.5 py-1 text-xs font-medium text-primary hover:bg-primary/20 disabled:opacity-50 transition-colors"
            >
              {appliedType === adj.type ? 'Applied' : apply.isPending ? 'Applying…' : `Apply from week ${(fromWeekIndex ?? 0) + 1}`}
            </button>
          ) : (
            <span className="shrink-0 text-[11px] text-muted-foreground/70">advice</span>
          )}
        </div>
      ))}
      {message && <p className="text-[11px] text-muted-foreground">{message}</p>}
    </div>
  )
}
