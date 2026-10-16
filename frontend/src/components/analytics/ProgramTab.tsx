import { Link } from 'react-router-dom'
import { useProgramAnalytics } from '@/api/analytics'
import { EmptyState } from '@/components/shared/EmptyState'
import { LoadingCard } from '@/components/shared/LoadingCard'
import { ErrorBanner } from '@/components/shared/ErrorBanner'
import { ProgramFrame } from './ProgramFrame'
import { Scorecard } from './Scorecard'
import { IntensitySplit } from './IntensitySplit'
import { MovementBalance } from './MovementBalance'
import { ArchetypeTable } from './ArchetypeTable'
import { StatusBadge } from './StatusBadge'

/**
 * Am I doing the plan? The frame, the scorecard, the intensity split, movement
 * by pattern, session shapes and load — from one server document
 * (src/analytics); this tab only lays it out. Whether the training is working
 * — each methodology's own measures and the standards — is Analytics ▸
 * Progress, which reads the same document (moved there 2026-10-16; the
 * Progress tab's purpose line always said "the Program tab shows how closely
 * you follow the plan").
 */
export function ProgramTab() {
  const { data, isLoading, isError, error } = useProgramAnalytics()

  if (isLoading) return <div className="p-6 space-y-3"><LoadingCard lines={4} /><LoadingCard lines={6} /></div>
  if (isError) return <div className="p-6"><ErrorBanner error={error as Error} title="Could not load program analytics" /></div>
  if (!data || data.status === 'no_program') {
    return (
      <div className="p-6">
        <EmptyState title="No active program"
          description="Program analytics measures your training against what your program is for. Generate a program and it will appear here." />
      </div>
    )
  }

  const sectionErr = (s: unknown) => (s && typeof s === 'object' && 'error' in s) ? String((s as { error: string }).error) : null

  return (
    <div className="p-6 space-y-6 max-w-6xl">
      <ProgramFrame frame={data.frame} />

      <div className="grid gap-4 lg:grid-cols-2">
        {sectionErr(data.scorecard) ? <ErrorBanner error={new Error(sectionErr(data.scorecard)!)} title="Scorecard" /> : <Scorecard scorecard={data.scorecard} />}
        {sectionErr(data.intensity) ? <ErrorBanner error={new Error(sectionErr(data.intensity)!)} title="Intensity" /> : <IntensitySplit intensity={data.intensity} />}
      </div>

      {!sectionErr(data.movement) && <MovementBalance movement={data.movement} />}

      <Link to="/analytics?tab=progress"
            className="block rounded-lg border bg-card p-4 text-xs text-muted-foreground hover:border-primary/40 transition-colors">
        What {data.frame.philosophies.map((p) => p.name).join(' + ') || 'this program'} measures progress by, and the
        standards, are on <span className="font-medium text-foreground">Progress →</span>
      </Link>

      {!sectionErr(data.archetypes) && <ArchetypeTable rows={data.archetypes} />}

      <div className="rounded-lg border bg-card p-4 flex flex-wrap items-center justify-between gap-2 text-xs">
        <div className="text-muted-foreground">
          Training load, read in the light of the phase
          {data.load.phase && <> ({data.load.phase}{data.load.isDeload ? ', deload' : ''})</>}:
          {data.load.tsb != null && <> TSB <span className="font-semibold text-foreground">{data.load.tsb}</span></>}
          {data.load.readiness && <> · readiness <span className="font-semibold text-foreground">{data.load.readiness.score}</span></>}
          {' '}<Link to="/analytics?tab=recovery" className="underline underline-offset-2">Recovery →</Link>
        </div>
        {data.load.reading && <StatusBadge status={data.load.reading} />}
      </div>
    </div>
  )
}
