import { Plus, X } from 'lucide-react'
import { cn } from '@/lib/utils'
import { useBuilderStore } from '@/store/builderStore'
import { usePhilosophies } from '@/api/philosophies'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import { findTrack, primaryTrack, tracksOf } from '@/lib/tracks'
import { PhaseSpine } from '@/components/shared/PhaseSpine'
import type { ModalityId, Philosophy } from '@/api/types'

const SECTION_LABEL = 'text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium'

function hexOf(phil: Philosophy | undefined): string {
  return MODALITY_COLORS[(phil?.bias?.[0] ?? '') as ModalityId]?.hex ?? '#6366f1'
}

/**
 * A blend's tracks (step 2): each philosophy runs one of its tracks in its own
 * phases, at its weight; a philosophy may add another of its tracks. The
 * server composes them into one week (src/composition.py) and the preview
 * says how the days were shared and what gave way — nothing here estimates it.
 */
export function LanePicker() {
  const { lanes, updateLane, addLane, removeLane, constraints } = useBuilderStore()
  const { data: philosophies } = usePhilosophies()
  const level = constraints.training_level
  const total = lanes.reduce((s, l) => s + l.weight, 0) || 1

  const trackOf = (philosophyId: string, trackId: string | null) => {
    const phil = philosophies?.find((p) => p.id === philosophyId)
    return findTrack(phil, trackId) ?? primaryTrack(phil, level)
  }

  // A philosophy whose other tracks are not in the blend yet can add one.
  const addable = Array.from(new Set(lanes.map((l) => l.philosophyId)))
    .map((id) => philosophies?.find((p) => p.id === id))
    .filter((p): p is Philosophy => !!p)
    .map((phil) => {
      const used = new Set(lanes.filter((l) => l.philosophyId === phil.id)
        .map((l) => trackOf(phil.id, l.trackId)?.id))
      return { phil, next: tracksOf(phil).find((t) => !used.has(t.id)) }
    })
    .filter((x) => x.next)

  return (
    <section className="space-y-3">
      <div>
        <p className={SECTION_LABEL}>Periodization</p>
        <h2 className="text-sm font-semibold text-foreground mt-0.5">Training Tracks</h2>
        <p className="text-xs text-muted-foreground mt-0.5">
          Every track runs in its own phases, on your week together. Its weight is its share of your days;
          the preview shows how the week was shared and what had to give.
        </p>
      </div>

      <div className="flex rounded overflow-hidden h-2 gap-px">
        {lanes.map((lane, i) => (
          <div key={`${lane.philosophyId}-${i}`}
               style={{ flex: lane.weight / total, backgroundColor: hexOf(philosophies?.find((p) => p.id === lane.philosophyId)), opacity: 0.75 }} />
        ))}
      </div>

      <div className="grid grid-cols-1 gap-3">
        {lanes.map((lane, i) => {
          const phil = philosophies?.find((p) => p.id === lane.philosophyId)
          const track = trackOf(lane.philosophyId, lane.trackId)
          const tracks = tracksOf(phil)
          const siblings = lanes.filter((l, j) => j !== i && l.philosophyId === lane.philosophyId)
            .map((l) => trackOf(l.philosophyId, l.trackId)?.id)
          const pct = Math.round((lane.weight / total) * 100)
          const hex = hexOf(phil)
          return (
            <div key={`${lane.philosophyId}-${i}`} className="rounded-xl border border-border bg-card p-4 space-y-3">
              <div className="flex items-center justify-between gap-2">
                <div className="flex items-center gap-1.5 min-w-0">
                  <span className="size-2 rounded-full shrink-0" style={{ backgroundColor: hex }} />
                  <p className="text-xs font-semibold truncate">{phil?.name ?? lane.philosophyId}</p>
                  {track && <span className="text-[10px] text-muted-foreground truncate">· {track.name}</span>}
                </div>
                <div className="flex items-center gap-2 shrink-0">
                  <span className="text-xs font-semibold tabular-nums">{pct}%</span>
                  {siblings.length > 0 && (
                    <button onClick={() => removeLane(i)} title="Remove this track"
                            className="rounded p-0.5 text-muted-foreground hover:text-foreground hover:bg-muted">
                      <X className="size-3.5" />
                    </button>
                  )}
                </div>
              </div>

              {tracks.length > 1 && (
                <div className="flex flex-wrap gap-1.5">
                  {tracks.map((t) => {
                    const taken = siblings.includes(t.id)
                    const active = track?.id === t.id
                    return (
                      <button key={t.id} disabled={taken && !active}
                              onClick={() => updateLane(i, { trackId: t.id })}
                              className={cn('rounded-full border px-2.5 py-1 text-[10px] font-medium transition-colors',
                                active ? 'border-primary bg-primary/10 text-primary'
                                  : 'border-border text-muted-foreground hover:text-foreground hover:border-primary/50',
                                taken && !active && 'opacity-40 cursor-not-allowed')}>
                        {t.name}
                      </button>
                    )
                  })}
                </div>
              )}

              {track && <PhaseSpine phases={track.phases} />}

              <input type="range" min={5} max={95} step={5} value={lane.weight}
                     aria-label={`${phil?.name ?? lane.philosophyId} weight`}
                     onChange={(e) => updateLane(i, { weight: parseInt(e.target.value) })}
                     style={{ accentColor: hex }} className="w-full" />
            </div>
          )
        })}
      </div>

      {addable.length > 0 && (
        <div className="flex flex-wrap gap-2">
          {addable.map(({ phil, next }) => (
            <button key={phil.id} onClick={() => addLane(phil.id, next!.id)}
                    className="flex items-center gap-1 rounded-md border border-dashed border-border px-2.5 py-1.5 text-[10px] font-medium text-muted-foreground hover:text-foreground hover:border-primary/50">
              <Plus className="size-3" />
              Add another {phil.name} track
            </button>
          ))}
        </div>
      )}
    </section>
  )
}
