import { useState, useMemo } from 'react'
import { ChevronDown, ChevronRight, BookOpen, Loader2, Link2 } from 'lucide-react'
import { usePhilosophies } from '@/api/philosophies'
import { useFrameworks } from '@/api/frameworks'
import { useArchetypes } from '@/api/archetypes'
import { useExercises } from '@/api/exercises'
import { useModalities } from '@/api/modalities'
import { HeatmapPanel } from './heatmap/HeatmapPanel'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import { cn } from '@/lib/utils'
import { Badge } from '@/components/ui/badge'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import type {
  ModalityId, Modality, Philosophy, Framework,
  Archetype, ArchetypeSlot, Exercise,
} from '@/api/types'

// ─── Exercise pattern matching (mirrors selector.py) ─────────────────────────

const PATTERN_ALIASES: Record<string, { mode: 'or' | 'and' | 'category'; patterns: string[] }> = {
  squat:           { mode: 'or',       patterns: ['squat'] },
  hinge:           { mode: 'or',       patterns: ['hip_hinge'] },
  hip_hinge:       { mode: 'or',       patterns: ['hip_hinge'] },
  carry:           { mode: 'or',       patterns: ['loaded_carry'] },
  loaded_carry:    { mode: 'or',       patterns: ['loaded_carry'] },
  rotation:        { mode: 'or',       patterns: ['rotation'] },
  locomotion:      { mode: 'or',       patterns: ['locomotion'] },
  ballistic:       { mode: 'or',       patterns: ['ballistic'] },
  olympic:         { mode: 'or',       patterns: ['olympic_lift'] },
  olympic_lift:    { mode: 'or',       patterns: ['olympic_lift'] },
  isometric:       { mode: 'or',       patterns: ['isometric'] },
  horizontal_push: { mode: 'or',       patterns: ['horizontal_push'] },
  vertical_push:   { mode: 'or',       patterns: ['vertical_push'] },
  horizontal_pull: { mode: 'or',       patterns: ['horizontal_pull'] },
  vertical_pull:   { mode: 'or',       patterns: ['vertical_pull'] },
  press:           { mode: 'or',       patterns: ['horizontal_push', 'vertical_push'] },
  push:            { mode: 'or',       patterns: ['horizontal_push', 'vertical_push'] },
  pull:            { mode: 'or',       patterns: ['horizontal_pull', 'vertical_pull'] },
  aerobic:         { mode: 'or',       patterns: ['aerobic_monostructural', 'locomotion'] },
  swing:           { mode: 'and',      patterns: ['hip_hinge', 'ballistic'] },
  clean:           { mode: 'and',      patterns: ['hip_hinge', 'olympic_lift'] },
  jerk:            { mode: 'and',      patterns: ['vertical_push', 'ballistic'] },
  snatch:          { mode: 'and',      patterns: ['hip_hinge', 'ballistic', 'olympic_lift'] },
  tgu:             { mode: 'and',      patterns: ['isometric', 'vertical_push'] },
  ruck:            { mode: 'and',      patterns: ['locomotion', 'loaded_carry'] },
  skill:           { mode: 'category', patterns: ['skill'] },
  farmer_carry:    { mode: 'or',       patterns: ['farmer_carry'] },
  rack_carry:      { mode: 'or',       patterns: ['rack_carry'] },
  step_up:         { mode: 'or',       patterns: ['step_up'] },
}

function resolveAliasPatterns(key: string): string[] | null {
  const alias = PATTERN_ALIASES[key]
  if (!alias || (alias.patterns.length === 1 && alias.patterns[0] === key)) return null
  return alias.patterns
}

function exerciseMatchesSlot(ex: Exercise, slot: ArchetypeSlot): boolean {
  if (slot.skip_exercise) return false
  const filter = slot.exercise_filter
  if (!filter) return false
  const mp = filter.movement_pattern
  const cat = filter.category
  if (mp) {
    const alias = PATTERN_ALIASES[mp]
    if (!alias) return ex.movement_patterns.includes(mp)
    const { mode, patterns } = alias
    if (mode === 'or')       return patterns.some(p => ex.movement_patterns.includes(p))
    if (mode === 'and')      return patterns.every(p => ex.movement_patterns.includes(p))
    if (mode === 'category') return patterns.includes(ex.category)
  }
  if (cat) return ex.category === cat
  return false
}

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

const LEVEL_COLORS: Record<string, string> = {
  novice:       '#22c55e',
  intermediate: '#60a5fa',
  advanced:     '#f97316',
  elite:        '#ef4444',
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
                    className="text-[9px] font-mono px-1.5 py-0.5 rounded border bg-indigo-500/10 border-indigo-500/30 text-indigo-400"
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
                    <div
                      className="text-[10px] font-mono font-medium"
                      style={{ color: LEVEL_COLORS[lvl] ?? '#94a3b8' }}
                    >
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
                      <span key={u} className="text-[9px] font-mono px-1.5 py-0.5 rounded bg-emerald-500/10 border border-emerald-500/30 text-emerald-400">
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
                      <span key={f} className="text-[9px] font-mono px-1.5 py-0.5 rounded bg-orange-500/10 border border-orange-500/30 text-orange-400">
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

function SlotRow({ slot, allExercises }: { slot: ArchetypeSlot; allExercises: Exercise[] }) {
  const [open, setOpen] = useState(false)
  const [showAll, setShowAll] = useState(false)

  const matching = useMemo(
    () => allExercises.filter(ex => exerciseMatchesSlot(ex, slot)),
    [allExercises, slot],
  )

  const displayed = showAll ? matching : matching.slice(0, 8)

  const prescription = fmtSlotPrescription(slot)
  const patternKey = slot.exercise_filter?.movement_pattern
  const categoryKey = slot.exercise_filter?.category
  const patternLabel = patternKey?.replace(/_/g, ' ') ?? categoryKey?.replace(/_/g, ' ')
  const resolvedPatterns = patternKey ? resolveAliasPatterns(patternKey) : null

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
          {/* Row 2: pattern chip + resolved aliases + exercise count */}
          {patternLabel && (
            <div className="flex flex-wrap items-center gap-1.5">
              <span className="text-[9px] font-mono px-1.5 py-0.5 rounded border bg-indigo-500/10 border-indigo-500/30 text-indigo-400">
                {patternLabel}
              </span>
              {resolvedPatterns && (
                <span className="text-[9px] text-muted-foreground/50">
                  → {resolvedPatterns.map(p => p.replace(/_/g, ' ')).join(' · ')}
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
            Pattern Pool · {patternLabel} · {matching.length} matching
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

function ArchetypeCard({ archetype, allExercises }: { archetype: Archetype; allExercises: Exercise[] }) {
  const [open, setOpen] = useState(false)

  const levelInitials = (archetype.training_levels ?? []).map(l => ({
    label: LEVEL_LABELS[l] ?? l[0].toUpperCase(),
    color: LEVEL_COLORS[l] ?? '#94a3b8',
  }))

  return (
    <div className="rounded border border-border/40 bg-muted/5 overflow-hidden">
      {/* Header */}
      <button
        onClick={() => setOpen(o => !o)}
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
          {/* Level initials */}
          <div className="flex gap-0.5">
            {levelInitials.map(({ label, color }, i) => (
              <span
                key={i}
                className="text-[9px] font-mono font-semibold"
                style={{ color }}
              >
                {label}
              </span>
            ))}
          </div>
          <span className="text-[10px] text-muted-foreground/50">
            {(archetype.slots ?? []).length} slots
          </span>
        </div>
      </button>

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
                  <span
                    key={l}
                    className="text-[9px] font-mono px-1.5 py-0.5 rounded border"
                    style={{ color: LEVEL_COLORS[l] ?? '#94a3b8', borderColor: `${LEVEL_COLORS[l] ?? '#94a3b8'}40`, backgroundColor: `${LEVEL_COLORS[l] ?? '#94a3b8'}10` }}
                  >
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
              <SlotRow key={i} slot={slot} allExercises={allExercises} />
            ))}
          </div>

          {/* Archetype notes */}
          {archetype.notes && (
            <p className="text-[10px] italic text-muted-foreground/60 pt-2 border-t border-border/20">
              {archetype.notes}
            </p>
          )}
        </div>
      )}
    </div>
  )
}

// ─── ModalitySection (full card) ──────────────────────────────────────────────

function ModalitySection({
  modalityId,
  modality,
  sessionsPerWeek,
}: {
  modalityId: ModalityId
  modality: Modality | undefined
  sessionsPerWeek: number
}) {
  const [open, setOpen] = useState(true)
  const color = MODALITY_COLORS[modalityId]

  const recoveryCostColor: Record<string, string> = {
    low: '#22c55e', medium: '#eab308', high: '#ef4444',
  }

  return (
    <div className="rounded-lg border overflow-hidden" style={{ borderColor: `${color?.hex ?? '#94a3b8'}30` }}>
      {/* Header */}
      <button
        onClick={() => setOpen(o => !o)}
        className="w-full flex items-center gap-2 px-3 py-2.5 text-left transition-colors hover:bg-muted/10"
        style={{ backgroundColor: `${color?.hex ?? '#94a3b8'}08` }}
      >
        {open
          ? <ChevronDown className="size-3 shrink-0" style={{ color: color?.hex ?? '#94a3b8' }} />
          : <ChevronRight className="size-3 shrink-0" style={{ color: color?.hex ?? '#94a3b8' }} />
        }
        <span className="text-[12px] font-semibold flex-1" style={{ color: color?.hex ?? '#94a3b8' }}>
          {color?.label ?? modalityId.replace(/_/g, ' ')}
        </span>
        <div className="flex items-center gap-2 shrink-0">
          <span className="text-[10px] font-mono px-1.5 py-0.5 rounded border"
            style={{ borderColor: `${color?.hex ?? '#94a3b8'}30`, color: color?.hex ?? '#94a3b8', backgroundColor: `${color?.hex ?? '#94a3b8'}10` }}>
            {sessionsPerWeek}×/wk
          </span>
          {modality?.recovery_cost && (
            <span
              className="text-[9px] font-mono px-1 rounded"
              style={{ color: recoveryCostColor[modality.recovery_cost] ?? '#94a3b8', opacity: 0.8 }}
            >
              rec: {modality.recovery_cost}
            </span>
          )}
        </div>
      </button>

      {open && (
        <div className="border-t px-3 pb-3 pt-2.5 space-y-3" style={{ borderColor: `${color?.hex ?? '#94a3b8'}20` }}>
          {modality ? (
            <>
              {/* Description */}
              {modality.description && (
                <p className="text-[11px] text-muted-foreground leading-relaxed">{modality.description}</p>
              )}

              {/* Metadata grid */}
              <dl className="grid grid-cols-2 gap-x-4 gap-y-2">
                <div>
                  <dt className="text-[9px] uppercase tracking-wider text-muted-foreground/50">Recovery Cost</dt>
                  <dd className="text-[11px] mt-0.5 capitalize"
                    style={{ color: recoveryCostColor[modality.recovery_cost] ?? undefined }}>
                    {modality.recovery_cost}
                  </dd>
                </div>
                <div>
                  <dt className="text-[9px] uppercase tracking-wider text-muted-foreground/50">Recovery Min</dt>
                  <dd className="text-[11px] font-mono mt-0.5">{modality.recovery_hours_min}h</dd>
                </div>
                <div>
                  <dt className="text-[9px] uppercase tracking-wider text-muted-foreground/50">Session Position</dt>
                  <dd className="text-[11px] mt-0.5">{modality.session_position}</dd>
                </div>
                <div>
                  <dt className="text-[9px] uppercase tracking-wider text-muted-foreground/50">Progression Model</dt>
                  <dd className="text-[11px] font-mono mt-0.5">{modality.progression_model}</dd>
                </div>
                <div>
                  <dt className="text-[9px] uppercase tracking-wider text-muted-foreground/50">Weekly Volume</dt>
                  <dd className="text-[11px] font-mono mt-0.5">{modality.min_weekly_minutes}–{modality.max_weekly_minutes} min</dd>
                </div>
                {modality.typical_session_minutes && (
                  <div>
                    <dt className="text-[9px] uppercase tracking-wider text-muted-foreground/50">Typical Session</dt>
                    <dd className="text-[11px] font-mono mt-0.5">
                      {modality.typical_session_minutes.min}–{modality.typical_session_minutes.max} min
                    </dd>
                  </div>
                )}
              </dl>

              {/* Compatible with */}
              {modality.compatible_in_session_with?.length ? (
                <div>
                  <p className="text-[9px] uppercase tracking-wider text-muted-foreground/50 mb-1">Compatible With</p>
                  <div className="flex flex-wrap gap-1">
                    {modality.compatible_in_session_with.map(id => {
                      const c = MODALITY_COLORS[id as ModalityId]
                      return (
                        <span key={id} className="text-[9px] font-mono px-1.5 py-0.5 rounded border"
                          style={c
                            ? { borderColor: `${c.hex}40`, color: c.hex, backgroundColor: `${c.hex}10` }
                            : { borderColor: 'hsl(var(--border))' }
                          }>
                          {c?.label ?? id.replace(/_/g, ' ')}
                        </span>
                      )
                    })}
                  </div>
                </div>
              ) : null}

              {/* Incompatible with */}
              {modality.incompatible_in_session_with?.length ? (
                <div>
                  <p className="text-[9px] uppercase tracking-wider text-muted-foreground/50 mb-1">Incompatible With</p>
                  <div className="flex flex-wrap gap-1">
                    {modality.incompatible_in_session_with.map(id => (
                      <span key={id} className="text-[9px] font-mono px-1.5 py-0.5 rounded border border-orange-500/30 text-orange-400 bg-orange-500/10">
                        {id.replace(/_/g, ' ')}
                      </span>
                    ))}
                  </div>
                </div>
              ) : null}

              {/* Intensity zones */}
              {modality.intensity_zones?.length ? (
                <div>
                  <p className="text-[9px] uppercase tracking-wider text-muted-foreground/50 mb-1.5">Intensity Zones</p>
                  <div className="space-y-1">
                    {modality.intensity_zones.map((z, i) => (
                      <div key={i} className="flex items-start gap-2 text-[10px]">
                        <span className="font-mono font-medium w-16 shrink-0" style={{ color: color?.hex }}>
                          {z.label}
                        </span>
                        <span className="text-muted-foreground flex-1 min-w-0 text-[9px]">{z.description}</span>
                        {z.hr_pct_range && (
                          <span className="font-mono text-muted-foreground/60 shrink-0 text-[9px]">
                            {z.hr_pct_range[0]}–{z.hr_pct_range[1]}%
                          </span>
                        )}
                      </div>
                    ))}
                  </div>
                </div>
              ) : null}

              {/* Notes */}
              {modality.notes && (
                <p className="text-[10px] italic text-muted-foreground/60">{modality.notes}</p>
              )}

              {/* Sources */}
              {modality.sources?.length ? (
                <div className="pt-1 border-t border-border/20">
                  {modality.sources.map((s, i) => (
                    <p key={i} className="text-[9px] italic text-muted-foreground/40">{s}</p>
                  ))}
                </div>
              ) : null}
            </>
          ) : (
            <p className="text-[10px] text-muted-foreground/50 italic">Loading modality data…</p>
          )}

        </div>
      )}
    </div>
  )
}

// ─── FrameworkSection ─────────────────────────────────────────────────────────

function FrameworkSection({
  framework,
}: {
  framework: Framework
}) {
  const [open, setOpen] = useState(true)
  const modalities = Object.entries(framework.sessions_per_week ?? {}) as [ModalityId, number][]
  const intensityEntries = Object.entries(framework.intensity_distribution ?? {})

  return (
    <div className="rounded-lg border border-border bg-card">
      {/* Framework header */}
      <button
        onClick={() => setOpen(o => !o)}
        className="w-full flex items-start gap-3 px-4 py-3 text-left hover:bg-muted/10 transition-colors"
      >
        {open
          ? <ChevronDown className="size-4 text-blue-400 mt-0.5 shrink-0" />
          : <ChevronRight className="size-4 text-blue-400 mt-0.5 shrink-0" />
        }
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <span className="text-sm font-semibold text-blue-300">{framework.name}</span>
            {framework.progression_model && (
              <span className="text-[10px] font-mono px-1.5 py-0.5 rounded bg-blue-500/10 text-blue-400 border border-blue-500/20">
                {framework.progression_model.replace(/_/g, ' ')}
              </span>
            )}
          </div>
          <div className="flex flex-wrap gap-1.5 mt-1">
            {modalities.map(([mod, count]) => {
              const c = MODALITY_COLORS[mod]
              return (
                <span key={mod} className="text-[10px] font-mono px-1.5 py-0.5 rounded border"
                  style={{ borderColor: `${c?.hex ?? '#94a3b8'}30`, color: c?.hex ?? '#94a3b8', backgroundColor: `${c?.hex ?? '#94a3b8'}10` }}>
                  {c?.label ?? mod.replace(/_/g, ' ')} {count}×
                </span>
              )
            })}
          </div>
        </div>
        {framework.deload_protocol && (
          <span className="text-[10px] text-muted-foreground shrink-0 self-center">
            deload every {framework.deload_protocol.frequency_weeks}w
          </span>
        )}
      </button>

      {open && (
        <div className="px-4 pb-4 space-y-4 border-t border-border/40">
          {framework.notes && (
            <p className="text-[11px] text-muted-foreground leading-relaxed pt-3">{framework.notes}</p>
          )}

          {intensityEntries.length > 0 && (
            <div className="space-y-1.5">
              <p className="text-[10px] uppercase tracking-wider text-muted-foreground/60 font-medium">
                Intensity Distribution
              </p>
              <div className="flex gap-3 flex-wrap">
                {intensityEntries.map(([zone, pct]) => (
                  <div key={zone} className="flex items-center gap-1.5">
                    <div className="h-1.5 rounded-full bg-muted overflow-hidden w-16">
                      <div className="h-full rounded-full bg-primary/60"
                        style={{ width: `${(pct as number) * 100}%` }} />
                    </div>
                    <span className="text-[10px] font-mono text-muted-foreground">
                      {zone.replace(/_pct$/, '').replace(/_/g, ' ')}: {((pct as number) * 100).toFixed(0)}%
                    </span>
                  </div>
                ))}
              </div>
            </div>
          )}

          {framework.applicable_when && (
            <div className="text-[10px] text-muted-foreground flex flex-wrap gap-x-4 gap-y-1">
              {framework.applicable_when.days_per_week_min !== undefined && (
                <span>
                  {framework.applicable_when.days_per_week_min}–{framework.applicable_when.days_per_week_max} days/wk
                </span>
              )}
              {framework.applicable_when.training_level && (
                <span>{framework.applicable_when.training_level.join(' · ')}</span>
              )}
            </div>
          )}

          {framework.sources?.length ? (
            <div className="pt-1 border-t border-border/30 space-y-1">
              <p className="text-[10px] uppercase tracking-wider text-muted-foreground/60 font-medium">Sources</p>
              {framework.sources.map((s, i) => (
                <p key={i} className="text-[10px] text-muted-foreground/70 italic">{s}</p>
              ))}
            </div>
          ) : null}
        </div>
      )}
    </div>
  )
}

// ─── PhilosophyHeader ─────────────────────────────────────────────────────────

function PhilosophyHeader({ phil }: { phil: Philosophy }) {
  const [notesOpen, setNotesOpen] = useState(true)

  return (
    <div className="rounded-lg border border-violet-500/30 bg-violet-500/5 p-4 space-y-3">
      <div className="flex items-start justify-between gap-3 flex-wrap">
        <h2 className="text-base font-semibold text-violet-300 leading-tight">{phil.name}</h2>
        <div className="flex gap-1.5 flex-wrap shrink-0">
          {phil.intensity_model && (
            <Badge variant="outline" className="text-[10px] font-mono border-violet-500/30 text-violet-400">
              {phil.intensity_model.replace(/_/g, ' ')}
            </Badge>
          )}
          {phil.progression_philosophy && (
            <Badge variant="outline" className="text-[10px] font-mono border-violet-500/20 text-violet-500/70">
              {phil.progression_philosophy.replace(/_/g, ' ')}
            </Badge>
          )}
        </div>
      </div>

      {phil.notes && (
        <div>
          <button
            onClick={() => setNotesOpen(o => !o)}
            className="flex items-center gap-1 text-[10px] text-muted-foreground/60 hover:text-muted-foreground mb-1 transition-colors"
          >
            {notesOpen ? <ChevronDown className="size-3" /> : <ChevronRight className="size-3" />}
            Notes
          </button>
          {notesOpen && (
            <p className="text-[11px] text-muted-foreground/80 leading-relaxed">{phil.notes}</p>
          )}
        </div>
      )}

      {phil.core_principles.length > 0 && (
        <div>
          <p className="text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium mb-1.5">
            Core Principles
          </p>
          <ul className="space-y-0.5">
            {phil.core_principles.map((p, i) => (
              <li key={i} className="flex items-start gap-2 text-[11px] text-muted-foreground/80">
                <span className="text-violet-500/60 mt-0.5 shrink-0">·</span>
                {p.replace(/_/g, ' ')}
              </li>
            ))}
          </ul>
        </div>
      )}

      <div className="flex flex-wrap gap-3">
        {phil.scope.length > 0 && (
          <div className="space-y-1">
            <p className="text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium">Scope</p>
            <div className="flex flex-wrap gap-1">
              {phil.scope.map(s => (
                <span key={s} className="text-[10px] px-1.5 py-0.5 rounded bg-muted/60 text-muted-foreground font-mono">
                  {s.replace(/_/g, ' ')}
                </span>
              ))}
            </div>
          </div>
        )}
        {phil.bias.length > 0 && (
          <div className="space-y-1">
            <p className="text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium">Bias</p>
            <div className="flex flex-wrap gap-1">
              {phil.bias.map(b => {
                const c = MODALITY_COLORS[b as ModalityId]
                return (
                  <span key={b} className="text-[10px] px-1.5 py-0.5 rounded border font-mono"
                    style={c
                      ? { borderColor: `${c.hex}40`, color: c.hex, backgroundColor: `${c.hex}15` }
                      : { borderColor: 'hsl(var(--border))' }
                    }>
                    {c?.label ?? b.replace(/_/g, ' ')}
                  </span>
                )
              })}
            </div>
          </div>
        )}
      </div>

      <div className="flex flex-wrap gap-4 text-[10px] text-muted-foreground">
        {phil.required_equipment.length > 0 && (
          <div className="space-y-0.5">
            <span className="uppercase tracking-wider text-muted-foreground/50 font-medium block">Requires</span>
            <span className="font-mono">{phil.required_equipment.map(e => e.replace(/_/g, ' ')).join(', ')}</span>
          </div>
        )}
        {phil.avoid_with.length > 0 && (
          <div className="space-y-0.5">
            <span className="uppercase tracking-wider text-muted-foreground/50 font-medium block">Avoid with</span>
            <span className="font-mono text-orange-400/70">{phil.avoid_with.map(a => a.replace(/_/g, ' ')).join(', ')}</span>
          </div>
        )}
      </div>

      {(phil.system_connections.frameworks.length > 0 || phil.system_connections.goals.length > 0) && (
        <div className="flex flex-wrap gap-4 pt-2 border-t border-violet-500/20">
          {phil.system_connections.frameworks.length > 0 && (
            <div className="space-y-1">
              <div className="flex items-center gap-1 text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium">
                <Link2 className="size-3" /> Frameworks
              </div>
              <div className="flex flex-wrap gap-1">
                {phil.system_connections.frameworks.map(fw => (
                  <span key={fw} className="text-[10px] font-mono px-1.5 py-0.5 rounded bg-blue-500/10 text-blue-400 border border-blue-500/20">
                    {fw.replace(/_/g, ' ')}
                  </span>
                ))}
              </div>
            </div>
          )}
          {phil.system_connections.goals.length > 0 && (
            <div className="space-y-1">
              <div className="flex items-center gap-1 text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium">
                <Link2 className="size-3" /> Goals
              </div>
              <div className="flex flex-wrap gap-1">
                {phil.system_connections.goals.map(g => (
                  <span key={g} className="text-[10px] font-mono px-1.5 py-0.5 rounded bg-emerald-500/10 text-emerald-400 border border-emerald-500/20">
                    {g.replace(/_/g, ' ')}
                  </span>
                ))}
              </div>
            </div>
          )}
        </div>
      )}

      {phil.sources.length > 0 && (
        <div className="pt-1 border-t border-violet-500/10 space-y-0.5">
          {phil.sources.map((s, i) => (
            <p key={i} className="text-[10px] text-muted-foreground/50 italic">{s}</p>
          ))}
        </div>
      )}
    </div>
  )
}

// ─── Main panel ───────────────────────────────────────────────────────────────

export function PhilosophyExplorerPanel() {
  const { data: philosophies = [], isLoading: loadingPhil } = usePhilosophies()
  const { data: frameworksList = [] } = useFrameworks()
  const { data: archetypesList = [] } = useArchetypes()
  const { data: exercises = [] } = useExercises()
  const { data: modalitiesList = [] } = useModalities()

  const [selectedId, setSelectedId] = useState<string>('')

  const modalitiesMap = useMemo(
    () => Object.fromEntries(modalitiesList.map(m => [m.id, m])) as Record<ModalityId, Modality>,
    [modalitiesList],
  )

  const phil = useMemo(
    () => philosophies.find(p => p.id === selectedId),
    [philosophies, selectedId],
  )

  const frameworks = useMemo(
    () => frameworksList.filter(fw => fw.source_philosophy === selectedId),
    [frameworksList, selectedId],
  )

  const philosophyModalityIds = useMemo(() => {
    const ids = new Set<ModalityId>()
    for (const fw of frameworks) {
      for (const id of Object.keys(fw.sessions_per_week ?? {})) {
        ids.add(id as ModalityId)
      }
    }
    return [...ids]
  }, [frameworks])

  const modalitySessionsMap = useMemo(() => {
    const map: Record<string, number> = {}
    for (const fw of frameworks) {
      for (const [id, count] of Object.entries(fw.sessions_per_week ?? {})) {
        if (!(id in map)) map[id] = count as number
      }
    }
    return map
  }, [frameworks])

  const philosophyArchetypes = useMemo(
    () => archetypesList.filter(a => philosophyModalityIds.includes(a.modality as ModalityId)),
    [archetypesList, philosophyModalityIds],
  )

  if (loadingPhil) {
    return (
      <div className="flex items-center justify-center h-64 text-muted-foreground text-sm gap-2">
        <Loader2 className="size-4 animate-spin" />
        Loading philosophies…
      </div>
    )
  }

  return (
    <div className="flex flex-col h-full min-h-0">
      {/* ── Selector bar ── */}
      <div className="flex items-center gap-3 px-4 py-3 border-b bg-muted/10 shrink-0">
        <BookOpen className="size-4 text-violet-400 shrink-0" />
        <span className="text-xs font-medium text-muted-foreground">Philosophy</span>
        <Select value={selectedId} onValueChange={setSelectedId}>
          <SelectTrigger className="h-8 text-xs w-72">
            <SelectValue placeholder="Select a philosophy…" />
          </SelectTrigger>
          <SelectContent>
            {philosophies.map(p => (
              <SelectItem key={p.id} value={p.id} className="text-xs">
                {p.name}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        {phil && (
          <div className="flex gap-1 ml-2">
            {phil.bias.map(b => {
              const c = MODALITY_COLORS[b as ModalityId]
              return c ? (
                <div key={b} className="size-2 rounded-full" style={{ backgroundColor: c.hex }} title={c.label} />
              ) : null
            })}
          </div>
        )}
        {phil && frameworks.length > 0 && (
          <span className="text-[11px] text-muted-foreground ml-auto">
            {frameworks.length} framework{frameworks.length !== 1 ? 's' : ''}
            {' · '}
            {philosophyArchetypes.length} archetypes
          </span>
        )}
      </div>

      {!selectedId ? (
        <div className="flex flex-col items-center justify-center h-full text-muted-foreground gap-2">
          <BookOpen className="size-10 opacity-20" />
          <p className="text-sm">Select a philosophy to explore its full structure</p>
          <p className="text-xs opacity-60">frameworks → modalities → archetypes → slots → exercises</p>
        </div>
      ) : (
        <div className="flex flex-1 min-h-0 overflow-hidden">
          {/* ── Left: detail tree ── */}
          <div className="flex-1 overflow-y-auto px-4 py-4 space-y-6 min-w-0">
            {phil && <PhilosophyHeader phil={phil} />}

            {frameworks.length === 0 ? (
              <div className="rounded-lg border border-border/40 p-4 text-center text-sm text-muted-foreground">
                No frameworks linked to this philosophy
              </div>
            ) : (
              <>
                {/* Frameworks */}
                <div className="space-y-3">
                  <p className="text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium px-1">
                    Frameworks ({frameworks.length})
                  </p>
                  {frameworks.map(fw => (
                    <FrameworkSection key={fw.id} framework={fw} />
                  ))}
                </div>

                {/* Modalities */}
                {philosophyModalityIds.length > 0 && (
                  <div className="space-y-3">
                    <p className="text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium px-1">
                      Modalities ({philosophyModalityIds.length})
                    </p>
                    {philosophyModalityIds.map(modId => (
                      <ModalitySection
                        key={modId}
                        modalityId={modId}
                        modality={modalitiesMap[modId]}
                        sessionsPerWeek={modalitySessionsMap[modId] ?? 0}
                      />
                    ))}
                  </div>
                )}

                {/* Archetypes */}
                {philosophyArchetypes.length > 0 && (
                  <div className="space-y-3">
                    <p className="text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium px-1">
                      Archetypes ({philosophyArchetypes.length})
                    </p>
                    {philosophyArchetypes.map(arch => (
                      <ArchetypeCard key={arch.id} archetype={arch} allExercises={exercises} />
                    ))}
                  </div>
                )}
              </>
            )}
          </div>

          {/* ── Right: ontology graph ── */}
          <div className="w-[420px] shrink-0 border-l border-border overflow-y-auto" style={{ maxWidth: '42%' }}>
            <div className="px-3 py-2 border-b bg-muted/10">
              <p className="text-[10px] uppercase tracking-wider text-muted-foreground/60 font-medium">
                Ontology Graph
              </p>
            </div>
            <div className="px-3 py-3">
              <HeatmapPanel
                program={null}
                initialLockedNode={selectedId ? `philosophy::${selectedId}` : null}
              />
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
