import { useState } from 'react'
import { Link } from 'react-router-dom'
import { ArrowRight, ChevronDown, LineChart } from 'lucide-react'
import type { AnalyticsFrame, AnalyticsMethodology, AnalyticsProgressEntry } from '@/api/types'
import { SpecSourceBadge } from '@/components/explore/SpecSourceBadge'
import { StandardLadder, StandardLevelBadge } from '@/components/standards/StandardLadder'
import { thresholdTexts } from '@/lib/standards'
import { cn } from '@/lib/utils'
import { StatusBadge } from './StatusBadge'
import { CoverageNotice } from './CoverageNotice'

/**
 * Each methodology's own measures, one row each: the latest number, the
 * status, the trend. A row the chart can draw selects it there; every row
 * opens to its coverage and evidence (and the movements or standards an
 * unlocks or standards measure lists). The per-measure chart cards it
 * replaced drew the same lines the one chart now draws (2026-10-23).
 */
export function MeasureList({ methodologies, progress, frame, chartable, selectedId, onChart }: {
  methodologies: AnalyticsMethodology[]
  progress: AnalyticsProgressEntry[]
  frame: AnalyticsFrame
  /** `${philosophy}:${id}` of the measures the chart can draw. */
  chartable: Set<string>
  /** The charted measure's `${philosophy}:${id}`. */
  selectedId: string | null
  onChart: (key: string) => void
}) {
  return (
    <div className="space-y-5">
      {methodologies.map((m) => (
        <Methodology key={m.philosophy} method={m} frame={frame} chartable={chartable} selectedId={selectedId}
                     onChart={onChart} entries={progress.filter((p) => p.philosophy === m.philosophy)} />
      ))}
    </div>
  )
}

function Methodology({ method, entries, frame, chartable, selectedId, onChart }: {
  method: AnalyticsMethodology; entries: AnalyticsProgressEntry[]; frame: AnalyticsFrame
  chartable: Set<string>; selectedId: string | null; onChart: (id: string) => void
}) {
  const phil = frame.philosophies.find((p) => p.id === method.philosophy)
  // An entry no session of this program is in scope for (a pentathlon cadence
  // in General Practice) is not "unmeasured": it gets a line, not a row.
  const applying = entries.filter((e) => e.applies !== false)
  const elsewhere = entries.filter((e) => e.applies === false)
  const ordered = [...applying].sort((a, b) => Number(b.headline) - Number(a.headline))
  return (
    <section className="space-y-2">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <div>
          <h3 className="text-sm font-semibold text-foreground">{phil?.name ?? method.philosophy}</h3>
          <p className="text-[11px] text-muted-foreground flex items-center gap-1.5 flex-wrap">
            <span>
              {method.measurable} of {method.applicable ?? method.total} measures measurable
              {method.weight < 1 && <> · {Math.round(method.weight * 100)}% of the blend</>}
            </span>
            <SpecSourceBadge source={method.analytics} />
          </p>
        </div>
        <Link
          to={`/explore?topic=philosophies&id=${encodeURIComponent(method.philosophy)}`}
          className="inline-flex items-center gap-1 text-[11px] text-muted-foreground hover:text-foreground transition-colors"
        >
          How this is measured <ArrowRight className="size-3" />
        </Link>
      </div>
      <ul className="divide-y divide-border/60 rounded-lg border bg-card">
        {ordered.map((entry) => (
          <MeasureRow key={entry.id} entry={entry} selected={selectedId === `${entry.philosophy}:${entry.id}`}
                      chartable={chartable.has(`${entry.philosophy}:${entry.id}`)}
                      onChart={() => onChart(`${entry.philosophy}:${entry.id}`)} />
        ))}
      </ul>
      {elsewhere.length > 0 && (
        <p className="text-[11px] text-muted-foreground">
          Not in this program: {elsewhere.map((e) => `${e.label}${appliesInText(e)}`).join(' · ')}
        </p>
      )}
    </section>
  )
}

/** The measure's latest number in its own unit: the lead lift's for a load measure. */
function latestText(entry: AnalyticsProgressEntry): string | null {
  if (entry.primitive === 'unlocks') return entry.practised ? `${entry.practised.length} practised` : null
  if (entry.primitive === 'benchmark_level') {
    const rows = (entry.benchmarks ?? []) as Array<{ missing?: boolean; latest?: number | null }>
    const known = rows.filter((r) => !r.missing)
    return known.length ? `${known.filter((r) => r.latest != null).length} of ${known.length} with a result` : null
  }
  const lead = (entry.exercises ?? []).find((e) => e.exerciseId === entry.leadExerciseId)
  const series = lead ? lead.series : entry.series
  const last = [...series].reverse().find((p) => p.value != null)
  if (!last) return null
  const unit = lead?.unit ?? entry.unit
  return `${last.value}${unit ? ` ${unit}` : ''}${lead ? ` · ${lead.name}` : ''}`
}

function MeasureRow({ entry, selected, chartable, onChart }: {
  entry: AnalyticsProgressEntry; selected: boolean; chartable: boolean; onChart: () => void
}) {
  const [open, setOpen] = useState(false)
  const latest = latestText(entry)
  const lead = (entry.exercises ?? []).find((e) => e.exerciseId === entry.leadExerciseId)
  const trend = lead ? lead.trend : entry.trend
  const status = lead ? lead.status : entry.status
  return (
    <li className={cn('px-3 py-2', selected && 'bg-primary/5')}>
      <div className="flex items-center gap-2">
        <button type="button" onClick={() => setOpen((v) => !v)} aria-expanded={open}
                className="flex min-w-0 flex-1 items-center gap-2 text-left">
          <ChevronDown className={cn('size-3.5 shrink-0 text-muted-foreground transition-transform', !open && '-rotate-90')} aria-hidden="true" />
          <span className="min-w-0 flex-1">
            <span className="block truncate text-sm font-medium text-foreground">
              {entry.label}{entry.headline && <span className="ml-1.5 text-[10px] font-normal text-primary">headline</span>}
            </span>
            <span className="block truncate text-[11px] text-muted-foreground tabular-nums">
              {latest ?? 'nothing measured yet'}
              {trend.direction !== 'insufficient_data' && <> · {trend.direction}</>}
              {entry.coverage.inScope > 0 && entry.coverage.pct < 100 && <> · {entry.coverage.pct}% measured</>}
            </span>
          </span>
        </button>
        <StatusBadge status={status} />
        {chartable && (
          <button type="button" onClick={onChart} aria-label={`Chart ${entry.label}`} aria-pressed={selected}
                  className={cn('rounded p-1 transition-colors', selected ? 'text-primary' : 'text-muted-foreground hover:text-foreground')}>
            <LineChart className="size-4" />
          </button>
        )}
      </div>
      {open && (
        <div className="mt-2 space-y-2 pl-5">
          <CoverageNotice coverage={entry.coverage} />
          {entry.primitive === 'unlocks' && <Unlocks entry={entry} />}
          {entry.primitive === 'benchmark_level' && <Benchmarks entry={entry} />}
          {lead?.stalled && (
            <p className="text-xs text-red-700 dark:text-red-300">
              Stalled: {lead.name} has not moved for the last sessions this methodology allows.
            </p>
          )}
          {entry.evidence.length > 0 && (
            <ul className="text-[11px] text-muted-foreground space-y-0.5">
              {entry.evidence.slice(0, 4).map((e, i) => <li key={i}>{e}</li>)}
            </ul>
          )}
        </div>
      )}
    </li>
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

/** " (Pentathlon Prep)" — where an entry this program does not schedule applies. */
function appliesInText(entry: AnalyticsProgressEntry): string {
  const tracks = (entry.appliesIn ?? []).map((t) => t.track)
  return tracks.length ? ` (${tracks.join(', ')})` : ''
}
