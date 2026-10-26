import { useState } from 'react'
import { ChevronRight, Code2, Database, AlertCircle, CheckCircle2, MinusCircle } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { cn } from '@/lib/utils'
import type { TracedProgram } from '@/api/types'
import { useOntology } from '@/api/ontology'

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
    fn: 'goals.philosophy_to_goal(track_id) + generator._build_phase_entries()',
    file: 'src/goals.py + src/phases.py + src/scheduler.py',
    knowledgeRatio: 40,
    yamlFromSource: [
      'tracks[] (ways to follow the philosophy; the builder picks one)',
      'tracks[].phases[] (the philosophy\'s own phases: id, name, kind, weeks, framework_id, text)',
      'primary_track_id (default track)',
      'bias (fallback priorities)',
    ],
    yamlFromTarget: [
      'applicable_when conditions',
      'min/max days_per_week',
      'sessions_per_week',
      'expectations (min/ideal weeks, days, session minutes, split support)',
    ],
    bakedLogic: [
      'Philosophy mode creates synthetic goal internally via api._philosophy_to_goal() (not exposed to user)',
      'Track phases → phase timeline; every week runs the framework its phase names',
      'Phase kind (data/commons/phase_kinds.yaml) drives archetype filters, multipliers and cadence',
      'A legacy framework_id maps to the track and phase that run it',
      'Priorities derived from the track\'s longest phase framework sessions_per_week, or philosophy.bias as fallback',
      'No standalone goal YAML files — goals deprecated in favor of direct philosophy → framework flow',
    ],
  },
  {
    id: 'framework-modality',
    source: 'Framework + Philosophy',
    target: 'Modality Schedule',
    fn: 'scheduler.allocate_sessions() + assign_to_days()',
    file: 'src/scheduler.py (week_template.plan_week, training_contract._placements place their own)',
    knowledgeRatio: 70,
    yamlFromSource: [
      'synthetic_goal.priorities (modality weights, derived from philosophy.bias or framework)',
      'synthetic_goal.phase_sequence[].priority_override',
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
      'Recovery windows: a modality\'s recovery_hours_min from itself, 48 h between two high-cost modalities; checked both ways and against last week\'s end (_neighbours); framework recovery.allow_consecutive lifts a pair',
      'Days come from framework.cadence_options (rotating week to week); phase kinds that spread_cadence take the first pattern; _DEFAULT_SPREAD without one',
      'Incompatibility: no two incompatible_in_session_with modalities share a day',
      'Templated phases and training contracts place their own sessions (every shipped package)',
    ],
    hardcodedValues: [
      '_RECOVERY_COST_RANK dict — only 3 cost levels recognised',
      'The 48 h high-cost window (the modality schema says recovery_hours_min governs it)',
    ],
  },
  {
    id: 'modality-archetype',
    source: 'Modality',
    target: 'Archetype',
    fn: 'selector.select_archetype()',
    file: 'src/selector.py',
    knowledgeRatio: 50,
    yamlFromSource: ['modality id (primary filter)', 'recent sessions (archetype ids, heavy body regions)'],
    yamlFromTarget: [
      'applicable_phases',
      'training_levels',
      'required_equipment',
      'scaling.equipment_limited',
      'scaling.time_limited',
      'duration_estimate_minutes',
      'slots → regional load (data/commons/recovery_regions.yaml; regional_load overrides)',
    ],
    bakedLogic: [
      'Runs only for a session left to choose: template days, contract modules and tests are placed, not scored',
      'Scoring: +6 full equipment satisfied, −3 if used in the last 14 (flat), ±3/−2 day fit, up to −8 injury impact, −10 per slot whose category the equipment blocks, +10 the split day\'s mobility hint, −2/−1 per body region a session a day/two days before loaded heavily (cap −4)',
      'Ties: the least recently used, then the first authored',
      'Equipment-limited fallback: use archetype with scaling flag if preferred is blocked by equipment',
      'Time-limited fallback: use shorter archetype variant if session time is insufficient',
    ],
  },
  {
    id: 'archetype-exercise',
    source: 'Archetype Slot',
    target: 'Exercise',
    fn: 'selector.select_exercise()',
    file: 'src/selector.py',
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
      'Candidates: the archetype\'s own package plus those its philosophy borrows from (provenance); slot exercise_ids (in order when ordered), else movement_pattern aliases (data/commons/movement_patterns.yaml) and category',
      'Level prerequisites: requires resolved transitively against the level\'s concepts (_LEVEL_CONCEPTS) and level_seeds.yaml',
      'Slot constraints: AMRAP/for_time slots reject skill, mobility and rehab; zone1–2 aerobic slots keep low effort; phase exclude_exercises',
      'Scoring: −2 per recent use (last 40), +0.5 for unlocks (not in a slot that names its exercises), +0.5 for defined movement_patterns; ties to the first authored (least recently used first in a slot that names its exercises)',
      'Main lifts (heavy sets × reps) keep one exercise through a phase unless it rotate_main_lifts',
      'Taper phase: max-effort exercises excluded entirely',
    ],
    hardcodedValues: [
      '_LEVEL_CONCEPTS — the concepts each training level knows',
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
      'exercise.starting_load_kg (by level) and weekly_increment_kg',
      'exercise.category (gates RPE vs linear dispatch)',
    ],
    bakedLogic: [
      'Model: the framework\'s progression_overrides for the modality, else the modality\'s progression_model',
      'Loads from the exercise YAML; _DEFAULT_INCREMENT_KG (2.5 kg) is the only code default',
      '_SESSIONS_PER_WEEK: assumed training frequency per exercise',
      'Time and distance ceilings: the phase kind\'s volume_multiplier (data/commons/phase_kinds.yaml)',
      'Deload: the framework\'s deload_protocol.volume_reduction_pct is the share kept (0.6 without one); a taper kind\'s share is the total',
      'as_written slots (template days, tests) are prescribed exactly as the source writes them',
    ],
    hardcodedValues: [
      '_SESSIONS_PER_WEEK dict',
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
      'Tracks replaced framework_groups and canonical_phase_sequence; validate_entities checks track/phase ids and ownership',
      'No effect on program generation when used standalone — must be paired with frameworks',
      'Fix: add POST endpoint with the same track validation (src/phases.validate_philosophy_tracks)',
    ],
  },
  {
    type: 'Framework',
    color: '#8b5cf6',
    create: 'no',
    edit: 'partial',
    autoUsed: 'yes',
    gaps: [
      'No POST /api/frameworks endpoint — can only edit existing frameworks',
      'PUT /api/frameworks/<id> ✅ exists for updates',
      'cadence_options lives in the framework YAML (a framework without one gets the default spread)',
      'expectations field is now REQUIRED per schema — must be present in YAML',
      'Fix: add POST endpoint',
    ],
  },
  {
    type: 'Modality',
    color: '#06b6d4',
    create: 'partial',
    edit: 'no',
    autoUsed: 'yes',
    gaps: [
      'POST /api/modalities ✅ exists (authoring enabled)',
      'Scheduler reads recovery_cost, recovery_hours_min, incompatible_in_session_with from YAML generically — new modalities with these fields are placed correctly with no code changes',
      'No PUT endpoint for an existing modality',
    ],
  },
  {
    type: 'Archetype',
    color: '#f97316',
    create: 'yes',
    edit: 'yes',
    autoUsed: 'yes',
    gaps: [
      'POST /api/archetypes ✅ exists; stored in data/packages/custom/archetypes/',
      'PUT /api/archetypes/<id> ✅ exists for updates',
      'DELETE /api/archetypes/<id> ✅ (custom package only)',
      'Regional load is derived from its slots; one that names no exercises needs regional_load',
      'slot_type values not validated on create — unknown type falls back silently',
    ],
  },
  {
    type: 'Exercise',
    color: '#ef4444',
    create: 'yes',
    edit: 'yes',
    autoUsed: 'yes',
    gaps: [
      'POST /api/exercises ✅ exists; stored in the custom package',
      'PUT /api/exercises/<id> ✅ exists for updates',
      'DELETE /api/exercises/<id> ✅ (custom package only)',
      'Loads come from its starting_load_kg / weekly_increment_kg; without them, generic defaults',
      'A movement pattern recovery_regions.yaml does not list loads no body region (test_recovery_regions.py fails on it)',
    ],
  },
  {
    type: 'Goal',
    color: '#f59e0b',
    create: 'no',
    edit: 'no',
    autoUsed: 'no',
    gaps: [
      '⚠️ DEPRECATED — Goals removed from system (April 2026)',
      'Programs now generated directly from philosophies (no goal intermediary)',
      'Synthetic goals generated internally by api._philosophy_to_goal() for backward compatibility',
      'All goal YAML files deleted; domain expertise preserved in docs/philosophy-blends.md',
      'No API endpoints: POST/PUT/DELETE all removed',
    ],
  },
]

// ─── Pipeline Node config ─────────────────────────────────────────────────────

interface NodeCounts {
  Philosophy: number
  Framework: number
  Modality: number
  Archetype: number
  Exercise: number
}

function getNodes(counts: NodeCounts) {
  return [
    { id: 'Philosophy', color: '#94a3b8', count: String(counts.Philosophy) },
    { id: 'Framework', color: '#8b5cf6', count: String(counts.Framework) },
    { id: 'Modality', color: '#06b6d4', count: String(counts.Modality) },
    { id: 'Archetype', color: '#f97316', count: String(counts.Archetype) },
    { id: 'Exercise', color: '#ef4444', count: String(counts.Exercise) },
    { id: 'Load', color: '#10b981', count: '—' },
  ]
}

// ─── Sub-components ───────────────────────────────────────────────────────────

function StatusIcon({ status }: { status: ExtStatus }) {
  if (status === 'yes') return <CheckCircle2 className="size-4 text-emerald-700 dark:text-emerald-300" />
  if (status === 'partial') return <AlertCircle className="size-4 text-amber-700 dark:text-amber-300" />
  if (status === 'no') return <MinusCircle className="size-4 text-red-700 dark:text-red-300" />
  return <span className="text-xs text-muted-foreground">—</span>
}

function StatusBadge({ status }: { status: ExtStatus }) {
  if (status === 'yes') return <Badge className="text-[10px] bg-emerald-500/15 text-emerald-700 dark:text-emerald-300 border-emerald-500/30 hover:bg-emerald-500/15">Yes</Badge>
  if (status === 'partial') return <Badge className="text-[10px] bg-amber-500/15 text-amber-700 dark:text-amber-300 border-amber-500/30 hover:bg-amber-500/15">Partial</Badge>
  if (status === 'no') return <Badge className="text-[10px] bg-red-500/15 text-red-700 dark:text-red-300 border-red-500/30 hover:bg-red-500/15">No</Badge>
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

  // Fetch ontology data for dynamic counts
  const { data: ontology } = useOntology()

  // Compute dynamic counts with fallback to hardcoded values
  const dynamicCounts: NodeCounts = ontology ? {
    Philosophy: ontology.philosophies.length,
    Framework: ontology.frameworks.length,
    Modality: ontology.modalities.length,
    Archetype: ontology.archetypes.length,
    Exercise: ontology.exercises.length,
  } : {
    Philosophy: 11,
    Framework: 16,
    Modality: 12,
    Archetype: 25,
    Exercise: 198,
  }

  const NODES = getNodes(dynamicCounts)

  // Extract live values from trace if available
  const traceWeek0 = result?.generation_trace?.weeks?.[0]
  const liveFramework = traceWeek0?.scheduler?.framework_selection?.selected_id as string | undefined
  const liveArchetypes = traceWeek0
    ? Object.values(traceWeek0.sessions ?? {})
        .flat()
        .map((s) => (s as { archetype_trace?: { selected?: string } })?.archetype_trace?.selected)
        .filter(Boolean) as string[]
    : []

  return (
    <div className="space-y-6 px-6 py-4 max-w-5xl">

      {/* ── Live program context banner ── */}
      {result && (
        <div className="flex flex-wrap items-center gap-2 rounded-md border border-primary/20 bg-primary/5 px-3 py-2 text-xs">
          <span className="text-muted-foreground">Live from last generation:</span>
          {liveFramework && (
            <Badge variant="outline" className="text-[10px] border-violet-500/40 text-violet-700 dark:text-violet-300 bg-violet-500/10">
              framework: {liveFramework}
            </Badge>
          )}
          {liveArchetypes.slice(0, 4).map((a, i) => (
            <Badge key={i} variant="outline" className="text-[10px] border-orange-500/40 text-orange-700 dark:text-orange-300 bg-orange-500/10">
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
          Click any arrow to inspect the transition. <span className="text-sky-700 dark:text-sky-300">Blue</span> = data-driven · <span className="text-orange-700 dark:text-orange-300">Orange</span> = baked logic.
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
                    <li key={i} className="text-xs font-mono text-sky-700 dark:text-sky-300 before:content-['·'] before:mr-1.5 before:text-muted-foreground">
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
                    <li key={i} className="text-xs font-mono text-sky-700 dark:text-sky-300 before:content-['·'] before:mr-1.5 before:text-muted-foreground">
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
                  <p className="text-[10px] font-semibold uppercase tracking-wider text-amber-700/80 dark:text-amber-300/80 mb-1.5">
                    Hardcoded — blocks extensibility
                  </p>
                  <ul className="space-y-1">
                    {selectedEdge.hardcodedValues.map((v, i) => (
                      <li key={i} className="text-xs text-amber-700/90 dark:text-amber-300/90 before:content-['⚠'] before:mr-1.5">
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
                                g.includes('✅') ? 'text-emerald-700 dark:text-emerald-300' :
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
