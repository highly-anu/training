import { Link } from 'react-router-dom'
import { Trophy } from 'lucide-react'
import { useBenchmarks } from '@/api/benchmarks'
import { LevelBar } from '@/components/benchmarks/LevelBar'
import { LoadingCard } from '@/components/shared/LoadingCard'
import { useProfileStore } from '@/store/profileStore'
import type { BenchmarkStandard } from '@/api/types'

const CATEGORY_LABEL: Record<BenchmarkStandard['category'], string> = {
  strength: 'Strength',
  conditioning: 'Conditioning',
  cell: 'Cell standards',
}

/**
 * Explore ▸ Standards — the benchmark ladders the methodologies measure
 * against, with the athlete's own logged values on them. Logging a PR is a
 * Profile ▸ Benchmarks action; this is the reference view.
 */
export function StandardsLanding() {
  const { data: benchmarks = [], isLoading } = useBenchmarks()
  const logs = useProfileStore((s) => s.performanceLogs)

  if (isLoading) return <div className="p-6"><LoadingCard /></div>

  const categories = (['strength', 'conditioning', 'cell'] as const)
    .map((cat) => ({ cat, items: benchmarks.filter((b) => b.category === cat) }))
    .filter((g) => g.items.length > 0)

  return (
    <div className="h-full overflow-y-auto">
      <div className="max-w-2xl mx-auto px-8 py-12 space-y-10">
        <div className="space-y-3">
          <p className="text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium">
            Standards
          </p>
          <h2 className="text-2xl font-semibold leading-snug">{benchmarks.length} benchmark standards.</h2>
          <p className="text-sm text-muted-foreground leading-relaxed max-w-lg">
            Entry to elite, as the source methodologies define them. Your logged values sit on the
            ladder; log a new one under{' '}
            <Link to="/profile?tab=benchmarks" className="text-primary hover:underline">Profile ▸ Benchmarks</Link>.
          </p>
        </div>

        {categories.map(({ cat, items }) => (
          <section key={cat} className="space-y-3">
            <h3 className="text-xs uppercase tracking-wider text-muted-foreground/50 font-medium">
              {CATEGORY_LABEL[cat]}
            </h3>
            <div className="space-y-2">
              {items.map((b) => {
                const userValue = logs[b.id]?.at(-1)?.value
                return (
                  <div key={b.id} className="rounded-lg border border-border/30 bg-card/40 p-4 space-y-2">
                    <div className="flex items-center justify-between gap-3">
                      <div className="min-w-0">
                        <p className="text-sm font-medium truncate">{b.name}</p>
                        {b.notes && (
                          <p className="text-[11px] text-muted-foreground line-clamp-2">{b.notes}</p>
                        )}
                      </div>
                      {userValue != null ? (
                        <span className="shrink-0 text-xs tabular-nums text-foreground">
                          you: <span className="font-semibold">{userValue}</span> {b.unit}
                        </span>
                      ) : (
                        <Link
                          to="/profile?tab=benchmarks"
                          className="shrink-0 inline-flex items-center gap-1 text-[11px] text-primary hover:underline"
                        >
                          <Trophy className="size-3" aria-hidden="true" /> Log a PR
                        </Link>
                      )}
                    </div>
                    <LevelBar
                      standards={b.standards}
                      userValue={userValue}
                      unit={b.unit}
                      lowerIsBetter={b.lower_is_better}
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
