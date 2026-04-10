import { useState } from 'react'
import { useOntology } from '@/api/ontology'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import { ModalityBadge } from '@/components/shared/ModalityBadge'
import type { TracedProgram, WeekTrace, SessionTrace, ModalityId } from '@/api/types'

// ─── Props ────────────────────────────────────────────────────────────────────

interface Props {
  program: TracedProgram
  weeks: WeekTrace[]
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

const DAY_NAMES = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']

function Label({ children }: { children: React.ReactNode }) {
  return (
    <span className="text-[10px] uppercase tracking-wider text-muted-foreground/60">
      {children}
    </span>
  )
}

function Mono({ children }: { children: React.ReactNode }) {
  return <span className="font-mono text-[10px]">{children}</span>
}

function ReadOutputRow({ reads, outputs }: { reads: string[]; outputs: string[] }) {
  return (
    <div className="flex flex-wrap gap-x-6 gap-y-1 px-3 py-2 bg-muted/30 rounded-b border-t border-border/30 mt-2">
      <div className="flex items-start gap-2">
        <Label>reads</Label>
        <div className="flex flex-wrap gap-1">
          {reads.map(r => (
            <span key={r} className="px-1.5 py-0.5 rounded bg-muted text-[10px] font-mono text-muted-foreground">{r}</span>
          ))}
        </div>
      </div>
      <div className="flex items-start gap-2">
        <Label>outputs</Label>
        <div className="flex flex-wrap gap-1">
          {outputs.map(o => (
            <span key={o} className="px-1.5 py-0.5 rounded bg-primary/10 text-[10px] font-mono text-primary/70">{o}</span>
          ))}
        </div>
      </div>
    </div>
  )
}

function Connector({ label }: { label: string }) {
  return (
    <div className="flex items-center gap-2 pl-4 py-1">
      <div className="w-px h-4 bg-border" />
      <span className="text-[10px] text-muted-foreground">↓ {label}</span>
    </div>
  )
}

function Block({
  color,
  label,
  children,
  reads,
  outputs,
}: {
  color: string
  label: string
  children: React.ReactNode
  reads: string[]
  outputs: string[]
}) {
  return (
    <div className={`rounded-lg border border-border/50 border-l-2 overflow-hidden ${color}`}>
      <div className="px-3 pt-2 pb-1">
        <Label>{label}</Label>
        <div className="mt-1.5 space-y-1.5">{children}</div>
      </div>
      <ReadOutputRow reads={reads} outputs={outputs} />
    </div>
  )
}

function Placeholder({ text }: { text: string }) {
  return <p className="text-[10px] text-muted-foreground/50 italic">{text}</p>
}

function formatLoadOutput(output: Record<string, number | string>): string {
  const parts: string[] = []
  if (output.sets && output.reps) parts.push(`${output.sets}×${output.reps}`)
  else if (output.sets) parts.push(`${output.sets} sets`)
  if (output.target_rpe) parts.push(`@ RPE ${output.target_rpe}`)
  if (output.weight_kg) parts.push(`${output.weight_kg}kg`)
  if (output.duration_minutes) parts.push(`${output.duration_minutes}min`)
  if (output.zone_target) parts.push(output.zone_target.toString())
  if (output.distance_km) parts.push(`${output.distance_km}km`)
  if (output.time_minutes) parts.push(`${output.time_minutes}min`)
  if (output.format) parts.push(output.format.toString())
  if (parts.length === 0) {
    return Object.entries(output)
      .slice(0, 3)
      .map(([k, v]) => `${k}=${v}`)
      .join(' ')
  }
  return parts.join(' ')
}

// ─── Main Component ───────────────────────────────────────────────────────────

export function PipelineFlowPanel({ program, weeks }: Props) {
  const { data: ontology } = useOntology()

  const [weekIdx, setWeekIdx] = useState(0)
  const [selectedDay, setSelectedDay] = useState<string | null>(null)
  const [sessionIdx, setSessionIdx] = useState(0)

  const weekTrace = weeks[weekIdx]
  if (!weekTrace) return <Placeholder text="No week trace available." />

  // Collect days that have sessions
  const assignedDays = Object.keys(weekTrace.sessions).sort()

  // Auto-select first day if none selected
  const activeDay = selectedDay && assignedDays.includes(selectedDay)
    ? selectedDay
    : assignedDays[0] ?? null

  const daySessions: SessionTrace[] = activeDay ? (weekTrace.sessions[activeDay] ?? []) : []
  const session: SessionTrace | undefined = daySessions[sessionIdx] ?? daySessions[0]

  const { goal } = program
  const sortedPriorities = Object.entries(goal.priorities)
    .filter(([, v]) => v > 0)
    .sort(([, a], [, b]) => b - a)

  const fw = weekTrace.scheduler.framework_selection
  const frameworkDef = ontology?.frameworks.find(f => f.id === fw.selected_id)

  return (
    <div className="space-y-1 max-w-2xl">
      {/* Week / Day / Session selectors */}
      <div className="flex flex-wrap gap-3 mb-3">
        <div className="flex gap-1 items-center">
          <Label>Week</Label>
          <div className="flex gap-1 ml-1">
            {weeks.map((w, i) => (
              <button
                key={w.week_number}
                onClick={() => { setWeekIdx(i); setSelectedDay(null); setSessionIdx(0) }}
                className={`px-2 py-0.5 rounded border text-[10px] font-mono transition-colors ${
                  i === weekIdx
                    ? 'bg-primary/15 border-primary/40 text-primary'
                    : 'border-border text-muted-foreground hover:bg-muted'
                }`}
              >
                W{w.week_number}
              </button>
            ))}
          </div>
        </div>
        <div className="flex gap-1 items-center">
          <Label>Day</Label>
          <div className="flex gap-1 ml-1">
            {assignedDays.map(d => (
              <button
                key={d}
                onClick={() => { setSelectedDay(d); setSessionIdx(0) }}
                className={`px-2 py-0.5 rounded border text-[10px] font-mono transition-colors ${
                  d === activeDay
                    ? 'bg-primary/15 border-primary/40 text-primary'
                    : 'border-border text-muted-foreground hover:bg-muted'
                }`}
              >
                {d}
              </button>
            ))}
          </div>
        </div>
        {daySessions.length > 1 && (
          <div className="flex gap-1 items-center">
            <Label>Session</Label>
            <div className="flex gap-1 ml-1">
              {daySessions.map((s, i) => (
                <button
                  key={i}
                  onClick={() => setSessionIdx(i)}
                  className={`px-2 py-0.5 rounded border text-[10px] font-mono transition-colors ${
                    i === sessionIdx
                      ? 'bg-primary/15 border-primary/40 text-primary'
                      : 'border-border text-muted-foreground hover:bg-muted'
                  }`}
                >
                  {s.modality.replace(/_/g, ' ')}
                </button>
              ))}
            </div>
          </div>
        )}
      </div>

      {/* ① Goal */}
      <Block
        color="border-l-violet-500"
        label="① GOAL"
        reads={['goal profile YAML', 'athlete constraints']}
        outputs={['priority weights', 'phase sequence', 'primary sources']}
      >
        <div className="font-mono text-[10px] font-medium text-foreground/80">{goal.name}</div>
        <p className="text-[10px] text-muted-foreground leading-relaxed">
          {goal.description.slice(0, 120)}{goal.description.length > 120 ? '…' : ''}
        </p>
        <div className="space-y-1 mt-1">
          {sortedPriorities.slice(0, 6).map(([mod, prio]) => (
            <div key={mod} className="flex items-center gap-2">
              <span className="text-[10px] text-muted-foreground w-36 truncate">{mod.replace(/_/g, ' ')}</span>
              <div className="flex-1 h-1 bg-muted rounded-full overflow-hidden">
                <div className="h-full bg-primary/60 rounded-full" style={{ width: `${prio * 100}%` }} />
              </div>
              <Mono>{(prio * 100).toFixed(0)}%</Mono>
            </div>
          ))}
        </div>
        {goal.primary_sources && goal.primary_sources.length > 0 && (
          <div className="flex flex-wrap gap-1 mt-1">
            <Label>sources:</Label>
            {goal.primary_sources.map(s => (
              <span key={s} className="px-1.5 py-0.5 rounded bg-violet-500/10 text-[10px] font-mono text-violet-400">{s}</span>
            ))}
          </div>
        )}
      </Block>

      <Connector label="priority weights → framework selection" />

      {/* ② Framework */}
      <Block
        color="border-l-blue-500"
        label="② FRAMEWORK SELECTION"
        reads={['goal.framework_selection', 'days_per_week constraint']}
        outputs={['sessions_per_week template']}
      >
        {fw ? (
          <div className="space-y-1.5">
            <div className="flex items-center gap-2">
              <Mono>{fw.selected_id}</Mono>
              {fw.forced_override && (
                <span className="px-1.5 py-0.5 rounded bg-amber-500/15 text-[10px] text-amber-400">forced override</span>
              )}
            </div>
            <p className="text-[10px] text-muted-foreground">{fw.selection_reason}</p>
            {frameworkDef?.source_philosophy && (
              <div className="flex gap-1 items-center">
                <Label>philosophy:</Label>
                <Mono>{frameworkDef.source_philosophy}</Mono>
              </div>
            )}
            {frameworkDef?.sessions_per_week && (
              <div className="flex flex-wrap gap-1 mt-0.5">
                <Label>sessions/wk:</Label>
                {Object.entries(frameworkDef.sessions_per_week).map(([mod, cnt]) => {
                  const col = MODALITY_COLORS[mod as ModalityId]
                  return (
                    <span key={mod} className={`px-1.5 py-0.5 rounded text-[10px] font-mono ${col?.bg ?? 'bg-muted'} ${col?.text ?? 'text-foreground'}`}>
                      {mod.replace(/_/g, ' ')} ×{cnt}
                    </span>
                  )
                })}
              </div>
            )}
            {fw.alternatives_checked && fw.alternatives_checked.length > 0 && (
              <div className="mt-1 space-y-0.5">
                <Label>alternatives checked:</Label>
                {fw.alternatives_checked.map(a => (
                  <div key={a.framework_id} className="flex items-center gap-2 pl-2">
                    <span className={`w-1.5 h-1.5 rounded-full ${a.matched ? 'bg-emerald-400' : 'bg-muted-foreground/40'}`} />
                    <Mono>{a.framework_id}</Mono>
                    <span className="text-[10px] text-muted-foreground">{a.condition}</span>
                  </div>
                ))}
              </div>
            )}
          </div>
        ) : (
          <Placeholder text="No framework selection trace." />
        )}
      </Block>

      <Connector label="sessions_per_week → allocation math" />

      {/* ③ Allocation */}
      <Block
        color="border-l-indigo-500"
        label="③ ALLOCATION"
        reads={['phase priorities', 'framework.sessions_per_week']}
        outputs={['session counts per modality']}
      >
        {weekTrace.scheduler.allocation ? (
          <div className="space-y-1.5">
            <div className="flex gap-2 items-center">
              <Label>phase:</Label>
              <Mono>{weekTrace.phase}</Mono>
              {weekTrace.is_deload && (
                <span className="px-1.5 py-0.5 rounded bg-amber-500/15 text-[10px] text-amber-400">deload</span>
              )}
            </div>
            <div className="overflow-x-auto">
              <table className="text-[10px] font-mono w-full">
                <thead>
                  <tr className="text-muted-foreground/60">
                    <th className="text-left pr-4 font-normal">modality</th>
                    <th className="text-right pr-4 font-normal">priority</th>
                    <th className="text-right pr-4 font-normal">raw</th>
                    <th className="text-right font-normal">final</th>
                  </tr>
                </thead>
                <tbody>
                  {Object.entries(weekTrace.scheduler.allocation.final)
                    .filter(([, v]) => v > 0)
                    .sort(([, a], [, b]) => b - a)
                    .map(([mod, final]) => {
                      const col = MODALITY_COLORS[mod as ModalityId]
                      return (
                        <tr key={mod}>
                          <td className={`pr-4 ${col?.text ?? 'text-foreground'}`}>{mod.replace(/_/g, ' ')}</td>
                          <td className="text-right pr-4 text-muted-foreground">
                            {((weekTrace.scheduler.allocation.phase_priorities[mod] ?? 0) * 100).toFixed(0)}%
                          </td>
                          <td className="text-right pr-4 text-muted-foreground">
                            {(weekTrace.scheduler.allocation.raw[mod] ?? 0).toFixed(2)}
                          </td>
                          <td className="text-right text-foreground/80">{final}</td>
                        </tr>
                      )
                    })}
                </tbody>
              </table>
            </div>
          </div>
        ) : (
          <Placeholder text="No allocation trace." />
        )}
      </Block>

      <Connector label="session counts → day assignment" />

      {/* ④ Day Assignment */}
      <Block
        color="border-l-teal-500"
        label="④ DAY ASSIGNMENT"
        reads={['modality.recovery_cost', 'modality.incompatible_in_session_with', 'cadence pattern']}
        outputs={['modality → day mapping']}
      >
        {weekTrace.scheduler.day_assignment ? (
          <div className="space-y-2">
            {/* Mini 7-day grid */}
            <div className="grid grid-cols-7 gap-1">
              {DAY_NAMES.map((name, i) => {
                const dayNum = i + 1
                const dayStr = dayNum.toString()
                const dayMods = weekTrace.scheduler.day_assignment.assignments[dayStr] ?? []
                const isActive = activeDay === dayStr
                return (
                  <div
                    key={name}
                    className={`rounded border text-center p-1 ${isActive ? 'border-primary/60 bg-primary/10' : 'border-border/40 bg-muted/20'}`}
                  >
                    <div className="text-[9px] text-muted-foreground mb-0.5">{name}</div>
                    {dayMods.length === 0 ? (
                      <div className="text-[9px] text-muted-foreground/30">—</div>
                    ) : (
                      dayMods.map(mod => {
                        const col = MODALITY_COLORS[mod as ModalityId]
                        return (
                          <div
                            key={mod}
                            className={`text-[8px] font-mono rounded px-0.5 mb-0.5 truncate ${col?.bg ?? 'bg-muted'} ${col?.text ?? 'text-foreground'}`}
                            title={mod}
                          >
                            {mod.replace(/_/g, '_').slice(0, 8)}
                          </div>
                        )
                      })
                    )}
                  </div>
                )
              })}
            </div>
            {/* Modality order + recovery cost */}
            {weekTrace.scheduler.day_assignment.modality_order.length > 0 && (
              <div className="space-y-0.5">
                <Label>placement order (by recovery cost):</Label>
                {weekTrace.scheduler.day_assignment.modality_order.map(mod => {
                  const modalityDef = ontology?.modalities.find(m => m.id === mod)
                  const col = MODALITY_COLORS[mod as ModalityId]
                  return (
                    <div key={mod} className="flex items-center gap-2 pl-1">
                      <span className={`text-[10px] font-mono ${col?.text ?? 'text-foreground'}`}>
                        {mod.replace(/_/g, ' ')}
                      </span>
                      {modalityDef && (
                        <span className={`px-1.5 py-0.5 rounded text-[9px] ${
                          modalityDef.recovery_cost === 'high' ? 'bg-red-500/15 text-red-400' :
                          modalityDef.recovery_cost === 'medium' ? 'bg-amber-500/15 text-amber-400' :
                          'bg-emerald-500/15 text-emerald-400'
                        }`}>
                          {modalityDef.recovery_cost}
                        </span>
                      )}
                    </div>
                  )
                })}
              </div>
            )}
          </div>
        ) : (
          <Placeholder text="No day assignment trace." />
        )}
      </Block>

      <Connector label={`modality → archetype selection${session ? ` (${session.modality})` : ''}`} />

      {/* ⑤ Archetype Selection */}
      <Block
        color="border-l-amber-500"
        label="⑤ ARCHETYPE SELECTION"
        reads={['assigned modality', 'phase', 'equipment', 'training_level']}
        outputs={['archetype (session template with N slots)']}
      >
        {session ? (
          <div className="space-y-1.5">
            <div className="flex items-center gap-2">
              <ModalityBadge modality={session.modality as ModalityId} size="sm" />
              {session.archetype.selected_id ? (
                <Mono>{session.archetype.selected_id}</Mono>
              ) : (
                <span className="text-[10px] text-muted-foreground/50 italic">no archetype selected</span>
              )}
            </div>
            {session.archetype.candidates.length > 0 && (
              <div className="space-y-0.5">
                <Label>top candidates:</Label>
                {session.archetype.candidates.slice(0, 4).map(c => (
                  <div key={c.id} className="flex items-center gap-2 pl-1">
                    <span className={`w-1.5 h-1.5 rounded-full ${c.id === session.archetype.selected_id ? 'bg-emerald-400' : 'bg-muted-foreground/30'}`} />
                    <Mono>{c.id}</Mono>
                    <span className="text-[10px] text-muted-foreground font-mono">score={c.score.toFixed(1)}</span>
                  </div>
                ))}
              </div>
            )}
            {Object.keys(session.archetype.filter_counts).length > 0 && (
              <div className="flex flex-wrap gap-1">
                <Label>filters:</Label>
                {Object.entries(session.archetype.filter_counts).map(([k, v]) => (
                  <span key={k} className="px-1.5 py-0.5 rounded bg-muted text-[10px] font-mono text-muted-foreground">
                    {k}={v}
                  </span>
                ))}
              </div>
            )}
          </div>
        ) : (
          <Placeholder text="Select a day with a session to see archetype selection." />
        )}
      </Block>

      <Connector label="archetype slots → exercise selection" />

      {/* ⑥ Exercise Selection */}
      <Block
        color="border-l-orange-500"
        label="⑥ EXERCISE SELECTION"
        reads={['archetype slots', 'exercises', 'injury_flags', 'equipment']}
        outputs={['exercises per slot']}
      >
        {session && session.slots.length > 0 ? (
          <div className="space-y-1">
            {session.slots.map((slot, i) => (
              <div
                key={i}
                className={`flex items-start gap-2 text-[10px] font-mono py-0.5 ${slot.meta ? 'opacity-40' : ''}`}
              >
                <span className="text-muted-foreground/50 w-4 shrink-0">{slot.slot_index}</span>
                <span className={`shrink-0 w-16 truncate ${slot.injury_blocked ? 'text-destructive/70' : 'text-muted-foreground'}`}>
                  {slot.slot_role}
                </span>
                <span className="text-muted-foreground/60 shrink-0 w-20 truncate">{slot.slot_type}</span>
                {slot.movement_pattern && (
                  <span className="text-muted-foreground/50 shrink-0 w-20 truncate">{slot.movement_pattern}</span>
                )}
                {slot.injury_blocked ? (
                  <span className="text-destructive/60 italic">injury skip</span>
                ) : slot.selected_id ? (
                  <span className="text-foreground/70 truncate">{slot.selected_id}</span>
                ) : (
                  <span className="text-muted-foreground/40 italic">—</span>
                )}
                {!slot.injury_blocked && slot.candidates.length > 0 && (
                  <span className="text-muted-foreground/40 shrink-0">({slot.candidates.length})</span>
                )}
              </div>
            ))}
          </div>
        ) : (
          <Placeholder text="Select a day with a session to see exercise selection." />
        )}
      </Block>

      <Connector label="exercises → load calculation" />

      {/* ⑦ Load Calculation */}
      <Block
        color="border-l-emerald-500"
        label="⑦ LOAD CALCULATION"
        reads={['progression_model', 'week_in_phase', 'phase', 'training_level', 'is_deload']}
        outputs={['prescribed load']}
      >
        {session && session.progression.length > 0 ? (
          <div className="space-y-1">
            {session.progression.map((p, i) => (
              <div key={i} className="flex items-start gap-2 text-[10px] font-mono py-0.5">
                <span className="text-muted-foreground/50 w-4 shrink-0">{i + 1}</span>
                <span className="text-foreground/70 truncate w-32 shrink-0">{p.exercise_name}</span>
                <span className="text-muted-foreground/60 shrink-0 w-24 truncate">{p.model}</span>
                <span className="text-primary/70 truncate">{formatLoadOutput(p.output)}</span>
              </div>
            ))}
          </div>
        ) : (
          <Placeholder text="Select a day with a session to see load calculations." />
        )}
      </Block>
    </div>
  )
}
