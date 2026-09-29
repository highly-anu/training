import type { ProgramAnalytics } from '@/api/types'
import { LevelBar } from '@/components/benchmarks/LevelBar'

const WHY_LABEL: Record<string, string> = { philosophy: 'this methodology', priority_modality: 'priority modality', declared: 'declared' }

/** The standards this program is measured by, and where the athlete stands. */
export function BenchmarkLadder({ benchmarks }: { benchmarks: ProgramAnalytics['benchmarks'] }) {
  if (benchmarks.benchmarks.length === 0) return null
  return (
    <div className="rounded-lg border bg-card p-4 space-y-4">
      <div>
        <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Standards</p>
        <p className="text-xs text-muted-foreground">
          Selected by this program's sources and priorities.
          {benchmarks.bodyweightKg != null
            ? <> Bodyweight {benchmarks.bodyweightKg} kg lets ×BW standards derive from your logged sets.</>
            : <> Log your bodyweight on the Profile page to derive ×BW standards from logged sets.</>}
        </p>
      </div>
      <div className="grid gap-3 lg:grid-cols-2">
        {benchmarks.benchmarks.map((b) => (
          <div key={b.benchmarkId} className="space-y-1.5">
            <div className="flex items-center justify-between gap-2 text-xs">
              <span className="font-medium">{b.name}</span>
              <span className="text-muted-foreground">
                {b.value != null ? <><span className="font-semibold text-foreground">{b.value}</span>{b.unit}{b.valueSource === 'derived' ? ' est.' : ''}</> : '—'}
                {b.level && <> · {b.level}</>}
                {b.next && b.gapToNext != null && <> · {b.gapToNext}{b.unit} to {b.next}</>}
              </span>
            </div>
            <LevelBar standards={b.standards as Record<'entry' | 'intermediate' | 'advanced' | 'elite', number>}
                      unit={b.unit} lowerIsBetter={b.lowerIsBetter} userValue={b.value ?? undefined} />
            <p className="text-[10px] text-muted-foreground">
              {b.why.map((w) => WHY_LABEL[w]).join(' · ')}
              {b.derived?.reason === 'no_bodyweight_logged' && ' · est. 1RM known, bodyweight not'}
            </p>
          </div>
        ))}
      </div>
    </div>
  )
}
