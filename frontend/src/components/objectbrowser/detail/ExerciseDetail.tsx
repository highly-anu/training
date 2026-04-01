import { ModalityBadge } from '@/components/shared/ModalityBadge'
import { CrossRefBadge } from '../CrossRefBadge'
import type { Exercise } from '@/api/types'
import type { NavigateToFn } from '../types'

function formatVolume(v: Record<string, unknown>): string {
  const parts: string[] = []
  const sets = v.sets as number | undefined
  const reps = v.reps as number | undefined
  const duration = (v.duration_sec as number | undefined)
  const distance = v.distance_m as number | undefined
  const ladderTop = v.ladder_top as number | undefined
  const repsTotal = v.reps_total as number | undefined

  if (ladderTop != null) {
    parts.push(`ladder 1–${ladderTop}`)
    if (repsTotal != null) parts.push(`${repsTotal} total reps`)
  } else {
    if (sets != null && reps != null) parts.push(`${sets}×${reps}`)
    else if (sets != null) parts.push(`${sets} sets`)
  }
  if (duration != null) {
    const min = Math.floor(duration / 60)
    const sec = duration % 60
    parts.push(sec === 0 ? `${min} min` : `${min}:${String(sec).padStart(2, '0')}`)
  }
  if (distance != null) parts.push(`${distance}m`)
  return parts.join(' · ') || '—'
}

interface ExerciseDetailProps {
  exercise: Exercise
  navigateTo: NavigateToFn
}

function Field({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div>
      <dt className="text-[10px] text-muted-foreground uppercase tracking-wider">{label}</dt>
      <dd className="text-sm mt-0.5">{value}</dd>
    </div>
  )
}

function Pills({ items }: { items: string[] }) {
  if (!items?.length) return <span className="text-sm text-muted-foreground">—</span>
  return (
    <div className="flex flex-wrap gap-1">
      {items.map(item => (
        <span key={item} className="px-2 py-0.5 rounded text-xs bg-muted border border-border font-mono">
          {item}
        </span>
      ))}
    </div>
  )
}

export function ExerciseDetail({ exercise: ex, navigateTo }: ExerciseDetailProps) {
  return (
    <div className="space-y-5">
      <div>
        <h2 className="text-base font-semibold">{ex.name}</h2>
        <p className="text-xs text-muted-foreground font-mono mt-0.5">{ex.id}</p>
      </div>

      {/* Metadata grid */}
      <dl className="grid grid-cols-2 gap-3">
        <Field label="Category" value={ex.category} />
        <Field label="Effort" value={ex.effort} />
        <Field label="Bilateral" value={ex.bilateral ? 'Yes' : 'No'} />
        {ex.typical_volume && (
          <Field label="Typical Volume" value={formatVolume(ex.typical_volume as Record<string, unknown>)} />
        )}
      </dl>

      {/* Modalities */}
      <div>
        <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-1.5">Modalities</p>
        {ex.modality?.length ? (
          <div className="flex flex-wrap gap-1">
            {ex.modality.map(m => (
              <button key={m} onClick={() => navigateTo('modalities', m)}>
                <ModalityBadge modality={m} />
              </button>
            ))}
          </div>
        ) : (
          <span className="text-sm text-muted-foreground">—</span>
        )}
      </div>

      {/* Equipment */}
      <div>
        <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-1.5">Equipment</p>
        <Pills items={ex.equipment ?? []} />
      </div>

      {/* Movement patterns */}
      <div>
        <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-1.5">Movement Patterns</p>
        <Pills items={ex.movement_patterns ?? []} />
      </div>

      {/* Progressions */}
      {ex.progressions && Object.keys(ex.progressions).length > 0 && (
        <div>
          <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-1.5">Progressions</p>
          <dl className="space-y-1 text-xs">
            {Object.entries(ex.progressions).map(([key, val]) => (
              <div key={key}>
                <span className="text-muted-foreground capitalize">{key}: </span>
                {String(val).replace(/_/g, ' ')}
              </div>
            ))}
          </dl>
        </div>
      )}

      {/* Scaling */}
      {ex.scaling_down?.length ? (
        <div>
          <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-1.5">Scaling Down</p>
          <ul className="text-xs space-y-0.5 list-disc list-inside text-muted-foreground">
            {ex.scaling_down.map((s, i) => <li key={i}>{s}</li>)}
          </ul>
        </div>
      ) : null}

      {/* Related objects */}
      <div className="space-y-3 pt-2 border-t">
        <p className="text-[10px] font-semibold text-muted-foreground uppercase tracking-wider">Related</p>

        {ex.requires?.length ? (
          <div>
            <p className="text-xs text-muted-foreground mb-1">Requires</p>
            <div className="flex flex-wrap gap-1">
              {ex.requires.map(r => (
                <CrossRefBadge key={r} label={r} type="exercises" id={r} navigateTo={navigateTo} />
              ))}
            </div>
          </div>
        ) : null}

        {ex.unlocks?.length ? (
          <div>
            <p className="text-xs text-muted-foreground mb-1">Unlocks</p>
            <div className="flex flex-wrap gap-1">
              {ex.unlocks.map(u => (
                <CrossRefBadge key={u} label={u} type="exercises" id={u} navigateTo={navigateTo} />
              ))}
            </div>
          </div>
        ) : null}

        {ex.contraindicated_with?.length ? (
          <div>
            <p className="text-xs text-muted-foreground mb-1">Contraindicated with</p>
            <div className="flex flex-wrap gap-1">
              {ex.contraindicated_with.map(f => (
                <CrossRefBadge key={f} label={f} type="injuryFlags" id={f} navigateTo={navigateTo} />
              ))}
            </div>
          </div>
        ) : null}
      </div>

      {/* Notes */}
      {ex.notes && (
        <div className="pt-2 border-t">
          <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-1.5">Notes</p>
          <p className="text-xs text-muted-foreground">{ex.notes}</p>
        </div>
      )}
    </div>
  )
}
