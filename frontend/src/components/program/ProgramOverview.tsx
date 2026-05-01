import { useState } from 'react'
import { cn } from '@/lib/utils'
import { Badge } from '@/components/ui/badge'
import { PHASE_COLORS } from '@/lib/phaseColors'
import {
  BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, Legend, ReferenceArea,
} from 'recharts'
import type { GeneratedProgram, ModalityId, TrainingPhase } from '@/api/types'
import type { PhaseSegment } from '@/hooks/usePhaseCalendar'
import { useBuilderStore } from '@/store/builderStore'
import { usePhilosophies } from '@/api/philosophies'
import { MODALITY_COLORS } from '@/lib/modalityColors'

// ── Category config (for backend volume summary bars — 4 fixed buckets) ───────

const VOL_CATEGORIES = [
  { id: 'Strength',     color: '#ef4444' },
  { id: 'Conditioning', color: '#0ea5e9' },
  { id: 'Durability',   color: '#f59e0b' },
  { id: 'Mobility',     color: '#10b981' },
] as const

// ── Phase theory content ───────────────────────────────────────────────────────

interface PhaseTheory {
  theory: string
  keyAdaptations: string[]
  intensityProfile: string
  methodology: string
}

const PHASE_THEORY: Record<TrainingPhase, PhaseTheory> = {
  base: {
    theory: 'Establishes aerobic infrastructure and structural resilience before any intensification. Volume is the primary driver; intensity stays submaximal. Mirrors the Uphill Athlete base period and Lydiard\'s aerobic foundation model — you are building the engine, not testing it.',
    keyAdaptations: ['Mitochondrial density', 'Cardiac output', 'Capillary development', 'Connective tissue tolerance', 'Movement economy'],
    intensityProfile: '80–90% low intensity (Z1–Z2), 10–20% moderate',
    methodology: 'Uphill Athlete · Polarized 80/20',
  },
  build: {
    theory: 'Layers specific intensity onto the aerobic base. Threshold work and strength accumulation rise together. This is the "load" block in Gym Jones concurrent programming and the specific preparation phase in classical periodization. Fitness is built here; the base phase made it sustainable.',
    keyAdaptations: ['Lactate threshold', 'Neuromuscular recruitment', 'Glycolytic capacity', 'Strength–endurance coupling'],
    intensityProfile: '70% low intensity, 20% threshold, 10% high intensity',
    methodology: 'Gym Jones · Block Periodization',
  },
  peak: {
    theory: 'Sharpens event-specific fitness through high-intensity, reduced-volume work. The accumulated base is leveraged for top-end expression. Marcus Filly\'s functional peak and CrossFit Endurance race-prep inform this phase — it reveals what was built, not where more is added.',
    keyAdaptations: ['VO₂max expression', 'Power output', 'Sport-specific sharpening', 'Neuromuscular peak'],
    intensityProfile: '60% moderate, 30% high, 10% maximal',
    methodology: 'CrossFit Endurance · Marcus Filly',
  },
  taper: {
    theory: 'Reduces training volume 40–60% while maintaining intensity to allow supercompensation. Fatigue dissipates faster than fitness — the taper captures the gap. Research supports a 1–3 week taper for endurance athletes; strength athletes typically need less.',
    keyAdaptations: ['Fatigue clearance', 'Glycogen supercompensation', 'Neural readiness', 'Hormonal recovery'],
    intensityProfile: '~50% of peak-week volume · intensity maintained',
    methodology: 'Uphill Athlete · Evidence-based taper',
  },
  deload: {
    theory: 'A structured deload prevents accumulated fatigue from compounding into overreaching. Volume drops 40–60%; intensity is maintained or modestly reduced. Starting Strength\'s "light day" principle scales to a full week when systemic fatigue is present.',
    keyAdaptations: ['Connective tissue repair', 'Neural recovery', 'Hormonal reset', 'Adaptation consolidation'],
    intensityProfile: '40–60% of normal volume · similar or reduced intensity',
    methodology: 'Starting Strength · Auto-regulation',
  },
  maintenance: {
    theory: 'Sustains all fitness qualities without driving further adaptation. Minimum effective dose — enough stimulus to prevent detraining. Used between focused blocks or during high life-stress periods when additional loading is counterproductive.',
    keyAdaptations: ['Fitness retention', 'Movement quality', 'Structural integrity'],
    intensityProfile: 'Balanced across qualities · moderate volume and intensity',
    methodology: 'Concurrent · Minimum Effective Dose',
  },
  rehab: {
    theory: 'Restores movement quality and tissue health before progressive loading. ATG and Ido Portal movement restoration principles guide selection. Pain-free range of motion and tissue tolerance precede any strength expression.',
    keyAdaptations: ['Range of motion restoration', 'Tissue remodeling', 'Pattern re-education', 'Pain reduction'],
    intensityProfile: 'Low load · high frequency · below pain threshold',
    methodology: 'ATG · Ido Portal · Movement Restoration',
  },
  post_op: {
    theory: 'Protects healing tissues while maintaining non-affected systems. Loading follows surgical protocol timelines. Movement is used as medicine within prescribed constraints — adjacent fitness is maintained, not lost.',
    keyAdaptations: ['Tissue healing', 'Edema reduction', 'Muscle inhibition reversal', 'Proprioceptive re-training'],
    intensityProfile: 'Minimal load · protocol-guided · protect surgical site',
    methodology: 'Surgical protocol compliance · Conservative loading',
  },
  active: {
    theory: 'Maintains movement quality and parasympathetic tone between intensive training blocks. Low-intensity aerobic work accelerates recovery without adding stress. Horsemen GPP principles of constant low-level movement underpin this phase.',
    keyAdaptations: ['Active recovery', 'Movement quality maintenance', 'Aerobic maintenance'],
    intensityProfile: 'Low intensity only · Z1–Z2 ceiling',
    methodology: 'Horsemen GPP · Active Recovery',
  },
  transition: {
    theory: 'Rebuilds movement quality and general work capacity after a rest period or following an objective. Intensity stays strictly aerobic (Z1–Z2 only — nose-breathing). Strength work is general and progressed linearly. No anaerobic work. Uphill Athlete describes this as "filling the tank" before structured loading begins — the training age of the tissue must catch up to the ambition of the athlete.',
    keyAdaptations: ['Movement pattern restoration', 'Aerobic re-priming', 'Connective tissue tolerance', 'General work capacity', 'Training habit re-establishment'],
    intensityProfile: '90–100% low intensity (Z1–Z2) · no anaerobic',
    methodology: 'Uphill Athlete — Transition Period · Starting Strength linear reload',
  },
  specific: {
    theory: 'Applies accumulated base fitness directly to the demands of the target objective. Muscular endurance (ME) — the mountain-specific quality — peaks here through weighted box step-ups and uphill carries. Interval intensity rises to approach AnT. Long days back-to-back simulate the event. Volume is near peak; progression shifts from "more volume" to "higher specificity." This is the phase that separates mountain athletes from general endurance athletes.',
    keyAdaptations: ['Muscular endurance (ME)', 'Sport-specific power', 'AnT approach', 'Back-to-back long-day tolerance', 'Load-bearing capacity'],
    intensityProfile: '80% low intensity · 15% threshold · 5% high intensity',
    methodology: 'Uphill Athlete — Specific Period · ME box step-ups · AnT intervals',
  },
}

// ── Helpers ────────────────────────────────────────────────────────────────────

function fmtDur(minMin: number, maxMin: number): string {
  const fmt = (m: number) => {
    if (m <= 0) return ''
    const h = Math.floor(m / 60)
    const rem = Math.round(m % 60)
    if (h === 0) return `${rem}m`
    return rem > 0 ? `${h}h ${rem}m` : `${h}h`
  }
  if (minMin <= 0 && maxMin <= 0) return ''
  if (minMin === maxMin || minMin <= 0) return fmt(maxMin)
  return `${fmt(minMin)}–${fmt(maxMin)}`
}

interface ArchetypeRow {
  name: string
  color: string
  count: number
  minDur: number
  maxDur: number
  modality: string
}

function buildArchetypeRows(
  program: GeneratedProgram,
  startWeek: number,
  endWeek: number
): ArchetypeRow[] {
  const map = new Map<string, ArchetypeRow>()

  for (const week of program.weeks ?? []) {
    if (week.week_number < startWeek || week.week_number > endWeek) continue
    for (const sessions of Object.values(week.schedule)) {
      for (const session of sessions) {
        if (!session.archetype) continue
        const dur = session.duration_min ?? session.archetype.duration_estimate_minutes ?? 0
        const mod = session.modality as ModalityId
        const color = MODALITY_COLORS[mod]?.hex ?? '#6366f1'
        const name = session.archetype.name

        const existing = map.get(name)
        if (existing) {
          existing.count++
          existing.minDur = Math.min(existing.minDur, dur)
          existing.maxDur = Math.max(existing.maxDur, dur)
        } else {
          map.set(name, { name, color, count: 1, minDur: dur, maxDur: dur, modality: mod })
        }
      }
    }
  }

  return Array.from(map.values()).sort((a, b) => b.count - a.count)
}

interface WeekVolRow {
  week: number
  strength: number
  conditioning: number
  durability: number
  mobility: number
  sessions: number
}

function buildWeekVolRows(
  program: GeneratedProgram,
  startWeek: number,
  endWeek: number
): WeekVolRow[] {
  const rows: WeekVolRow[] = []
  const volSummary = program.volume_summary ?? []

  for (let w = startWeek; w <= endWeek; w++) {
    const vs = volSummary.find((s) => s.week_number === w)
    const weekData = program.weeks?.find((wk) => wk.week_number === w)
    const sessionCount = weekData
      ? Object.values(weekData.schedule).flat().length
      : 0

    rows.push({
      week: w,
      strength: vs ? vs.strength_sets * 4 : 0,
      conditioning: vs?.cond_minutes ?? 0,
      durability: vs?.dur_minutes ?? 0,
      mobility: vs?.mob_minutes ?? 0,
      sessions: sessionCount,
    })
  }
  return rows
}

// ── Component ─────────────────────────────────────────────────────────────────

interface ProgramOverviewProps {
  program: GeneratedProgram
  segments: PhaseSegment[]
}

export function ProgramOverview({ program, segments }: ProgramOverviewProps) {
  const [expandedPhases, setExpandedPhases] = useState<Set<string>>(new Set())

  const sourceMode = useBuilderStore((s) => s.sourceMode)
  const selectedPhilosophyIds = useBuilderStore((s) => s.selectedPhilosophyIds)
  const { data: philosophies } = usePhilosophies()

  const { goal, volume_summary } = program as GeneratedProgram & {
    minimum_prerequisites?: Record<string, number>
  }

  const prerequisites = (goal.minimum_prerequisites ?? {}) as Record<string, number>

  const chartData = (volume_summary ?? []).map((s) => ({
    week: `W${s.week_number}`,
    Strength:     s.strength_sets * 4,
    Conditioning: s.cond_minutes,
    Durability:   s.dur_minutes,
    Mobility:     s.mob_minutes,
  }))

  function togglePhase(key: string) {
    setExpandedPhases((prev) => {
      const next = new Set(prev)
      if (next.has(key)) next.delete(key)
      else next.add(key)
      return next
    })
  }

  return (
    <div className="p-6 space-y-8">

      {/* 1. Program rationale */}
      {sourceMode !== null ? (
        <div>
          <h2 className="text-sm font-semibold mb-2">About this Program</h2>
          {sourceMode === 'philosophy' && (() => {
            const phil = philosophies?.find((p) => p.id === selectedPhilosophyIds[0])
            return phil ? (
              <>
                <p className="text-sm text-muted-foreground leading-relaxed">
                  Built from the <span className="font-medium text-foreground">{phil.name}</span> philosophy.
                </p>
                <div className="flex flex-wrap gap-1.5 mt-3">
                  <Badge variant="secondary" className="text-xs">{phil.id}</Badge>
                </div>
              </>
            ) : null
          })()}
          {sourceMode === 'blend' && (() => {
            const phils = philosophies?.filter((p) => selectedPhilosophyIds.includes(p.id)) ?? []
            return (
              <>
                <p className="text-sm text-muted-foreground leading-relaxed">
                  Blended from {phils.length} philosoph{phils.length === 1 ? 'y' : 'ies'}:{' '}
                  {phils.map((p) => p.name).join(', ')}.
                </p>
                <div className="flex flex-wrap gap-1.5 mt-3">
                  {phils.map((p) => (
                    <Badge key={p.id} variant="secondary" className="text-xs">{p.id}</Badge>
                  ))}
                </div>
              </>
            )
          })()}
          {sourceMode === 'custom' && (
            <p className="text-sm text-muted-foreground leading-relaxed">
              Built from custom modality priorities. Priorities are set directly — no source philosophy.
            </p>
          )}
        </div>
      ) : goal.notes ? (
        <div>
          <h2 className="text-sm font-semibold mb-2">About this Program</h2>
          <p className="text-sm text-muted-foreground leading-relaxed">{goal.notes}</p>
          {goal.primary_sources.length > 0 && (
            <div className="flex flex-wrap gap-1.5 mt-3">
              {goal.primary_sources.map((src) => (
                <Badge key={src} variant="secondary" className="text-xs">{src}</Badge>
              ))}
            </div>
          )}
        </div>
      ) : null}

      {/* 2. Phase cards — two separate cards per phase */}
      {segments.length > 0 && (
        <div>
          <h2 className="text-sm font-semibold mb-3">Training Phases</h2>
          <div className="space-y-4">
            {segments.map((seg) => {
              const colors = PHASE_COLORS[seg.phase]
              const phaseKey = `${seg.phase}-${seg.startWeek}`
              const isExpanded = expandedPhases.has(phaseKey)
              const theory = PHASE_THEORY[seg.phase]

              // Volume data
              const phaseVolWeeks = (volume_summary ?? []).filter(
                (s) => s.week_number >= seg.startWeek && s.week_number <= seg.endWeek
              )
              const volData = [
                { ...VOL_CATEGORIES[0], minutes: phaseVolWeeks.reduce((sum, s) => sum + s.strength_sets * 4, 0) },
                { ...VOL_CATEGORIES[1], minutes: phaseVolWeeks.reduce((sum, s) => sum + s.cond_minutes, 0) },
                { ...VOL_CATEGORIES[2], minutes: phaseVolWeeks.reduce((sum, s) => sum + s.dur_minutes, 0) },
                { ...VOL_CATEGORIES[3], minutes: phaseVolWeeks.reduce((sum, s) => sum + s.mob_minutes, 0) },
              ].filter(({ minutes }) => minutes > 0)
              const totalMinutes = volData.reduce((sum, { minutes }) => sum + minutes, 0)

              const archetypeRows = buildArchetypeRows(program, seg.startWeek, seg.endWeek)
              const weekVolRows = buildWeekVolRows(program, seg.startWeek, seg.endWeek)

              // Phase totals
              const totalSessions = weekVolRows.reduce((s, r) => s + r.sessions, 0)
              const totalStrengthSets = phaseVolWeeks.reduce((s, r) => s + r.strength_sets, 0)
              const totalConditioning = weekVolRows.reduce((s, r) => s + r.conditioning, 0)
              const totalDurability = weekVolRows.reduce((s, r) => s + r.durability, 0)
              const totalMobility = weekVolRows.reduce((s, r) => s + r.mobility, 0)

              return (
                <div key={phaseKey} className="space-y-0">
                  {/* Two-card row */}
                  <div className="grid grid-cols-2 gap-3">

                    {/* ── Left card: Theory ─────────────────────────── */}
                    <div className="rounded-xl border bg-card overflow-hidden flex flex-col">
                      <div className="h-0.5 w-full" style={{ backgroundColor: colors.hex }} />
                      <div className="p-5 flex flex-col gap-3 flex-1">

                        {/* Header */}
                        <div className="flex items-center justify-between gap-2">
                          <span className={cn(
                            'text-xs font-semibold px-2 py-0.5 rounded-full shrink-0',
                            colors.bg, colors.text
                          )}>
                            {colors.label}
                          </span>
                          <span className="text-[10px] font-medium text-muted-foreground/60 uppercase tracking-wider">
                            Theory
                          </span>
                        </div>

                        {/* Week range + focus */}
                        <div>
                          <div className="text-[10px] text-muted-foreground mb-1">
                            {seg.startWeek === seg.endWeek
                              ? `Week ${seg.startWeek}`
                              : `Weeks ${seg.startWeek}–${seg.endWeek}`}
                            {' · '}{seg.weeks} {seg.weeks === 1 ? 'week' : 'weeks'}
                          </div>
                          <p className="text-xs text-muted-foreground leading-relaxed">
                            {seg.focus}
                          </p>
                        </div>

                        {/* Volume bar */}
                        {volData.length > 0 && (
                          <div className="space-y-1.5 mt-auto">
                            <div className="flex h-1 w-full overflow-hidden rounded-full bg-muted">
                              {volData.map(({ id, color, minutes }) => (
                                <div
                                  key={id}
                                  style={{ width: `${(minutes / totalMinutes) * 100}%`, backgroundColor: color }}
                                />
                              ))}
                            </div>
                            <div className="flex flex-wrap gap-x-3 gap-y-0.5">
                              {volData.map(({ id, color }) => (
                                <span key={id} className="text-[10px] text-muted-foreground flex items-center gap-1">
                                  <span className="inline-block size-1.5 rounded-full shrink-0" style={{ backgroundColor: color }} />
                                  {id}
                                </span>
                              ))}
                            </div>
                          </div>
                        )}

                        {/* Expanded: theory detail */}
                        {isExpanded && (
                          <div className="border-t pt-4 mt-1 space-y-4">
                            <div>
                              <p className="text-xs text-muted-foreground leading-relaxed">
                                {theory.theory}
                              </p>
                            </div>
                            <div className="space-y-1">
                              <div className="text-[10px] font-semibold uppercase tracking-wider text-muted-foreground/60">
                                Key Adaptations
                              </div>
                              <div className="flex flex-wrap gap-1">
                                {theory.keyAdaptations.map((a) => (
                                  <span key={a} className={cn(
                                    'text-[10px] px-1.5 py-0.5 rounded-md border font-medium',
                                    colors.bg, colors.text
                                  )}>
                                    {a}
                                  </span>
                                ))}
                              </div>
                            </div>
                            <div className="grid grid-cols-1 gap-2">
                              <div>
                                <div className="text-[10px] font-semibold uppercase tracking-wider text-muted-foreground/60 mb-0.5">
                                  Intensity Profile
                                </div>
                                <p className="text-xs text-muted-foreground">{theory.intensityProfile}</p>
                              </div>
                              <div>
                                <div className="text-[10px] font-semibold uppercase tracking-wider text-muted-foreground/60 mb-0.5">
                                  Methodology
                                </div>
                                <p className="text-xs text-muted-foreground">{theory.methodology}</p>
                              </div>
                            </div>
                          </div>
                        )}

                      </div>
                    </div>

                    {/* ── Right card: Your program ──────────────────── */}
                    <div className="rounded-xl border bg-card overflow-hidden flex flex-col">
                      <div className="h-0.5 w-full" style={{ backgroundColor: colors.hex }} />
                      <div className="p-5 flex flex-col gap-3 flex-1">

                        {/* Header */}
                        <div className="flex items-center justify-between gap-2">
                          <span className={cn(
                            'text-xs font-semibold px-2 py-0.5 rounded-full shrink-0',
                            colors.bg, colors.text
                          )}>
                            {colors.label}
                          </span>
                          <span className="text-[10px] font-medium text-muted-foreground/60 uppercase tracking-wider">
                            Your Program
                          </span>
                        </div>

                        {/* Archetype list */}
                        {archetypeRows.length === 0 ? (
                          <p className="text-xs text-muted-foreground italic">No sessions generated.</p>
                        ) : (
                          <div className="space-y-2 flex-1">
                            {archetypeRows.map((row) => (
                              <div key={row.name} className="flex items-start gap-2">
                                <span
                                  className="inline-block size-1.5 rounded-full shrink-0 mt-1.5"
                                  style={{ backgroundColor: row.color }}
                                />
                                <span
                                  className="text-xs font-semibold tabular-nums shrink-0 w-5 text-right mt-0.5"
                                  style={{ color: row.color }}
                                >
                                  {row.count}×
                                </span>
                                <div className="flex-1 min-w-0">
                                  <div className="text-xs text-foreground leading-snug">{row.name}</div>
                                  <div className="text-[10px] font-medium" style={{ color: row.color }}>
                                    {MODALITY_COLORS[row.modality as ModalityId]?.label ?? row.modality}
                                  </div>
                                </div>
                                {row.maxDur > 0 && (
                                  <span className="text-[10px] text-muted-foreground tabular-nums shrink-0 mt-0.5">
                                    {fmtDur(row.minDur, row.maxDur)}
                                  </span>
                                )}
                              </div>
                            ))}
                          </div>
                        )}

                        {/* Phase summary stats */}
                        <div className="flex gap-3 mt-auto pt-2 border-t">
                          <div className="text-center">
                            <div className="text-sm font-semibold tabular-nums">{totalSessions}</div>
                            <div className="text-[9px] text-muted-foreground">sessions</div>
                          </div>
                          {totalStrengthSets > 0 && (
                            <div className="text-center">
                              <div className="text-sm font-semibold tabular-nums">{totalStrengthSets}</div>
                              <div className="text-[9px] text-muted-foreground">str sets</div>
                            </div>
                          )}
                          {totalConditioning > 0 && (
                            <div className="text-center">
                              <div className="text-sm font-semibold tabular-nums">{totalConditioning}m</div>
                              <div className="text-[9px] text-muted-foreground">conditioning</div>
                            </div>
                          )}
                          {totalDurability > 0 && (
                            <div className="text-center">
                              <div className="text-sm font-semibold tabular-nums">{totalDurability}m</div>
                              <div className="text-[9px] text-muted-foreground">durability</div>
                            </div>
                          )}
                          {totalMobility > 0 && (
                            <div className="text-center">
                              <div className="text-sm font-semibold tabular-nums">{totalMobility}m</div>
                              <div className="text-[9px] text-muted-foreground">mobility</div>
                            </div>
                          )}
                        </div>

                        {/* Expanded: week-by-week breakdown */}
                        {isExpanded && weekVolRows.length > 1 && (
                          <div className="border-t pt-4 mt-1">
                            <div className="text-[10px] font-semibold uppercase tracking-wider text-muted-foreground/60 mb-2">
                              Week-by-week
                            </div>
                            <div className="space-y-1.5">
                              {weekVolRows.map((row) => {
                                const rowTotal = row.strength + row.conditioning + row.durability + row.mobility
                                return (
                                  <div key={row.week} className="flex items-center gap-2">
                                    <span className="text-[10px] text-muted-foreground w-7 shrink-0">
                                      W{row.week}
                                    </span>
                                    <span className="text-[10px] text-muted-foreground w-12 shrink-0">
                                      {row.sessions} sess.
                                    </span>
                                    {/* Mini volume bar */}
                                    <div className="flex h-1 flex-1 overflow-hidden rounded-full bg-muted min-w-0">
                                      {row.strength > 0 && (
                                        <div style={{ width: `${(row.strength / rowTotal) * 100}%`, backgroundColor: '#ef4444' }} />
                                      )}
                                      {row.conditioning > 0 && (
                                        <div style={{ width: `${(row.conditioning / rowTotal) * 100}%`, backgroundColor: '#0ea5e9' }} />
                                      )}
                                      {row.durability > 0 && (
                                        <div style={{ width: `${(row.durability / rowTotal) * 100}%`, backgroundColor: '#f59e0b' }} />
                                      )}
                                      {row.mobility > 0 && (
                                        <div style={{ width: `${(row.mobility / rowTotal) * 100}%`, backgroundColor: '#10b981' }} />
                                      )}
                                    </div>
                                    <span className="text-[10px] text-muted-foreground tabular-nums w-12 text-right shrink-0">
                                      {rowTotal}m
                                    </span>
                                  </div>
                                )
                              })}
                            </div>
                          </div>
                        )}

                      </div>
                    </div>

                  </div>

                  {/* Details toggle — centered below both cards */}
                  <div className="flex justify-center pt-1">
                    <button
                      onClick={() => togglePhase(phaseKey)}
                      className="text-[11px] text-muted-foreground hover:text-foreground transition-colors flex items-center gap-1 px-2 py-1 rounded-md hover:bg-muted/50"
                    >
                      {isExpanded ? (
                        <>Hide details <span className="opacity-60">↑</span></>
                      ) : (
                        <>Details <span className="opacity-60">↓</span></>
                      )}
                    </button>
                  </div>
                </div>
              )
            })}
          </div>
        </div>
      )}

      {/* 3. Volume progression chart */}
      {chartData.length > 0 && (
        <div>
          <h2 className="text-sm font-semibold mb-3">Volume Progression</h2>
          <ResponsiveContainer width="100%" height={200}>
            <BarChart data={chartData} barSize={6} barGap={1} margin={{ top: 4, right: 8, left: 0, bottom: 0 }}>
              <XAxis
                dataKey="week"
                tick={{ fontSize: 9, fill: 'var(--muted-foreground)' }}
                axisLine={false}
                tickLine={false}
                interval={chartData.length > 12 ? Math.floor(chartData.length / 12) : 0}
              />
              <YAxis
                tick={{ fontSize: 9, fill: 'var(--muted-foreground)' }}
                axisLine={false}
                tickLine={false}
                width={24}
              />
              <Tooltip
                cursor={{ fill: '#888', fillOpacity: 0.08 }}
                contentStyle={{
                  backgroundColor: 'var(--card)',
                  border: '1px solid var(--border)',
                  borderRadius: '8px',
                  fontSize: '11px',
                }}
                formatter={(v) => [`${String(v)} min`]}
              />
              <Legend iconType="circle" iconSize={6} wrapperStyle={{ fontSize: 10 }} />

              {segments.map((seg) => (
                <ReferenceArea
                  key={seg.phase + seg.startWeek}
                  x1={`W${seg.startWeek}`}
                  x2={`W${seg.endWeek}`}
                  fill={PHASE_COLORS[seg.phase]?.hex}
                  fillOpacity={0.06}
                  stroke={PHASE_COLORS[seg.phase]?.hex}
                  strokeOpacity={0.25}
                  label={{ value: PHASE_COLORS[seg.phase]?.label, position: 'insideTopLeft', fontSize: 8, fill: PHASE_COLORS[seg.phase]?.hex, opacity: 0.7 }}
                />
              ))}

              <Bar dataKey="Conditioning" fill="#0ea5e9" radius={[2, 2, 0, 0]} />
              <Bar dataKey="Durability"   fill="#f59e0b" radius={[2, 2, 0, 0]} />
              <Bar dataKey="Strength"     fill="#ef4444" radius={[2, 2, 0, 0]} />
              <Bar dataKey="Mobility"     fill="#10b981" radius={[2, 2, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </div>
      )}

      {/* 4. Entry standards */}
      {Object.keys(prerequisites).length > 0 && (
        <div>
          <h2 className="text-sm font-semibold mb-1">Entry Standards</h2>
          <p className="text-xs text-muted-foreground mb-3">
            Minimum benchmarks recommended before starting this program.
          </p>
          <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
            {Object.entries(prerequisites).map(([key, val]) => (
              <div key={key} className="rounded-lg border bg-muted/30 px-3 py-2">
                <div className="text-[10px] text-muted-foreground capitalize">
                  {key.replace(/_/g, ' ')}
                </div>
                <div className="text-sm font-semibold">{val}</div>
              </div>
            ))}
          </div>
        </div>
      )}

    </div>
  )
}
