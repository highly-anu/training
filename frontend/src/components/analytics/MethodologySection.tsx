import { Link } from 'react-router-dom'
import { ArrowRight } from 'lucide-react'
import type { AnalyticsFrame, AnalyticsMethodology, AnalyticsProgressEntry } from '@/api/types'
import { SpecSourceBadge } from '@/components/explore/SpecSourceBadge'
import { ProgressCard } from './ProgressCard'

/**
 * One philosophy's section: its headline metric first, then the rest of what
 * it declared. A blend renders one of these per philosophy.
 */
export function MethodologySection({ method, entries, frame }: {
  method: AnalyticsMethodology; entries: AnalyticsProgressEntry[]; frame: AnalyticsFrame
}) {
  const phil = frame.philosophies.find((p) => p.id === method.philosophy)
  // An entry no session of this program is in scope for (a pentathlon cadence
  // in General Practice) is not "unmeasured": it gets a line, not a card.
  const applying = entries.filter((e) => e.applies !== false)
  const elsewhere = entries.filter((e) => e.applies === false)
  const ordered = [...applying].sort((a, b) => Number(b.headline) - Number(a.headline))
  return (
    <section className="space-y-3">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <div>
          <h3 className="text-sm font-semibold text-foreground">{phil?.name ?? method.philosophy}</h3>
          <p className="text-[11px] text-muted-foreground flex items-center gap-1.5 flex-wrap">
            <span>
              {method.measurable} of {method.applicable ?? method.total} metrics measurable
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
      <div className="grid gap-3 lg:grid-cols-2">
        {ordered.map((entry) => <ProgressCard key={entry.id} entry={entry} />)}
      </div>
      {elsewhere.length > 0 && (
        <p className="text-[11px] text-muted-foreground">
          Not in this program: {elsewhere.map((e) => `${e.label}${appliesInText(e)}`).join(' · ')}
        </p>
      )}
    </section>
  )
}

/** " (Pentathlon Prep)" — where an entry this program does not schedule applies. */
function appliesInText(entry: AnalyticsProgressEntry): string {
  const tracks = (entry.appliesIn ?? []).map((t) => t.track)
  return tracks.length ? ` (${tracks.join(', ')})` : ''
}
