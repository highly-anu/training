import { useState } from 'react'
import { ChevronRight, Code2, Database, AlertCircle, CheckCircle2, MinusCircle } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { cn } from '@/lib/utils'
import type { TracedProgram } from '@/api/types'

// ─── Data ─────────────────────────────────────────────────────────────────────

interface Edge {
  id: string
  source: string
  target: string
  fn: string
  file: string
  knowledgeRatio: number // % baked (0 = pure data, 100 = pure code)
  yamlFromSource: string[]
  yamlFromTarget: string[]
  bakedLogic: string[]
  hardcodedValues?: string[]
}

const EDGES: Edge[] = [
  {
    id: 'philosophy-framework',
    source: 'Philosophy',
    target: 'Framework',
    fn: 'loader.load_philosophies()',
    file: 'src/loader.py',
    knowledgeRatio: 5,
    yamlFromSource: ['sources', 'methodology'],
    yamlFromTarget: ['sources', 'applicable_when'],
    bakedLogic: [
      'Builds reverse index: scans frameworks + goals to find which cite each philosophy',
      'No scoring or placement logic — pure structural linking',
    ],
  },
  {
    id: 'goal-framework',
    source: 'Goal',
    target: 'Framework',
    fn: 'scheduler.select_framework()',
    file: 'src/scheduler.py:49–131',
    knowledgeRatio: 60,
    yamlFromSource: ['forced_framework (override field)'],
    yamlFromTarget: ['applicable_when conditions', 'min/max days_per_week', 'sessions_per_week'],
    bakedLogic: [
      'Evaluates applicable_when conditions (e.g. "days_per_week <= 3") via hardcoded _eval_condition()',
      'Fallback chain: forced override → first matching condition → days_per_week compatibility',
      'Validates min/max day count constraints from framework YAML',
    ],
    hardcodedValues: [
      '_CADENCE_OPTIONS dict keyed by framework_id — new framework IDs with no entry get no cadence pattern (blocker for user-created frameworks)',
    ],
  },
  {
    id: 'framework-modality',
    source: 'Framework + Goal',
    target: 'Modality Schedule',
    fn: 'scheduler.allocate_sessions() + assign_to_days()',
    file: 'src/scheduler.py:152–423',
    knowledgeRatio: 70,
    yamlFromSource: [
      'goal.priorities (modality weights)',
      'goal.phase_sequence[].priority_override',
      'framework.sessions_per_week',
    ],
    yamlFromTarget: [
      'recovery_cost (high/medium/low)',
      'recovery_hours_min',
      'incompatible_in_session_with',
      'session_position',
    ],
    bakedLogic: [
      'Largest-remainder rounding converts priority weights → integer session counts',
      '_RECOVERY_COST_RANK: {high:3, medium:2, low:1} — rank determines placement order',
      'Recovery gap enforcement: 24–48h minimum between high-cost modalities',
      'Phase-aware cadence: taper/deload/rehab get most-spread-out day pattern',
      'Incompatibility: no two incompatible_in_session_with modalities share a day',
    ],
    hardcodedValues: [
      '_RECOVERY_COST_RANK dict — only 3 cost levels recognised',
      '_CADENCE_OPTIONS — weekly day patterns per framework, keyed by framework_id',
    ],
  },
  {
    id: 'modality-archetype',
    source: 'Modality',
    target: 'Archetype',
    fn: 'selector.select_archetype()',
    file: 'src/selector.py:183–340',
    knowledgeRatio: 50,
    yamlFromSource: ['modality id (primary filter)', 'goal.sources (for scoring)'],
    yamlFromTarget: [
      'applicable_phases',
      'training_levels',
      'required_equipment',
      'scaling.equipment_limited',
      'scaling.time_limited',
      'sources',
    ],
    bakedLogic: [
      'Scoring: +6 full equipment satisfied, +2 per source match with goal, −3 per recent use (last 14), up to −8 injury impact',
      'Equipment-limited fallback: use archetype with scaling flag if preferred is blocked by equipment',
      'Time-limited fallback: use shorter archetype variant if session time is insufficient',
    ],
  },
  {
    id: 'archetype-exercise',
    source: 'Archetype Slot',
    target: 'Exercise',
    fn: 'selector.select_exercise()',
    file: 'src/selector.py:347–471',
    knowledgeRatio: 60,
    yamlFromSource: [
      'slot.slot_type',
      'slot.movement_pattern',
      'slot.category',
      'slot.effort',
    ],
    yamlFromTarget: [
      'movement_patterns',
      'category',
      'equipment',
      'training_level',
      'requires / unlocks',
      'contraindicated_with',
      'effort',
    ],
    bakedLogic: [
      'Movement pattern aliases: 30+ mappings in code (e.g. hip_hinge includes deadlift_pattern, rdl_pattern)',
      'Level prerequisite chain: hardcoded unlock ladder (novice → intermediate → advanced → elite)',
      'Slot constraints: AMRAP/for_time slots reject mobility + rehab category; zone1–2 aerobic slots reject high/max effort',
      'Scoring: −2 per recent use, +0.5 for exercises with unlocks, +0.5 for defined movement_patterns',
      'Taper phase: max-effort exercises excluded entirely',
    ],
    hardcodedValues: [
      'Movement pattern alias dict (selector.py:12–48) — new patterns need a code addition to be matchable',
      'Level prerequisite chain (selector.py:53–76)',
    ],
  },
  {
    id: 'exercise-progression',
    source: 'Exercise + Slot',
    target: 'Load Prescription',
    fn: 'progression.calculate_load()',
    file: 'src/progression.py',
    knowledgeRatio: 80,
    yamlFromSource: [
      'slot.slot_type',
      'slot.sets / reps / intensity',
      'slot.rest_sec',
      'slot.duration_minutes',
      'slot.distance_km',
    ],
    yamlFromTarget: [
      'exercise.id (lookup key in _STARTING_LOADS)',
      'exercise.category (gates RPE vs linear dispatch)',
    ],
    bakedLogic: [
      '_STARTING_LOADS: {exercise_id → {level → kg}} — custom exercises fall back to generic defaults',
      '_LINEAR_INCREMENTS: kg/session per exercise (deadlift: 5.0kg, press: 1.25kg, squat: 2.5kg…)',
      '_SESSIONS_PER_WEEK: assumed training frequency per exercise',
      'Phase load multipliers: build +25%, peak +40%, taper −40% (hardcoded)',
      'Weekly time ramp: +10% per week for time_domain slots',
      'Weekly distance ramp: +8% per week for distance slots',
      'Deload scaling: 60% volume, 80% intensity (hardcoded)',
    ],
    hardcodedValues: [
      '_STARTING_LOADS dict — user-created exercises get generic weight, not exercise-specific',
      '_LINEAR_INCREMENTS dict — same issue',
      'Phase multiplier constants (progression.py:102–127)',
    ],
  },
]

// ─── Extensibility Matrix ─────────────────────────────────────────────────────

type ExtStatus = 'yes' | 'partial' | 'no' | 'n/a'

interface ExtRow {
  type: string
  color: string
  create: ExtStatus
  edit: ExtStatus
  autoUsed: ExtStatus
  gaps: string[]
}

const EXTENSIBILITY: ExtRow[] = [
  {
    type: 'Philosophy',
    color: '#94a3b8',
    create: 'no',
    edit: 'no',
    autoUsed: 'n/a',
    gaps: [
      'No POST /api/philosophies endpoint',
      'No effect on program generation — reference/documentation content only',
      'Fix: one endpoint + loader glob; no engine changes needed',
    ],
  },
  {
    type: 'Framework',
    color: '#8b5cf6',
    create: 'no',
    edit: 'no',
    autoUsed: 'yes',
    gaps: [
      'No POST /api/frameworks endpoint',
      '_CADENCE_OPTIONS in scheduler.py is a hardcoded dict keyed by framework_id — new IDs get no cadence pattern',
      'Fix: move cadence_options into framework YAML; scheduler reads dynamically; add endpoint',
    ],
  },
  {
    type: 'Modality',
    color: '#06b6d4',
    create: 'partial',
    edit: 'no',
    autoUsed: 'yes',
    gaps: [
      'No POST /api/modalities endpoint — but dropping YAML into data/modalities/ works',
      'Scheduler reads recovery_cost, recovery_hours_min, incompatible_in_session_with from YAML generically — new modalities with these fields are placed correctly with no code changes',
      'Fix: just the endpoint. Cheapest win in the whole system.',
    ],
  },
  {
    type: 'Archetype',
    color: '#f97316',
    create: 'yes',
    edit: 'no',
    autoUsed: 'yes',
    gaps: [
      'POST /api/archetypes ✅ exists; stored in data/archetypes/custom/',
      'No PUT or DELETE endpoint',
      'sources field affects scoring — custom archetypes without correct sources score lower',
      'slot_type values not validated on create — unknown type falls back silently',
    ],
  },
  {
    type: 'Exercise',
    color: '#ef4444',
    create: 'yes',
    edit: 'no',
    autoUsed: 'yes',
    gaps: [
      'POST /api/exercises ✅ exists; stored in data/exercises/custom.yaml',
      'No PUT or DELETE endpoint',
      '_STARTING_LOADS and _LINEAR_INCREMENTS in progression.py have no entry for custom exercises — falls back to generic defaults (20/40/60/80kg)',
      'Fix: add optional starting_load and weekly_increment_kg fields to exercise YAML schema',
    ],
  },
  {
    type: 'Goal',
    color: '#f59e0b',
    create: 'no',
    edit: 'no',
    autoUsed: 'n/a',
    gaps: [
      'No POST /api/goals endpoint',
      'Schema is well-defined: id, name, priorities dict, phase_sequence list',
      'Fix: endpoint + priorities-sum validation; no engine changes needed',
    ],
  },
]

// ─── Pipeline Node config ─────────────────────────────────────────────────────

const NODES = [
  { id: 'Philosophy', color: '#94a3b8', count: '5' },
  { id: 'Goal', color: '#f59e0b', count: '7' },
  { id: 'Framework', color: '#8b5cf6', count: '8' },
  { id: 'Modality', color: '#06b6d4', count: '12' },
  { id: 'Archetype', color: '#f97316', count: '25' },
  { id: 'Exercise', color: '#ef4444', count: '198' },
  { id: 'Load', color: '#10b981', count: '—' },
]

// ─── Sub-components ───────────────────────────────────────────────────────────

function StatusIcon({ status }: { status: ExtStatus }) {
  if (status === 'yes') return <CheckCircle2 className="size-4 text-emerald-500" />
  if (status === 'partial') return <AlertCircle className="size-4 text-amber-500" />
  if (status === 'no') return <MinusCircle className="size-4 text-red-500" />
  return <span className="text-xs text-muted-foreground">—</span>
}

function StatusBadge({ status }: { status: ExtStatus }) {
  if (status === 'yes') return <Badge className="text-[10px] bg-emerald-500/15 text-emerald-400 border-emerald-500/30 hover:bg-emerald-500/15">Yes</Badge>
  if (status === 'partial') return <Badge className="text-[10px] bg-amber-500/15 text-amber-500 border-amber-500/30 hover:bg-amber-500/15">Partial</Badge>
  if (status === 'no') return <Badge className="text-[10px] bg-red-500/15 text-red-400 border-red-500/30 hover:bg-red-500/15">No</Badge>
  return <Badge variant="outline" className="text-[10px]">N/A</Badge>
}

function KnowledgeBar({ ratio }: { ratio: number }) {
  return (
    <div className="space-y-1">
      <div className="flex justify-between text-[10px] text-muted-foreground">
        <span className="flex items-center gap-1"><Database className="size-3" /> Data-driven</span>
        <span className="flex items-center gap-1"><Code2 className="size-3" /> Baked logic</span>
      </div>
      <div className="h-2 rounded-full bg-muted overflow-hidden flex">
        <div
          className="h-full bg-sky-500 rounded-l-full transition-all"
          style={{ width: `${100 - ratio}%` }}
        />
        <div
          className="h-full bg-orange-500 rounded-r-full transition-all"
          style={{ width: `${ratio}%` }}
        />
      </div>
      <div className="flex justify-between text-[10px] text-muted-foreground">
        <span>{100 - ratio}%</span>
        <span>{ratio}%</span>
      </div>
    </div>
  )
}

// ─── Main component ───────────────────────────────────────────────────────────

interface Props {
  result?: TracedProgram | null
}

export function ModelInteractionPanel({ result }: Props) {
  const [selectedEdge, setSelectedEdge] = useState<Edge | null>(EDGES[1]) // default: goal→framework
  const [expandedGapRow, setExpandedGapRow] = useState<string | null>(null)

  // Extract live values from trace if available
  const traceWeek0 = result?.generation_trace?.weeks?.[0]
  const liveFramework = traceWeek0?.scheduler_trace?.framework_id as string | undefined
  const liveArchetypes = traceWeek0
    ? Object.values(traceWeek0.sessions ?? {})
        .flat()
        .map((s: any) => s?.archetype_trace?.selected)
        .filter(Boolean) as string[]
    : []

  return (
    <div className="space-y-6 px-6 py-4 max-w-5xl">

      {/* ── Live program context banner ── */}
      {result && (
        <div className="flex flex-wrap items-center gap-2 rounded-md border border-primary/20 bg-primary/5 px-3 py-2 text-xs">
          <span className="text-muted-foreground">Live from last generation:</span>
          {liveFramework && (
            <Badge variant="outline" className="text-[10px] border-violet-500/40 text-violet-400 bg-violet-500/10">
              framework: {liveFramework}
            </Badge>
          )}
          {liveArchetypes.slice(0, 4).map((a, i) => (
            <Badge key={i} variant="outline" className="text-[10px] border-orange-500/40 text-orange-400 bg-orange-500/10">
              {a}
            </Badge>
          ))}
          {liveArchetypes.length > 4 && (
            <span className="text-muted-foreground">+{liveArchetypes.length - 4} more</span>
          )}
        </div>
      )}

      {/* ── Section 1: Pipeline strip ── */}
      <div>
        <h2 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-3">
          Pipeline Interactions
        </h2>
        <div className="overflow-x-auto pb-2">
          <div className="flex items-center gap-0 min-w-max">
            {NODES.map((node, i) => {
              const isLive = node.id === 'Framework' && liveFramework
              return (
                <div key={node.id} className="flex items-center">
                  {/* Node */}
                  <div
                    className={cn(
                      'flex flex-col items-center px-3 py-2 rounded-lg border transition-colors',
                      isLive
                        ? 'border-violet-500/50 bg-violet-500/10'
                        : 'border-border bg-card'
                    )}
                  >
                    <div
                      className="w-2 h-2 rounded-full mb-1.5"
                      style={{ backgroundColor: node.color }}
                    />
                    <span className="text-xs font-semibold text-foreground whitespace-nowrap">
                      {node.id}
                    </span>
                    <span className="text-[10px] text-muted-foreground font-mono mt-0.5">
                      ×{node.count}
                    </span>
                  </div>

                  {/* Arrow + edge button (between nodes) */}
                  {i < NODES.length - 1 && (() => {
                    // Find edges that connect this node to the next
                    const nextNode = NODES[i + 1]
                    const edge = EDGES.find(e =>
                      e.source.includes(node.id) && e.target.includes(nextNode.id)
                    ) ?? EDGES.find(e => e.source.includes(node.id))

                    if (!edge) {
                      return (
                        <div className="flex items-center px-1">
                          <div className="w-6 h-px bg-border" />
                          <ChevronRight className="size-3 text-muted-foreground -ml-1" />
                        </div>
                      )
                    }

                    const isSelected = selectedEdge?.id === edge.id
                    return (
                      <button
                        onClick={() => setSelectedEdge(edge)}
                        className={cn(
                          'flex flex-col items-center px-2 py-1.5 rounded mx-0.5 transition-colors group',
                          isSelected
                            ? 'bg-primary/10 border border-primary/30'
                            : 'hover:bg-muted border border-transparent'
                        )}
                        title={`Click to inspect: ${edge.fn}`}
                      >
                        <div className="flex items-center gap-0.5">
                          <div className="w-3 h-px bg-border group-hover:bg-primary/50 transition-colors" />
                          <ChevronRight className={cn(
                            'size-3 -mx-0.5 transition-colors',
                            isSelected ? 'text-primary' : 'text-muted-foreground group-hover:text-primary/70'
                          )} />
                          <div className="w-3 h-px bg-border group-hover:bg-primary/50 transition-colors" />
                        </div>
                        <span className={cn(
                          'text-[9px] mt-0.5 font-mono whitespace-nowrap transition-colors',
                          isSelected ? 'text-primary' : 'text-muted-foreground group-hover:text-foreground'
                        )}>
                          {edge.fn.split('.')[1]?.split('(')[0] ?? edge.fn}
                        </span>
                        {/* Knowledge ratio mini-bar */}
                        <div className="flex h-0.5 w-10 rounded-full overflow-hidden mt-0.5">
                          <div className="bg-sky-500" style={{ width: `${100 - edge.knowledgeRatio}%` }} />
                          <div className="bg-orange-500" style={{ width: `${edge.knowledgeRatio}%` }} />
                        </div>
                      </button>
                    )
                  })()}
                </div>
              )
            })}
          </div>
        </div>
        <p className="text-[10px] text-muted-foreground mt-1">
          Click any arrow to inspect the transition. <span className="text-sky-400">Blue</span> = data-driven · <span className="text-orange-400">Orange</span> = baked logic.
        </p>
      </div>

      {/* ── Section 2: Edge detail ── */}
      {selectedEdge && (
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm flex items-center gap-2">
              <span className="text-muted-foreground">{selectedEdge.source}</span>
              <ChevronRight className="size-3 text-muted-foreground" />
              <span>{selectedEdge.target}</span>
              <Badge variant="outline" className="ml-auto font-mono text-[10px]">
                {selectedEdge.file}
              </Badge>
            </CardTitle>
            <p className="text-xs font-mono text-primary mt-1">{selectedEdge.fn}</p>
          </CardHeader>
          <CardContent className="grid grid-cols-1 md:grid-cols-2 gap-4">

            {/* YAML properties */}
            <div className="space-y-3">
              <div>
                <p className="text-[10px] font-semibold uppercase tracking-wider text-muted-foreground mb-1.5 flex items-center gap-1">
                  <Database className="size-3" /> From source model
                </p>
                <ul className="space-y-0.5">
                  {selectedEdge.yamlFromSource.map((p, i) => (
                    <li key={i} className="text-xs font-mono text-sky-400 before:content-['·'] before:mr-1.5 before:text-muted-foreground">
                      {p}
                    </li>
                  ))}
                </ul>
              </div>
              <div>
                <p className="text-[10px] font-semibold uppercase tracking-wider text-muted-foreground mb-1.5 flex items-center gap-1">
                  <Database className="size-3" /> From target model
                </p>
                <ul className="space-y-0.5">
                  {selectedEdge.yamlFromTarget.map((p, i) => (
                    <li key={i} className="text-xs font-mono text-sky-400 before:content-['·'] before:mr-1.5 before:text-muted-foreground">
                      {p}
                    </li>
                  ))}
                </ul>
              </div>
            </div>

            {/* Baked logic + ratio */}
            <div className="space-y-3">
              <div>
                <p className="text-[10px] font-semibold uppercase tracking-wider text-muted-foreground mb-1.5 flex items-center gap-1">
                  <Code2 className="size-3" /> Logic in function
                </p>
                <ul className="space-y-1">
                  {selectedEdge.bakedLogic.map((l, i) => (
                    <li key={i} className="text-xs text-foreground/80 before:content-['·'] before:mr-1.5 before:text-orange-400">
                      {l}
                    </li>
                  ))}
                </ul>
              </div>

              {selectedEdge.hardcodedValues && (
                <div>
                  <p className="text-[10px] font-semibold uppercase tracking-wider text-amber-500/80 mb-1.5">
                    Hardcoded — blocks extensibility
                  </p>
                  <ul className="space-y-1">
                    {selectedEdge.hardcodedValues.map((v, i) => (
                      <li key={i} className="text-xs text-amber-500/90 before:content-['⚠'] before:mr-1.5">
                        {v}
                      </li>
                    ))}
                  </ul>
                </div>
              )}

              <KnowledgeBar ratio={selectedEdge.knowledgeRatio} />
            </div>

          </CardContent>
        </Card>
      )}

      {/* ── Section 3: Extensibility matrix ── */}
      <div>
        <h2 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-3">
          Extensibility — can users create new instances?
        </h2>
        <div className="rounded-lg border border-border overflow-hidden">
          <table className="w-full text-xs">
            <thead>
              <tr className="border-b border-border bg-muted/30">
                <th className="text-left px-3 py-2 text-muted-foreground font-medium">Model type</th>
                <th className="px-3 py-2 text-muted-foreground font-medium text-center">Create via API</th>
                <th className="px-3 py-2 text-muted-foreground font-medium text-center">Edit / Delete</th>
                <th className="px-3 py-2 text-muted-foreground font-medium text-center">Auto-used in generation</th>
                <th className="px-3 py-2 text-muted-foreground font-medium text-left">Gaps / Notes</th>
              </tr>
            </thead>
            <tbody>
              {EXTENSIBILITY.map((row, i) => {
                const isExpanded = expandedGapRow === row.type
                return (
                  <tr
                    key={row.type}
                    className={cn(
                      'border-b border-border/50 last:border-0 transition-colors',
                      isExpanded ? 'bg-muted/20' : 'hover:bg-muted/10',
                      i % 2 === 0 ? '' : 'bg-muted/5'
                    )}
                  >
                    <td className="px-3 py-2.5">
                      <div className="flex items-center gap-2">
                        <div className="w-2 h-2 rounded-full shrink-0" style={{ backgroundColor: row.color }} />
                        <span className="font-medium">{row.type}</span>
                      </div>
                    </td>
                    <td className="px-3 py-2.5 text-center">
                      <div className="flex justify-center"><StatusIcon status={row.create} /></div>
                    </td>
                    <td className="px-3 py-2.5 text-center">
                      <div className="flex justify-center"><StatusIcon status={row.edit} /></div>
                    </td>
                    <td className="px-3 py-2.5 text-center">
                      <div className="flex justify-center">
                        {row.autoUsed === 'n/a'
                          ? <span className="text-[10px] text-muted-foreground">N/A</span>
                          : <StatusIcon status={row.autoUsed} />}
                      </div>
                    </td>
                    <td className="px-3 py-2.5">
                      <button
                        className="flex items-start gap-1.5 text-left group w-full"
                        onClick={() => setExpandedGapRow(isExpanded ? null : row.type)}
                      >
                        <div className="flex flex-wrap gap-1 flex-1">
                          <StatusBadge status={row.create} />
                          {(row.create === 'no' || row.create === 'partial' || row.edit === 'no') && (
                            <span className="text-[10px] text-muted-foreground group-hover:text-foreground transition-colors">
                              {isExpanded ? '▲ hide gaps' : '▼ show gaps'}
                            </span>
                          )}
                        </div>
                      </button>
                      {isExpanded && (
                        <ul className="mt-2 space-y-1 pl-1">
                          {row.gaps.map((g, gi) => (
                            <li
                              key={gi}
                              className={cn(
                                'text-[11px] leading-relaxed',
                                g.includes('✅') ? 'text-emerald-400' :
                                g.startsWith('Fix:') ? 'text-primary' :
                                'text-muted-foreground'
                              )}
                            >
                              {g.startsWith('Fix:')
                                ? <><span className="text-primary font-medium">Fix: </span>{g.slice(5)}</>
                                : g}
                            </li>
                          ))}
                        </ul>
                      )}
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
        <p className="text-[10px] text-muted-foreground mt-2">
          Full gap analysis and priority order: <code className="bg-muted px-1 rounded">docs/model-generalization-gaps.md</code>
        </p>
      </div>

    </div>
  )
}
