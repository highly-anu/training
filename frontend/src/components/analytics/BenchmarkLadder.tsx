import { useState } from 'react'
import { Link } from 'react-router-dom'
import type { AnalyticsBenchmarkRow, ProgramAnalytics } from '@/api/types'
import { StandardLadder, StandardLevelBadge } from '@/components/standards/StandardLadder'
import { StandardSparkline } from '@/components/standards/StandardSparkline'
import { blockChangeText, thresholdTexts } from '@/lib/standards'

const WHY_LABEL: Record<string, string> = {
  declared: 'declared by this methodology', tested: 'tested in this program',
  philosophy: 'cites this methodology', priority_modality: 'same domain as a priority',
}

/**
 * The standards this program is measured by — what its package declares and
 * what it tests — with where the athlete stood when the block began and how
 * far they have moved. Standards that only share a domain or cite the
 * methodology wait behind "More standards"; a result alone no longer makes
 * a standard the program's own.
 */
export function BenchmarkLadder({ benchmarks }: { benchmarks: ProgramAnalytics['benchmarks'] }) {
  const [showMore, setShowMore] = useState(false)
  const rows = benchmarks.benchmarks
  if (rows.length === 0) return null
  const own = rows.filter((b) => b.primary)
  const more = rows.filter((b) => !b.primary)
  const shown = showMore ? [...own, ...more] : own
  return (
    <div className="rounded-lg border bg-card p-4 space-y-4">
      <div>
        <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Standards</p>
        <p className="text-xs text-muted-foreground">
          {own.length > 0
            ? 'What this program is measured by, and how far you have moved this block.'
            : 'This program declares no standards of its own.'}
          {benchmarks.bodyweightKg != null
            ? <> Bodyweight {benchmarks.bodyweightText ?? `${benchmarks.bodyweightKg} kg`} lets ×BW standards derive from your logged sets.</>
            : <> Log your bodyweight under Profile ▸ Athlete to derive ×BW standards from logged sets.</>}
        </p>
      </div>
      {shown.length > 0 && (
        <div className="grid gap-3 lg:grid-cols-2">
          {shown.map((b) => <StandardRow key={b.benchmarkId} b={b} />)}
        </div>
      )}
      {more.length > 0 && (
        <button type="button" onClick={() => setShowMore((v) => !v)}
          className="text-[11px] text-muted-foreground hover:text-foreground transition-colors">
          {showMore ? 'Fewer standards' : `More standards (${more.length}) — same domains, other sources`}
        </button>
      )}
    </div>
  )
}

function StandardRow({ b }: { b: AnalyticsBenchmarkRow }) {
  const change = blockChangeText(b)
  return (
    <div className="space-y-1.5">
      <div className="flex items-center justify-between gap-2 text-xs">
        <Link to={`/profile?tab=standards&standard=${b.benchmarkId}`} className="font-medium hover:underline underline-offset-2">
          {b.name}
        </Link>
        <span className="text-muted-foreground">
          {b.value != null ? (
            <>
              <span className="font-semibold text-foreground tabular-nums">{b.valueText ?? `${b.value}${b.unit}`}</span>
              {b.valueSource === 'derived' ? ' est.' : ''}{' '}
              <StandardLevelBadge level={b.level} domain={b.domain} />
            </>
          ) : 'No result yet'}
        </span>
      </div>
      <StandardLadder thresholds={thresholdTexts(b.standardsText, b.standards, b.unit)}
                      levelIndex={b.value != null ? b.levelIndex : undefined} domain={b.domain} />
      <div className="flex items-center justify-between gap-2 text-[10px] text-muted-foreground">
        <p>
          {[change,
            b.value != null && b.next && b.gapToNext != null ? `${b.gapText ?? `${b.gapToNext}${b.unit}`} to ${b.next}` : null,
            b.derived?.reason === 'no_bodyweight_logged' ? 'est. 1RM known, bodyweight not' : null,
          ].filter(Boolean).join(' · ')
            // With nothing to say about the result, say why it is here — for
            // the program's own, only that (not every incidental reason).
            || b.why.filter((w) => !b.primary || w === 'declared' || w === 'tested').map((w) => WHY_LABEL[w] ?? w).join(' · ')}
        </p>
        {b.blockHistory && (
          <StandardSparkline points={b.blockHistory} domain={b.domain}
            label={`This block: ${b.blockHistory.map((p) => p.valueText).join(' → ')}`} />
        )}
      </div>
    </div>
  )
}
