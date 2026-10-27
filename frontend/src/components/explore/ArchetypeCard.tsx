import { useMemo, useState } from 'react'
import { ChevronDown, ChevronRight } from 'lucide-react'
import { useExploreLinks } from '@/api/exploreLinks'
import { SimilarItems } from '@/components/shared/SimilarItems'
import { cn } from '@/lib/utils'
import type { Archetype, ArchetypeSlot, Exercise } from '@/api/types'

/**
 * One archetype in full — its phases, levels, equipment, scaling, sources and
 * slots, each slot's exercises expandable (Explore ▸ Archetypes' detail).
 */

// ─── Formatters ───────────────────────────────────────────────────────────────

function formatVolume(v: Record<string, unknown>): string {
  const parts: string[] = []
  const sets = v.sets as number | undefined
  const reps = v.reps as number | undefined
  const duration = v.duration_sec as number | undefined
  const distance = v.distance_m as number | undefined
  const ladderTop = v.ladder_top as number | undefined
  const repsTotal = v.reps_total as number | undefined
  if (ladderTop != null) {
    parts.push(`ladder 1–${ladderTop}`)
    if (repsTotal != null) parts.push(`${repsTotal} total`)
  } else {
    if (sets != null && reps != null) parts.push(`${sets}×${reps}`)
    else if (sets != null) parts.push(`${sets} sets`)
  }
  if (duration != null) {
    const min = Math.floor(duration / 60)
    const sec = duration % 60
    parts.push(sec === 0 ? `${min}min` : `${min}:${String(sec).padStart(2, '0')}`)
  }
  if (distance != null) parts.push(`${distance}m`)
  return parts.join(' · ') || '—'
}

function fmtSlotPrescription(slot: ArchetypeSlot): string {
  const parts: string[] = []
  if (slot.sets && slot.reps)         parts.push(`${slot.sets}×${slot.reps}`)
  else if (slot.sets)                  parts.push(`${slot.sets} sets`)
  if (slot.duration_sec != null) {
    const min = Math.floor(slot.duration_sec / 60)
    const sec = slot.duration_sec % 60
    parts.push(sec === 0 ? `${min}min` : `${min}:${String(sec).padStart(2, '0')}`)
  }
  if (slot.distance_m != null)         parts.push(`${slot.distance_m}m`)
  if (slot.intensity)                  parts.push(slot.intensity)
  if (slot.intensity_pct_1rm != null)  parts.push(`${Math.round(slot.intensity_pct_1rm * 100)}% 1RM`)
  if (slot.rest_sec != null)           parts.push(`${slot.rest_sec}s rest`)
  return parts.join('  ·  ')
}

// ─── Effort coloring ──────────────────────────────────────────────────────────

const EFFORT_COLORS: Record<string, string> = {
  low:    '#22c55e',
  medium: '#eab308',
  high:   '#f97316',
  max:    '#ef4444',
}

const LEVEL_LABELS: Record<string, string> = {
  novice:       'N',
  intermediate: 'I',
  advanced:     'A',
  elite:        'E',
}


// ─── ExerciseCard ─────────────────────────────────────────────────────────────

function ExerciseCard({ exercise: ex }: { exercise: Exercise }) {
  const [open, setOpen] = useState(false)

  const effortColor = EFFORT_COLORS[ex.effort] ?? '#94a3b8'
  const loadEntries = Object.entries(ex.starting_load_kg ?? {})
  const volStr = ex.typical_volume
    ? formatVolume(ex.typical_volume as Record<string, unknown>)
    : null
  const loadStr = loadEntries.length
    ? loadEntries.slice(0, 2).map(([l, kg]) => `${LEVEL_LABELS[l] ?? l}: ${kg}kg`).join('  ')
    : null

  return (
    <div className="rounded border border-border/30 bg-background/50 overflow-hidden">
      {/* Collapsed row */}
      <button
        onClick={() => setOpen(o => !o)}
        className="w-full flex items-center gap-2 px-2.5 py-1.5 text-left hover:bg-muted/20 transition-colors"
      >
        <div
          className="size-1.5 rounded-full shrink-0"
          style={{ backgroundColor: effortColor }}
        />
        <span className="text-[11px] flex-1 truncate min-w-0">{ex.name}</span>
        <div className="flex items-center gap-2 shrink-0 text-[10px]">
          <span className="font-mono" style={{ color: effortColor }}>{ex.effort}</span>
          {ex.bilateral && <span className="text-muted-foreground/60">⇄</span>}
          {volStr && <span className="font-mono text-muted-foreground">{volStr}</span>}
          {loadStr && <span className="font-mono text-primary/60">{loadStr}</span>}
        </div>
        {open
          ? <ChevronDown className="size-3 text-muted-foreground/50 shrink-0" />
          : <ChevronRight className="size-3 text-muted-foreground/50 shrink-0" />
        }
      </button>

      {/* Expanded body */}
      {open && (
        <div className="px-3 pb-3 pt-2 border-t border-border/20 space-y-3">
          <p className="text-[9px] font-mono text-muted-foreground/50">{ex.id}</p>

          {/* Metadata grid */}
          <dl className="grid grid-cols-2 gap-x-4 gap-y-2">
            <div>
              <dt className="text-[9px] uppercase tracking-wider text-muted-foreground/50">Category</dt>
              <dd className="text-[11px] font-mono mt-0.5">{ex.category}</dd>
            </div>
            <div>
              <dt className="text-[9px] uppercase tracking-wider text-muted-foreground/50">Effort</dt>
              <dd className="text-[11px] font-mono mt-0.5" style={{ color: effortColor }}>{ex.effort}</dd>
            </div>
            <div>
              <dt className="text-[9px] uppercase tracking-wider text-muted-foreground/50">Bilateral</dt>
              <dd className="text-[11px] mt-0.5">{ex.bilateral ? 'Yes ⇄' : 'No'}</dd>
            </div>
            {volStr && volStr !== '—' && (
              <div>
                <dt className="text-[9px] uppercase tracking-wider text-muted-foreground/50">Typical Volume</dt>
                <dd className="text-[11px] font-mono mt-0.5">{volStr}</dd>
              </div>
            )}
            {ex.weekly_increment_kg != null && (
              <div>
                <dt className="text-[9px] uppercase tracking-wider text-muted-foreground/50">Weekly Increment</dt>
                <dd className="text-[11px] font-mono mt-0.5">{ex.weekly_increment_kg}kg/wk</dd>
              </div>
            )}
          </dl>

          {/* Equipment */}
          {ex.equipment?.length > 0 && (
            <div>
              <p className="text-[9px] uppercase tracking-wider text-muted-foreground/50 mb-1">Equipment</p>
              <div className="flex flex-wrap gap-1">
                {ex.equipment.map(e => (
                  <span key={e} className="text-[9px] font-mono px-1.5 py-0.5 rounded bg-muted border border-border/40">
                    {e.replace(/_/g, ' ')}
                  </span>
                ))}
              </div>
            </div>
          )}

          {/* Movement patterns */}
          {ex.movement_patterns?.length > 0 && (
            <div>
              <p className="text-[9px] uppercase tracking-wider text-muted-foreground/50 mb-1">Movement Patterns</p>
              <div className="flex flex-wrap gap-1">
                {ex.movement_patterns.map(p => (
                  <span
                    key={p}
                    className="text-[9px] font-mono px-1.5 py-0.5 rounded border bg-indigo-500/10 border-indigo-500/30 text-indigo-700 dark:text-indigo-300"
                  >
                    {p.replace(/_/g, ' ')}
                  </span>
                ))}
              </div>
            </div>
          )}

          {/* Starting loads */}
          {loadEntries.length > 0 && (
            <div>
              <p className="text-[9px] uppercase tracking-wider text-muted-foreground/50 mb-1">Starting Loads</p>
              <div className="flex gap-3">
                {loadEntries.map(([lvl, kg]) => (
                  <div key={lvl} className="text-center">
                    <div className="text-[9px] text-muted-foreground/60 font-mono">
                      {LEVEL_LABELS[lvl] ?? lvl}
                    </div>
                    <div className="text-[10px] font-mono font-medium">
                      {kg}kg
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Progressions */}
          {ex.progressions && Object.keys(ex.progressions).length > 0 && (
            <div>
              <p className="text-[9px] uppercase tracking-wider text-muted-foreground/50 mb-1">Progressions</p>
              <dl className="space-y-0.5">
                {Object.entries(ex.progressions).map(([k, v]) => (
                  <div key={k} className="text-[10px]">
                    <span className="text-muted-foreground/60 capitalize">{k}: </span>
                    <span className="italic text-muted-foreground">{String(v).replace(/_/g, ' ')}</span>
                  </div>
                ))}
              </dl>
            </div>
          )}

          {/* Scaling down */}
          {ex.scaling_down?.length ? (
            <div>
              <p className="text-[9px] uppercase tracking-wider text-muted-foreground/50 mb-1">Scaling Down</p>
              <div className="flex flex-wrap gap-1">
                {ex.scaling_down.map(s => (
                  <span key={s} className="text-[9px] font-mono px-1.5 py-0.5 rounded bg-muted border border-border/40">
                    {s.replace(/_/g, ' ')}
                  </span>
                ))}
              </div>
            </div>
          ) : null}

          {/* Relations */}
          {(ex.requires?.length || ex.unlocks?.length || ex.contraindicated_with?.length) ? (
            <div className="space-y-1.5 pt-2 border-t border-border/20">
              {ex.requires?.length ? (
                <div>
                  <p className="text-[9px] text-muted-foreground/50 mb-0.5">Requires</p>
                  <div className="flex flex-wrap gap-1">
                    {ex.requires.map(r => (
                      <span key={r} className="text-[9px] font-mono px-1.5 py-0.5 rounded bg-muted border border-border/40">
                        {r.replace(/_/g, ' ')}
                      </span>
                    ))}
                  </div>
                </div>
              ) : null}
              {ex.unlocks?.length ? (
                <div>
                  <p className="text-[9px] text-muted-foreground/50 mb-0.5">Unlocks</p>
                  <div className="flex flex-wrap gap-1">
                    {ex.unlocks.map(u => (
                      <span key={u} className="text-[9px] font-mono px-1.5 py-0.5 rounded bg-emerald-500/10 border border-emerald-500/30 text-emerald-700 dark:text-emerald-300">
                        {u.replace(/_/g, ' ')}
                      </span>
                    ))}
                  </div>
                </div>
              ) : null}
              {ex.contraindicated_with?.length ? (
                <div>
                  <p className="text-[9px] text-muted-foreground/50 mb-0.5">Contraindicated with</p>
                  <div className="flex flex-wrap gap-1">
                    {ex.contraindicated_with.map(f => (
                      <span key={f} className="text-[9px] font-mono px-1.5 py-0.5 rounded bg-orange-500/10 border border-orange-500/30 text-orange-700 dark:text-orange-300">
                        {f.replace(/_/g, ' ')}
                      </span>
                    ))}
                  </div>
                </div>
              ) : null}
            </div>
          ) : null}

          {/* Notes */}
          {ex.notes && (
            <p className="text-[10px] italic text-muted-foreground/60 pt-2 border-t border-border/20">
              {ex.notes}
            </p>
          )}
        </div>
      )}
    </div>
  )
}

// ─── SlotRow ──────────────────────────────────────────────────────────────────

function SlotRow({ slot, matching }: { slot: ArchetypeSlot; matching: Exercise[] }) {
  const [open, setOpen] = useState(false)
  const [showAll, setShowAll] = useState(false)

  const displayed = showAll ? matching : matching.slice(0, 8)

  const prescription = fmtSlotPrescription(slot)
  const patternKey = slot.exercise_filter?.movement_pattern
  const categoryKey = slot.exercise_filter?.category
  const patternLabel = patternKey?.replace(/_/g, ' ') ?? categoryKey?.replace(/_/g, ' ')
  const listed = (slot.exercise_filter?.exercise_ids?.length ?? 0) > 0

  if (slot.skip_exercise) {
    return (
      <div className="pl-3 ml-2 border-l border-border/30 py-1.5">
        <div className="flex items-center gap-2">
          <span className="text-[11px] font-mono text-foreground/60">{slot.role}</span>
          {slot.slot_type && (
            <span className="text-[9px] font-mono px-1 rounded border border-border/40 text-muted-foreground">
              {slot.slot_type}
            </span>
          )}
          <span className="text-[10px] text-muted-foreground/50 italic">technique / no exercise</span>
        </div>
        {slot.notes && (
          <p className="text-[10px] italic text-muted-foreground/50 mt-0.5 pl-0">{slot.notes}</p>
        )}
      </div>
    )
  }

  return (
    <div className="pl-3 ml-2 border-l border-border/30">
      {/* Header */}
      <button
        onClick={() => matching.length > 0 && setOpen(o => !o)}
        className={cn(
          'w-full flex items-start gap-2 py-1.5 text-left group',
          matching.length > 0 ? 'cursor-pointer' : 'cursor-default',
        )}
      >
        <span className="mt-0.5 shrink-0 text-muted-foreground/40">
          {matching.length > 0
            ? (open ? <ChevronDown className="size-3" /> : <ChevronRight className="size-3" />)
            : <span className="text-[10px]">·</span>
          }
        </span>
        <div className="flex-1 min-w-0 space-y-0.5">
          {/* Row 1: role + slot_type + prescription */}
          <div className="flex flex-wrap items-baseline gap-x-2 gap-y-0.5">
            <span className="text-[11px] font-mono text-foreground/80">{slot.role}</span>
            {slot.slot_type && (
              <span className="text-[9px] font-mono px-1 rounded border border-border/40 text-muted-foreground">
                {slot.slot_type.replace(/_/g, ' ')}
              </span>
            )}
            {prescription && (
              <span className="text-[10px] font-mono text-primary/80">{prescription}</span>
            )}
          </div>
          {/* Row 2: pattern chip + exercise count */}
          {(patternLabel || listed) && (
            <div className="flex flex-wrap items-center gap-1.5">
              {patternLabel && (
                <span className="text-[9px] font-mono px-1.5 py-0.5 rounded border bg-indigo-500/10 border-indigo-500/30 text-indigo-700 dark:text-indigo-300">
                  {patternLabel}
                </span>
              )}
              {matching.length > 0 && (
                <span className="text-[9px] text-muted-foreground/50">
                  ({matching.length} exercises)
                </span>
              )}
            </div>
          )}
          {/* Slot notes — always visible */}
          {slot.notes && (
            <p className="text-[10px] italic text-muted-foreground/50">{slot.notes}</p>
          )}
        </div>
      </button>

      {/* Expanded exercise list */}
      {open && matching.length > 0 && (
        <div className="pb-2 pl-5 space-y-1">
          <p className="text-[9px] uppercase tracking-wider text-muted-foreground/40 mb-1.5">
            {listed ? 'Named by the slot' : `Pattern pool · ${patternLabel}`} · {matching.length}
          </p>
          {displayed.map(ex => (
            <ExerciseCard key={ex.id} exercise={ex} />
          ))}
          {matching.length > 8 && (
            <button
              onClick={() => setShowAll(s => !s)}
              className="text-[10px] text-muted-foreground/60 hover:text-muted-foreground transition-colors pl-1"
            >
              {showAll ? '↑ Show fewer' : `↓ Show all ${matching.length}`}
            </button>
          )}
        </div>
      )}
    </div>
  )
}

// ─── ArchetypeCard ────────────────────────────────────────────────────────────

export function ArchetypeCard({ archetype, allExercises, allArchetypes, isOpen, onToggle, onSelectArchetype, alwaysOpen }: { archetype: Archetype; allExercises: Exercise[]; allArchetypes: Archetype[]; isOpen: boolean; onToggle: () => void; onSelectArchetype?: (id: string) => void; alwaysOpen?: boolean }) {
  const open = alwaysOpen || isOpen
  // Each slot's exercises by the selector's own rule, from the server
  // (src/explore_links.py): the client's copy of it never read `exercise_ids`,
  // which almost every slot uses.
  const { data: links } = useExploreLinks()
  const bySlot = useMemo(() => {
    const byId = new Map(allExercises.map((e) => [e.id, e]))
    const out: Record<string, Exercise[]> = {}
    for (const edge of links?.links.archetypeExercise ?? []) {
      if (edge.archetype !== archetype.id) continue
      const ex = byId.get(edge.exercise)
      if (!ex) continue
      for (const role of edge.slots) (out[role] ??= []).push(ex)
    }
    return out
  }, [links, allExercises, archetype.id])

  const levelInitials = (archetype.training_levels ?? []).map(l => LEVEL_LABELS[l] ?? l[0].toUpperCase())

  return (
    <div className="rounded border border-border/40 bg-muted/5 overflow-hidden">
      {/* Header */}
      {!alwaysOpen && (
        <button
          onClick={onToggle}
          className="w-full flex items-center gap-2 px-3 py-2 text-left hover:bg-muted/20 transition-colors"
        >
          {open
            ? <ChevronDown className="size-3 text-muted-foreground shrink-0" />
            : <ChevronRight className="size-3 text-muted-foreground shrink-0" />
          }
          <span className="text-[11px] font-medium flex-1 truncate min-w-0">{archetype.name}</span>
          <div className="flex items-center gap-2 shrink-0">
            <span className="text-[9px] font-mono px-1.5 py-0.5 rounded bg-muted text-muted-foreground">
              {archetype.category}
            </span>
            <span className="text-[10px] font-mono text-muted-foreground">
              {archetype.duration_estimate_minutes}min
            </span>
            <div className="flex gap-0.5">
              {levelInitials.map((label, i) => (
                <span key={i} className="text-[9px] font-mono font-semibold text-muted-foreground">{label}</span>
              ))}
            </div>
            <span className="text-[10px] text-muted-foreground/50">
              {(archetype.slots ?? []).length} slots
            </span>
          </div>
        </button>
      )}

      {/* Expanded body */}
      {open && (
        <div className="border-t border-border/30 px-3 pb-3 pt-2.5 space-y-3">
          {/* Section A — metadata */}
          <div className="space-y-2">
            <div>
              <p className="text-[9px] uppercase tracking-wider text-muted-foreground/50 mb-1">Phases</p>
              <div className="flex flex-wrap gap-1">
                {(archetype.applicable_phases ?? []).map(p => (
                  <span key={p} className="text-[9px] font-mono px-1.5 py-0.5 rounded bg-muted text-muted-foreground">
                    {p}
                  </span>
                ))}
              </div>
            </div>
            <div>
              <p className="text-[9px] uppercase tracking-wider text-muted-foreground/50 mb-1">Levels</p>
              <div className="flex flex-wrap gap-1">
                {(archetype.training_levels ?? []).map(l => (
                  <span key={l} className="text-[9px] font-mono px-1.5 py-0.5 rounded border border-border/50 text-muted-foreground">
                    {l}
                  </span>
                ))}
              </div>
            </div>
            {(archetype.required_equipment ?? []).length > 0 && (
              <div>
                <p className="text-[9px] uppercase tracking-wider text-muted-foreground/50 mb-1">Equipment</p>
                <div className="flex flex-wrap gap-1">
                  {(archetype.required_equipment ?? []).map(e => (
                    <span key={e} className="text-[9px] font-mono px-1.5 py-0.5 rounded bg-muted border border-border/40 text-muted-foreground">
                      {e.replace(/_/g, ' ')}
                    </span>
                  ))}
                </div>
              </div>
            )}
          </div>

          {/* Section B — Scaling */}
          {archetype.scaling && Object.values(archetype.scaling).some(Boolean) && (
            <div className="pt-2 border-t border-border/20">
              <p className="text-[9px] uppercase tracking-wider text-muted-foreground/50 mb-1">Scaling</p>
              <dl className="space-y-1.5">
                {Object.entries(archetype.scaling).map(([k, v]) => {
                  if (!v) return null
                  const notes = typeof v === 'string'
                    ? v
                    : (v as Record<string, unknown>).notes as string | undefined
                  return (
                    <div key={k}>
                      <dt className="text-[9px] font-mono text-muted-foreground/60 capitalize">
                        {k.replace(/_/g, ' ')}
                      </dt>
                      {notes && (
                        <dd className="text-[10px] italic text-muted-foreground/70 pl-2 mt-0.5">{notes}</dd>
                      )}
                    </div>
                  )
                })}
              </dl>
            </div>
          )}

          {/* Section C — Sources */}
          {archetype.sources?.length > 0 && (
            <div className="pt-1 border-t border-border/20">
              {archetype.sources.map((s, i) => (
                <p key={i} className="text-[9px] italic text-muted-foreground/40">{s}</p>
              ))}
            </div>
          )}

          {/* Section D — Slots */}
          <div className="pt-1 border-t border-border/20 space-y-0.5">
            <p className="text-[9px] uppercase tracking-wider text-muted-foreground/50 mb-1.5">
              Slots ({(archetype.slots ?? []).length})
            </p>
            {(archetype.slots ?? []).map((slot, i) => (
              <SlotRow key={i} slot={slot} matching={bySlot[slot.role] ?? []} />
            ))}
          </div>

          {/* Archetype notes */}
          {archetype.notes && (
            <p className="text-[10px] italic text-muted-foreground/60 pt-2 border-t border-border/20">
              {archetype.notes}
            </p>
          )}

          {/* Similar archetypes */}
          <div className="pt-2 border-t border-border/20">
            <SimilarItems
              category="archetypes"
              id={archetype.id}
              getLabel={(id) => allArchetypes.find(a => a.id === id)?.name ?? id}
              onSelect={onSelectArchetype}
              count={4}
            />
          </div>
        </div>
      )}
    </div>
  )
}

