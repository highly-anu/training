import { useMemo } from 'react'
import { Link } from 'react-router-dom'
import { motion } from 'framer-motion'
import { differenceInCalendarDays, format, parseISO } from 'date-fns'
import { History, ChevronRight, Link2, CheckCircle2, CalendarRange } from 'lucide-react'
import { useProgramHistory } from '@/api/programHistory'
import { EmptyState } from '@/components/shared/EmptyState'
import { LoadingCard } from '@/components/shared/LoadingCard'
import { ErrorBanner } from '@/components/shared/ErrorBanner'
import { Badge } from '@/components/ui/badge'
import { cn } from '@/lib/utils'
import type { ProgramHistoryEntry } from '@/api/types'

/**
 * Every plan the athlete has trained, and the dates each was in force.
 * Program ▸ History.
 *
 * Only the *current* program used to exist: one row, overwritten on every save.
 * So a finished block left nothing behind, and a workout dated inside one could
 * never be matched to what had actually been planned for that day.
 */

function fmt(iso: string): string {
  try {
    return format(parseISO(iso), 'd MMM yyyy')
  } catch {
    return iso
  }
}

function spanLabel(entry: ProgramHistoryEntry): string {
  const start = fmt(entry.effectiveFrom)
  if (!entry.effectiveTo) return `${start} — now`
  return `${start} — ${fmt(entry.effectiveTo)}`
}

/** How long this plan was actually in force, in weeks. */
function weeksRun(entry: ProgramHistoryEntry): number | null {
  try {
    const end = entry.effectiveTo ? parseISO(entry.effectiveTo) : new Date()
    const weeks = Math.round(
      differenceInCalendarDays(end, parseISO(entry.effectiveFrom)) / 7
    )
    // A plan in force today is being trained in its first week, even on day one.
    // A closed interval can genuinely be zero weeks long — two regenerates in
    // one day leave the first with no days of its own.
    return entry.effectiveTo ? Math.max(0, weeks) : Math.max(1, weeks)
  } catch {
    return null
  }
}

function HistoryCard({ entry, index }: { entry: ProgramHistoryEntry; index: number }) {
  const ran = weeksRun(entry)
  const name = entry.goalName ?? entry.sourceGoalIds.join(' + ') ?? 'Program'

  return (
    <motion.div
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: index * 0.04, duration: 0.2 }}
    >
      <Link
        to={`/program/history/${entry.versionId}`}
        className={cn(
          'group flex items-center gap-4 rounded-lg border bg-card p-4 transition-colors',
          'hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
          entry.isActive && 'border-primary/50'
        )}
      >
        {/* A spine, so the list reads as a timeline rather than as cards. */}
        <div
          className={cn('h-10 w-0.5 shrink-0 rounded-full',
            entry.isActive ? 'bg-primary' : 'bg-border')}
          aria-hidden="true"
        />

        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2">
            <h3 className="truncate text-sm font-semibold text-foreground">{name}</h3>
            {entry.isActive && (
              <Badge variant="default" className="shrink-0 text-[10px]">Active</Badge>
            )}
          </div>

          <p className="mt-0.5 text-xs text-muted-foreground">{spanLabel(entry)}</p>

          <div className="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-[10px] text-muted-foreground">
            <span className="inline-flex items-center gap-1">
              <CalendarRange className="h-3 w-3" aria-hidden="true" />
              {/* Planned length and the length actually trained are different
                  facts, and the gap between them is the interesting one. */}
              {ran != null && ran < entry.weekCount
                ? `${ran} of ${entry.weekCount} wk trained`
                : `${entry.weekCount} wk`}
            </span>
            <span>{entry.sessionCount} sessions planned</span>
            {entry.matchedCount > 0 && (
              <span className="inline-flex items-center gap-1">
                <Link2 className="h-3 w-3" aria-hidden="true" />
                {entry.matchedCount} matched
              </span>
            )}
            {entry.loggedCount > 0 && (
              <span className="inline-flex items-center gap-1 text-emerald-700 dark:text-emerald-300">
                <CheckCircle2 className="h-3 w-3" aria-hidden="true" />
                {entry.loggedCount} logged
              </span>
            )}
          </div>
        </div>

        <ChevronRight
          className="h-4 w-4 shrink-0 text-muted-foreground transition-transform group-hover:translate-x-0.5"
          aria-hidden="true"
        />
      </Link>
    </motion.div>
  )
}

export function ProgramHistoryList() {
  const { data, isLoading, isError, error } = useProgramHistory()

  const grouped = useMemo(() => {
    // Revisions of one training block share a lineage. Showing each edit as its
    // own top-level entry would bury the blocks under the edits.
    const byLineage = new Map<string, ProgramHistoryEntry[]>()
    for (const entry of data ?? []) {
      const list = byLineage.get(entry.lineageId) ?? []
      list.push(entry)
      byLineage.set(entry.lineageId, list)
    }
    return [...byLineage.values()]
  }, [data])

  return (
    <div className="max-w-5xl mx-auto px-6 py-6 space-y-6">
      <p className="text-sm text-muted-foreground">
        Every plan you have trained, and when each was in force.
      </p>

      {isLoading && <LoadingCard />}

      {isError && <ErrorBanner error={error} title="Could not load program history" />}

      {!isLoading && !isError && grouped.length === 0 && (
        <EmptyState
          title="No history yet"
          description="Your programs are recorded from the moment you first open or save one. Generate a program and it will appear here."
          icon={<History className="h-8 w-8" aria-hidden="true" />}
        />
      )}

      <div className="space-y-6">
        {grouped.map((revisions) => (
          <section key={revisions[0].lineageId} className="space-y-2">
            {revisions.length > 1 && (
              <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                {revisions.length} revisions
              </p>
            )}
            {revisions.map((entry, i) => (
              <HistoryCard key={entry.activationId} entry={entry} index={i} />
            ))}
          </section>
        ))}
      </div>
    </div>
  )
}
