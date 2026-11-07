import { ArrowDown } from 'lucide-react'
import { LineagePill } from '@/components/explore/LineageSection'
import type { ExerciseProgression } from '@/lib/exploreLinks'
import { TRAINING_LEVEL_LABELS } from '@/lib/gen/clientVocab'

interface PrereqChainProps {
  name: string
  /** lib/exploreLinks.progressionOf: `requires` and `unlocks` read from both ends. */
  progression: ExerciseProgression | null
}

export function PrereqChain({ name, progression }: PrereqChainProps) {
  if (!progression) return <div className="h-10 rounded-md bg-muted/20 animate-pulse" />
  const { before, after, easier, levels } = progression
  // The lowest level it suits, per package that has it (src/level_suitability.py).
  const suits = levels.length > 0 && (
    <p className="text-[11px] text-muted-foreground">
      Suits {levels.map((l) => `${l.minLevel ? `${TRAINING_LEVEL_LABELS[l.minLevel] ?? l.minLevel} and up` : 'no level'}`
        + (levels.length > 1 ? ` (${l.label})` : '')).join(' · ')}
    </p>
  )

  if (!before.length && !after.length && !easier.length) {
    return suits || (
      <p className="text-xs text-muted-foreground">No prerequisite chain found.</p>
    )
  }

  return (
    <div className="space-y-3">
      {suits}
      <div className="flex flex-col items-center gap-1">
        {/* Comes before */}
        {before.length > 0 && (
          <div className="flex flex-wrap justify-center gap-1">
            {before.map((item) => <LineagePill key={item.id} item={item} />)}
          </div>
        )}

        {before.length > 0 && (
          <ArrowDown className="size-3.5 text-muted-foreground/50" />
        )}

        {/* Current exercise */}
        <div className="rounded-full border-2 border-primary bg-primary/10 px-3 py-1 text-xs font-semibold text-primary">
          {name}
        </div>

        {after.length > 0 && (
          <ArrowDown className="size-3.5 text-muted-foreground/50" />
        )}

        {/* Comes after */}
        {after.length > 0 && (
          <div className="flex flex-wrap justify-center gap-1">
            {after.map((item) => <LineagePill key={item.id} item={item} />)}
          </div>
        )}
      </div>

      {easier.length > 0 && (
        <div className="space-y-1">
          <p className="text-[10px] text-muted-foreground/70">Scale down to</p>
          <div className="flex flex-wrap gap-1">
            {easier.map((item) => <LineagePill key={item.id} item={item} />)}
          </div>
        </div>
      )}
    </div>
  )
}
