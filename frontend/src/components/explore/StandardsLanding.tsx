import { Link } from 'react-router-dom'
import { Trophy } from 'lucide-react'
import { useStandardResults, useStandards } from '@/api/standards'
import { StandardLadder, StandardLevelBadge } from '@/components/standards/StandardLadder'
import { thresholdTexts } from '@/lib/standards'
import { LoadingCard } from '@/components/shared/LoadingCard'
import type { BenchmarkStandard } from '@/api/types'

/**
 * Explore ▸ Standards — the ladders the methodologies measure against, with
 * the athlete's current result on each. Logging one is a Profile ▸ Standards
 * action; this is the reference view. Groups, their names and order come from
 * the server, so this and the Profile tab never disagree.
 */
export function StandardsLanding() {
  const { data: standards = [], isLoading } = useStandards()
  const { data: results } = useStandardResults()

  if (isLoading) return <div className="p-6"><LoadingCard /></div>

  const groups = new Map<string, { name: string; order: number; items: BenchmarkStandard[] }>()
  for (const s of standards) {
    const g = groups.get(s.category) ?? { name: s.categoryName ?? s.category, order: s.categoryOrder ?? 99, items: [] }
    g.items.push(s)
    groups.set(s.category, g)
  }
  const categories = [...groups.values()].sort((a, b) => a.order - b.order)

  return (
    <div className="h-full overflow-y-auto">
      <div className="max-w-2xl mx-auto px-8 py-12 space-y-10">
        <div className="space-y-3">
          <p className="text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium">
            Standards
          </p>
          <h2 className="text-2xl font-semibold leading-snug">{standards.length} standards.</h2>
          <p className="text-sm text-muted-foreground leading-relaxed max-w-lg">
            Entry to elite, as the source methodologies define them. Your current result sits on the
            ladder; log a new one under{' '}
            <Link to="/profile?tab=standards" className="text-primary hover:underline">Profile ▸ Standards</Link>.
          </p>
        </div>

        {categories.map(({ name, items }) => (
          <section key={name} className="space-y-3">
            <h3 className="text-xs uppercase tracking-wider text-muted-foreground/50 font-medium">
              {name}
            </h3>
            <div className="space-y-2">
              {items.map((b) => {
                const current = results?.standards[b.id]?.current
                return (
                  <div key={b.id} className="rounded-lg border border-border/30 bg-card/40 p-4 space-y-2">
                    <div className="flex items-center justify-between gap-3">
                      <div className="min-w-0">
                        <p className="text-sm font-medium truncate">{b.name}</p>
                        {b.notes && (
                          <p className="text-[11px] text-muted-foreground line-clamp-2">{b.notes}</p>
                        )}
                      </div>
                      {current ? (
                        <Link to={`/profile?tab=standards&standard=${b.id}`}
                              className="shrink-0 text-xs tabular-nums text-foreground hover:underline underline-offset-2">
                          you: <span className="font-semibold">{current.valueText}</span>{' '}
                          <StandardLevelBadge level={current.level} domain={b.domain} />
                        </Link>
                      ) : (
                        <Link
                          to={`/profile?tab=standards&standard=${b.id}`}
                          className="shrink-0 inline-flex items-center gap-1 text-[11px] text-primary hover:underline"
                        >
                          <Trophy className="size-3" aria-hidden="true" /> Log a result
                        </Link>
                      )}
                    </div>
                    <StandardLadder
                      thresholds={thresholdTexts(b.standardsText, b.standards, b.unit)}
                      levelIndex={current?.levelIndex}
                      domain={b.domain}
                    />
                  </div>
                )
              })}
            </div>
          </section>
        ))}
      </div>
    </div>
  )
}
