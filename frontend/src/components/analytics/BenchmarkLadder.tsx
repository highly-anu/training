import { Link } from 'react-router-dom'
import type { AnalyticsBenchmarkRow, ProgramAnalytics } from '@/api/types'
import { StandardLadder, StandardLevelBadge } from '@/components/standards/StandardLadder'
import { StandardSparkline } from '@/components/standards/StandardSparkline'
import { blockChangeText, thresholdTexts } from '@/lib/standards'

const WHY_LABEL: Record<string, string> = {
  tested: 'tested in this program', linked: 'estimated from a lift in this program',
  declared: 'declared by this methodology',
}

/**
 * The standards this program is measured by — those it tests and those a lift
 * it schedules estimates — with where the athlete stood when the block began
 * and how far they have moved. Every other standard is on Profile ▸
 * Standards; "More standards" (same domain, other sources) went on
 * 2026-10-23, when the server stopped sending them.
 */
export function BenchmarkLadder({ benchmarks }: { benchmarks: ProgramAnalytics['benchmarks'] }) {
  // An older server still sends the extras, marked not primary.
  const shown = benchmarks.benchmarks.filter((b) => b.primary !== false)
  if (shown.length === 0) return null
  return (
    <div className="rounded-lg border bg-card p-4 space-y-4">
      <div>
        <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Standards</p>
        <p className="text-xs text-muted-foreground">
          What this program tests, or estimates from its lifts, and how far you have moved this block.
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
      <Link to="/profile?tab=standards" className="block text-[11px] text-muted-foreground hover:text-foreground transition-colors">
        Every standard, with your results, is on Profile ▸ Standards →
      </Link>
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
            || b.why.map((w) => WHY_LABEL[w] ?? w).join(' · ')}
        </p>
        {b.blockHistory && (
          <StandardSparkline points={b.blockHistory} domain={b.domain}
            label={`This block: ${b.blockHistory.map((p) => p.valueText).join(' → ')}`} />
        )}
      </div>
    </div>
  )
}
