import { useMemo } from 'react'
import { Link, useParams } from 'react-router-dom'
import { motion } from 'framer-motion'
import { format, parseISO } from 'date-fns'
import { ChevronLeft, CheckCircle2, Link2, Clock, CircleSlash } from 'lucide-react'
import { useProgramVersion } from '@/api/programHistory'
import { ModalityBadge } from '@/components/shared/ModalityBadge'
import { PhaseBadge } from '@/components/shared/PhaseBadge'
import { EmptyState } from '@/components/shared/EmptyState'
import { LoadingCard } from '@/components/shared/LoadingCard'
import { ErrorBanner } from '@/components/shared/ErrorBanner'
import { Badge } from '@/components/ui/badge'
import { Separator } from '@/components/ui/separator'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import { cn } from '@/lib/utils'
import type { PlannedSession, TrainingPhase } from '@/api/types'

/**
 * One archived program, exactly as it was planned.
 *
 * Read-only by construction: these rows are the record of what was prescribed
 * on each date, and editing them would destroy the thing the page exists to
 * show. Weeks the plan never reached — because it was replaced first — are shown
 * dimmed rather than hidden, because "what this plan intended" and "what was in
 * force" are different questions and both are worth answering.
 */

function fmt(iso: string, pattern = 'EEE d MMM'): string {
  try {
    return format(parseISO(iso), pattern)
  } catch {
    return iso
  }
}

function SessionRow({ session }: { session: PlannedSession }) {
  const ghost = session.wasEffective === false
  const colour = MODALITY_COLORS[session.modality]

  return (
    <div
      className={cn(
        'flex items-center gap-3 rounded-md border bg-card p-3',
        ghost && 'opacity-50 border-dashed'
      )}
    >
      <div
        className="h-8 w-0.5 shrink-0 rounded-full"
        style={{ backgroundColor: colour?.hex ?? 'var(--border)' }}
        aria-hidden="true"
      />

      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <p className="truncate text-sm font-semibold text-foreground">
            {session.archetypeName ?? session.modality.replace(/_/g, ' ')}
          </p>
          {session.isDeload && (
            <Badge variant="secondary" className="shrink-0 text-[10px]">Deload</Badge>
          )}
        </div>
        <div className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1">
          <ModalityBadge modality={session.modality} size="sm" />
          <span className="inline-flex items-center gap-1 text-[10px] text-muted-foreground">
            <Clock className="h-3 w-3" aria-hidden="true" />
            {session.durationMinutes} min
          </span>
        </div>
      </div>

      <div className="flex shrink-0 flex-col items-end gap-1">
        <span className="text-xs text-muted-foreground">{fmt(session.date)}</span>
        <div className="flex items-center gap-1.5">
          {/* Icon plus title, never colour alone (design system §1.6). */}
          {session.completedAt && (
            <CheckCircle2
              className="h-3.5 w-3.5 text-emerald-700 dark:text-emerald-300"
              aria-hidden="true"
            />
          )}
          {session.matchedWorkoutId && (
            <Link2 className="h-3.5 w-3.5 text-muted-foreground" aria-hidden="true" />
          )}
          {ghost && (
            <CircleSlash className="h-3.5 w-3.5 text-muted-foreground" aria-hidden="true" />
          )}
          <span className="sr-only">
            {session.completedAt ? 'Logged. ' : ''}
            {session.matchedWorkoutId ? 'Has a matched workout. ' : ''}
            {ghost ? 'This plan was replaced before this week.' : ''}
          </span>
        </div>
      </div>
    </div>
  )
}

export function ProgramHistoryDetail() {
  const { versionId } = useParams<{ versionId: string }>()
  const { data, isLoading, isError, error } = useProgramVersion(versionId)

  const weeks = useMemo(() => {
    const byWeek = new Map<number, PlannedSession[]>()
    for (const session of data?.sessions ?? []) {
      const list = byWeek.get(session.weekIndex) ?? []
      list.push(session)
      byWeek.set(session.weekIndex, list)
    }
    return [...byWeek.entries()].sort((a, b) => a[0] - b[0])
  }, [data])

  const summary = data?.activations?.[0]
  const name = summary?.goalName ?? summary?.sourceGoalIds?.join(' + ') ?? 'Program'
  const ran = (data?.sessions ?? []).filter((s) => s.wasEffective !== false).length
  const never = (data?.sessions ?? []).length - ran

  return (
    <div className="space-y-6 p-5">
      <Link
        to="/program/history"
        className="inline-flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring rounded"
      >
        <ChevronLeft className="h-4 w-4" aria-hidden="true" />
        Program history
      </Link>

      {isLoading && <LoadingCard lines={5} />}
      {isError && <ErrorBanner error={error as Error} title="Could not load this program" />}

      {data && (
        <>
          <header className="space-y-2">
            <div className="flex flex-wrap items-center gap-2">
              <h1 className="text-2xl font-bold tracking-tight">{name}</h1>
              {summary?.isActive && <Badge className="text-[10px]">Active</Badge>}
            </div>
            <p className="text-sm text-muted-foreground">
              {data.weekCount} weeks from {fmt(data.startDate, 'd MMM yyyy')}
              {summary && ` · in force ${fmt(summary.effectiveFrom, 'd MMM')}`}
              {summary?.effectiveTo && ` to ${fmt(summary.effectiveTo, 'd MMM yyyy')}`}
            </p>
            {never > 0 && (
              <p className="text-xs text-muted-foreground">
                {ran} sessions fell while this plan was in force; {never} were planned for
                weeks it never reached.
              </p>
            )}
          </header>

          <Separator />

          {weeks.length === 0 && (
            <EmptyState
              title="No sessions recorded"
              description="This program version has no flattened sessions — it was archived without a usable start date."
            />
          )}

          <div className="space-y-6">
            {weeks.map(([weekIndex, sessions], i) => (
              <motion.section
                key={weekIndex}
                initial={{ opacity: 0, y: 8 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: Math.min(i, 8) * 0.03, duration: 0.2 }}
                className="space-y-2"
              >
                <div className="flex items-center gap-2">
                  <h2 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                    Week {weekIndex + 1}
                    {/* The stored week_number can differ from the position — a
                        program regenerated from an event date is numbered by its
                        absolute week. Show both when they disagree. */}
                    {sessions[0].weekNumber != null &&
                      sessions[0].weekNumber !== weekIndex + 1 &&
                      ` (numbered ${sessions[0].weekNumber})`}
                  </h2>
                  {sessions[0].phase && (
                    <PhaseBadge phase={sessions[0].phase as TrainingPhase} />
                  )}
                </div>
                <div className="space-y-2">
                  {sessions.map((session) => (
                    <SessionRow key={session.sessionUid} session={session} />
                  ))}
                </div>
              </motion.section>
            ))}
          </div>
        </>
      )}
    </div>
  )
}
