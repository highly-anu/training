import { useMemo } from 'react'
import { ArrowLeft } from 'lucide-react'
import { LoadingCard } from '@/components/shared/LoadingCard'
import { SimilarItems } from '@/components/shared/SimilarItems'
import { StatCell } from '@/components/explore/ExploreSection'
import { LineageSection } from '@/components/explore/LineageSection'
import { useLinkIndex } from '@/components/explore/useLineage'
import { lineageOf, prettify } from '@/lib/exploreLinks'
import { movementColor } from '@/lib/movementColors'
import type { Movement } from '@/api/types'

// The analytics groups (src/analytics/movement.ROLLUPS), in that order; a
// pattern outside them is "Other".
const ROLLUP_ORDER = ['push', 'pull', 'hinge', 'squat', 'carry', 'locomotion', 'rotation', 'isometric', 'ballistic', 'olympic']

/** Movements: the patterns exercises declare, grouped as the analytics count them. */
export function MovementLanding({ movements, isLoading, onSelect }: {
  movements: Movement[]
  isLoading: boolean
  onSelect: (id: string) => void
}) {
  const groups = useMemo(() => {
    const byRollup = new Map<string, Movement[]>()
    for (const m of movements) {
      const key = m.rollup ?? ''
      byRollup.set(key, [...(byRollup.get(key) ?? []), m])
    }
    const keys = [...ROLLUP_ORDER.filter((k) => byRollup.has(k)), ...(byRollup.has('') ? [''] : [])]
    return keys.map((k) => ({
      key: k,
      color: movementColor(k),
      items: (byRollup.get(k) ?? []).sort((a, b) => b.exerciseCount - a.exerciseCount),
    }))
  }, [movements])

  if (isLoading) return <div className="p-6"><LoadingCard /></div>

  return (
    <div className="h-full overflow-y-auto">
      <div className="max-w-3xl mx-auto px-8 py-12 space-y-8">
        <div className="space-y-3">
          <p className="text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium">
            Training ontology
          </p>
          <h2 className="text-2xl font-semibold leading-snug">{movements.length} movements.</h2>
          <p className="text-sm text-muted-foreground leading-relaxed max-w-lg">
            The movement patterns exercises are tagged with — squat, hinge, press, carry, and the rest.
            Grouped as the analytics count them. Select one to see the exercises that train it.
          </p>
        </div>

        {groups.map((g) => (
          <div key={g.key} className="space-y-2">
            <div className="flex items-center gap-1.5">
              <div className="size-1.5 rounded-full" style={{ backgroundColor: g.color.hex }} />
              <p className={`text-[10px] uppercase tracking-wider font-medium ${g.color.text}`}>{g.color.label}</p>
            </div>
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">
              {g.items.map((m) => (
                <button
                  key={m.id}
                  type="button"
                  onClick={() => onSelect(m.id)}
                  className="text-left rounded-lg border border-border/30 bg-card/40 px-3 py-2.5 transition-all
                             hover:border-primary/40 hover:shadow-sm hover:-translate-y-px hover:bg-muted/20 group"
                  style={{ borderLeftColor: g.color.hex, borderLeftWidth: 2 }}
                >
                  <p className="text-[11px] font-medium truncate group-hover:text-primary transition-colors">{m.name}</p>
                  <p className="text-[10px] text-muted-foreground/60 font-mono">
                    {m.exerciseCount} exercise{m.exerciseCount === 1 ? '' : 's'}
                  </p>
                </button>
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}

export function MovementDetail({ movement, movements, onSelect, onBack }: {
  movement: Movement
  movements: Movement[]
  onSelect: (id: string) => void
  onBack: () => void
}) {
  const { index, names, colors } = useLinkIndex()
  const lineage = useMemo(
    () => (index ? lineageOf(index, 'movements', movement.id, names, colors) : null),
    [index, movement.id, names, colors],
  )
  const philosophyCount = lineage?.up.length ?? 0
  const color = movementColor(movement.rollup)

  return (
    <div className="h-full overflow-y-auto">
      <div className="max-w-2xl mx-auto px-8 py-8 space-y-6">
        <button
          onClick={onBack}
          className="flex items-center gap-1.5 text-[11px] text-muted-foreground/60 hover:text-foreground transition-colors"
        >
          <ArrowLeft className="size-3" />
          All movements
        </button>

        {/* Name header — the group's dot and colour, as an archetype's category */}
        <div className="space-y-1.5">
          <div className="flex items-center gap-2">
            <div className="size-2.5 rounded-full shrink-0" style={{ backgroundColor: color.hex }} />
            <span className={`text-[10px] font-mono uppercase tracking-wider ${color.text}`}>
              Movement · {color.label}
            </span>
          </div>
          <h2 className="text-xl font-semibold" style={{ color: color.hex }}>{movement.name}</h2>
        </div>

        <div className="grid grid-cols-3 gap-2">
          <StatCell label="Exercises" value={`${movement.exerciseCount}`} />
          <StatCell label="Philosophies" value={lineage ? `${philosophyCount}` : '…'} />
          <StatCell label="Slot filters" value={`${movement.filterGroups.length}`} />
        </div>

        <LineageSection
          lineage={lineage}
          emptyUp="No exercise is tagged with this movement."
          emptyDown="A movement is the last level: no slot filter or analytics group names it."
        />

        <SimilarItems
          category="movement_patterns"
          id={movement.id}
          getLabel={(id) => movements.find((m) => m.id === id)?.name ?? prettify(id)}
          onSelect={onSelect}
          accentHex={color.hex}
        />
      </div>
    </div>
  )
}
