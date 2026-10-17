import { useState } from 'react'
import type { AnalyticsBenchmarkRow, ProgramAnalytics } from '@/api/types'
import { StandardLadder, StandardLevelBadge } from '@/components/standards/StandardLadder'
import { thresholdTexts } from '@/lib/standards'

const WHY_LABEL: Record<string, string> = { philosophy: 'this methodology', priority_modality: 'priority modality', declared: 'declared' }

/** The standards this program is measured by, and where the athlete stands. */
export function BenchmarkLadder({ benchmarks }: { benchmarks: ProgramAnalytics['benchmarks'] }) {
  const [showMore, setShowMore] = useState(false)
  const rows = benchmarks.benchmarks
  if (rows.length === 0) return null
  // The program's own standards first; same-domain tables from other sources
  // wait behind a toggle. With none of its own, show everything as before.
  const own = rows.filter((b) => b.primary !== false)
  const more = rows.filter((b) => b.primary === false)
  const shown = own.length === 0 ? rows : showMore ? [...own, ...more] : own
  return (
    <div className="rounded-lg border bg-card p-4 space-y-4">
      <div>
        <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Standards</p>
        <p className="text-xs text-muted-foreground">
          This program's own standards, and any you have a number for.
          {benchmarks.bodyweightKg != null
            ? <> Bodyweight {benchmarks.bodyweightText ?? `${benchmarks.bodyweightKg} kg`} lets ×BW standards derive from your logged sets.</>
            : <> Log your bodyweight under Profile ▸ Athlete to derive ×BW standards from logged sets.</>}
        </p>
      </div>
      <div className="grid gap-3 lg:grid-cols-2">
        {shown.map((b) => <StandardRow key={b.benchmarkId} b={b} />)}
      </div>
      {own.length > 0 && more.length > 0 && (
        <button type="button" onClick={() => setShowMore((v) => !v)}
          className="text-[11px] text-muted-foreground hover:text-foreground transition-colors">
          {showMore ? 'Fewer standards' : `More standards (${more.length}) — same domains, other sources`}
        </button>
      )}
    </div>
  )
}

function StandardRow({ b }: { b: AnalyticsBenchmarkRow }) {
  return (
    <div className="space-y-1.5">
      <div className="flex items-center justify-between gap-2 text-xs">
        <span className="font-medium">{b.name}</span>
        <span className="text-muted-foreground">
          {b.value != null ? (
            <>
              <span className="font-semibold text-foreground tabular-nums">{b.valueText ?? `${b.value}${b.unit}`}</span>
              {b.valueSource === 'derived' ? ' est.' : ''}{' '}
              <StandardLevelBadge level={b.level} domain={b.domain} />
            </>
          ) : 'No result yet'}
          {b.value != null && b.next && b.gapToNext != null && <> · {b.gapText ?? `${b.gapToNext}${b.unit}`} to {b.next}</>}
        </span>
      </div>
      <StandardLadder thresholds={thresholdTexts(b.standardsText, b.standards, b.unit)}
                      levelIndex={b.value != null ? b.levelIndex : undefined} domain={b.domain} />
      <p className="text-[10px] text-muted-foreground">
        {b.why.map((w) => WHY_LABEL[w]).join(' · ')}
        {b.derived?.reason === 'no_bodyweight_logged' && ' · est. 1RM known, bodyweight not'}
      </p>
    </div>
  )
}
