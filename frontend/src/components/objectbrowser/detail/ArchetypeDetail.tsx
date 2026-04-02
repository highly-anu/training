import { Network } from 'lucide-react'
import { PhaseBadge } from '@/components/shared/PhaseBadge'
import { CrossRefBadge } from '../CrossRefBadge'
import type { Archetype } from '@/api/types'
import type { NavigateToFn, OpenInOntologyFn } from '../types'

interface ArchetypeDetailProps {
  archetype: Archetype
  navigateTo: NavigateToFn
  onOpenInOntology?: OpenInOntologyFn
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

export function ArchetypeDetail({ archetype: a, navigateTo, onOpenInOntology }: ArchetypeDetailProps) {
  return (
    <div className="space-y-5">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h2 className="text-base font-semibold">{a.name}</h2>
          <p className="text-xs text-muted-foreground font-mono mt-0.5">{a.id}</p>
        </div>
        {onOpenInOntology && (
          <button
            onClick={() => onOpenInOntology(`archetype::${a.id}`)}
            className="shrink-0 flex items-center gap-1 text-[11px] text-muted-foreground hover:text-foreground transition-colors"
          >
            <Network className="size-3" />
            Ontology
          </button>
        )}
      </div>

      {/* Metadata */}
      <dl className="grid grid-cols-2 gap-3 text-sm">
        <div>
          <dt className="text-[10px] text-muted-foreground uppercase tracking-wider">Modality</dt>
          <dd className="mt-0.5">
            <CrossRefBadge label={a.modality} type="modalities" id={a.modality} navigateTo={navigateTo} />
          </dd>
        </div>
        <div>
          <dt className="text-[10px] text-muted-foreground uppercase tracking-wider">Category</dt>
          <dd className="mt-0.5">{a.category}</dd>
        </div>
        <div>
          <dt className="text-[10px] text-muted-foreground uppercase tracking-wider">Duration</dt>
          <dd className="mt-0.5">{a.duration_estimate_minutes} min</dd>
        </div>
      </dl>

      {/* Levels & Phases */}
      <div>
        <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-1.5">Training Levels</p>
        <Pills items={a.training_levels ?? []} />
      </div>

      <div>
        <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-1.5">Applicable Phases</p>
        <div className="flex flex-wrap gap-1">
          {(a.applicable_phases ?? []).map(p => (
            <PhaseBadge key={p} phase={p} />
          ))}
        </div>
      </div>

      {/* Equipment */}
      <div>
        <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-1.5">Required Equipment</p>
        <Pills items={a.required_equipment ?? []} />
      </div>

      {/* Slots */}
      {a.slots?.length ? (
        <div>
          <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-2">Slots</p>
          <div className="space-y-2">
            {a.slots.map((slot, i) => (
              <div key={i} className="rounded border bg-muted/30 p-2.5 text-xs space-y-1">
                <div className="flex items-center justify-between">
                  <span className="font-medium font-mono">{slot.role}</span>
                  <span className="text-muted-foreground">{slot.slot_type}</span>
                </div>
                <div className="flex flex-wrap gap-x-4 gap-y-0.5 text-muted-foreground">
                  {slot.sets != null && slot.reps != null && (
                    <span>{slot.sets}×{slot.reps}</span>
                  )}
                  {(slot as unknown as Record<string, unknown>).duration_sec != null && (
                    <span>{Math.floor(((slot as unknown as Record<string, unknown>).duration_sec as number) / 60) > 0 ? `${Math.floor(((slot as unknown as Record<string, unknown>).duration_sec as number) / 60)}min` : `${(slot as unknown as Record<string, unknown>).duration_sec as number}s`}</span>
                  )}
                  {(slot as unknown as Record<string, unknown>).distance_m != null && (
                    <span>{(slot as unknown as Record<string, unknown>).distance_m as number}m</span>
                  )}
                  {(slot as unknown as Record<string, unknown>).intensity != null && (
                    <span>@ {String((slot as unknown as Record<string, unknown>).intensity)}</span>
                  )}
                  {(slot as unknown as Record<string, unknown>).intensity_pct_1rm != null && (
                    <span>{Math.round(((slot as unknown as Record<string, unknown>).intensity_pct_1rm as number) * 100)}% 1RM</span>
                  )}
                  {(slot as unknown as Record<string, unknown>).rest_sec != null && (
                    <span>rest {(slot as unknown as Record<string, unknown>).rest_sec as number}s</span>
                  )}
                </div>
                {slot.notes && (
                  <p className="text-muted-foreground italic">{slot.notes}</p>
                )}
              </div>
            ))}
          </div>
        </div>
      ) : null}

      {/* Sources */}
      {a.sources?.length ? (
        <div className="pt-2 border-t">
          <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-1.5">Sources</p>
          <Pills items={a.sources} />
        </div>
      ) : null}
    </div>
  )
}
