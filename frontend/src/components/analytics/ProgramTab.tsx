import { Link } from 'react-router-dom'
import { useProgramAnalytics } from '@/api/analytics'
import { EmptyState } from '@/components/shared/EmptyState'
import { LoadingCard } from '@/components/shared/LoadingCard'
import { ErrorBanner } from '@/components/shared/ErrorBanner'
import { ProgramFrame } from './ProgramFrame'
import { Scorecard } from './Scorecard'
import { IntensitySplit } from './IntensitySplit'
import { MethodologySection } from './MethodologySection'
import { MovementBalance } from './MovementBalance'
import { ArchetypeTable } from './ArchetypeTable'
import { BenchmarkLadder } from './BenchmarkLadder'
import { StatusBadge } from './StatusBadge'

/**
 * How the athlete is doing against what the active program is for — per
 * methodology, in that methodology's own currency. Everything here comes from
 * one server document (src/analytics); this tab only lays it out.
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

      {data.methodologies.map((m) => (
        <MethodologySection key={m.philosophy} method={m} frame={data.frame}
                            entries={data.progress.filter((p) => p.philosophy === m.philosophy)} />
      ))}

      <div className="grid gap-4 lg:grid-cols-2">
        {!sectionErr(data.movement) && <MovementBalance movement={data.movement} />}
        {!sectionErr(data.benchmarks) && <BenchmarkLadder benchmarks={data.benchmarks} />}
      </div>

      {!sectionErr(data.archetypes) && <ArchetypeTable rows={data.archetypes} />}

      <div className="rounded-lg border bg-card p-4 flex flex-wrap items-center justify-between gap-2 text-xs">
        <div className="text-muted-foreground">
          Training load, read in the light of the phase
          {data.load.phase && <> ({data.load.phase}{data.load.isDeload ? ', deload' : ''})</>}:
          {data.load.tsb != null && <> TSB <span className="font-semibold text-foreground">{data.load.tsb}</span></>}
          {data.load.readiness && <> · readiness <span className="font-semibold text-foreground">{data.load.readiness.score}</span></>}
          {' '}<Link to="/bio" className="underline underline-offset-2">Recovery →</Link>
        </div>
        {data.load.reading && <StatusBadge status={data.load.reading} />}
      </div>
    </div>
  )
}
