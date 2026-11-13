import { useState, type ReactNode } from 'react'
import { ChevronRight, Code2, Database, AlertCircle, CheckCircle2, MinusCircle } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { cn } from '@/lib/utils'
import type { TracedProgram } from '@/api/types'
import { useOntology } from '@/api/ontology'

// ─── Data ─────────────────────────────────────────────────────────────────────
// The edges describe the engine, not a package, so they stay written here;
// checked against src/ on 2026-10-30 (and after roadmap 9.3 moved four tables to data). They describe the
// modality scheduler, which no shipped package runs on any more (roadmap 20.11 serves the map from data).
// What a package can and cannot bring is the server's, on Builder readiness (ReadinessPanel.tsx).

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
    file: 'src/goals.py + src/phases.py + src/generator.py',
    knowledgeRatio: 30,
    yamlFromSource: [
      'tracks[] (ways to follow the philosophy; the builder picks one)',
      'tracks[].phases[] (id, name, kind, weeks, framework_id, text)',
      'phase rules the generator reads: priority_override, exclude_exercises, rotate_main_lifts, tests, week_templates, drop_order',
      'track_for_level, then primary_track_id, then the first track',
      'bias (else scope) — fallback priorities',
      'training_contract.yaml — the track\'s contract, when the package has one',
      'training_contract.yaml tracks.<id>.options — choices the athlete makes for the track, each with a default (Wildman\'s swing minutes); both builders ask',
      'fidelity.yaml inventions — a track the app made up rather than the source is labelled in both builders',
    ],
    yamlFromTarget: [
      'sessions_per_week',
      'expectations (ideal days and session minutes are read)',
      'applicable_when + days_per_week — only for a goal whose phase names no framework',
    ],
    bakedLogic: [
      'goals.philosophy_to_goal builds the synthetic goal (api._philosophy_to_goal wraps it; never shown to the user)',
      'Track phases → phase timeline; every week runs the framework its phase names (phases.week_entry)',
      'Phase kind (data/commons/phase_kinds.yaml) drives archetype filters, multipliers, cadence spreading and the deload reading',
      'A legacy framework_id maps to the track and phase that run it (goals.owner_track_for_framework)',
      'Priorities from the longest phase\'s framework sessions_per_week (the first wins a tie), else the bias',
      'The goal carries the track\'s training contract; a blend drops it and composes lanes (src/composition.py)',
      'The athlete\'s answers ride in the constraints as contract_options; an option left out, or a choice it does not offer, takes its default',
    ],
  },
  {
    id: 'framework-modality',
    source: 'Framework + Philosophy',
    target: 'Modality Schedule',
    fn: 'scheduler.allocate_sessions() + assign_to_days()',
    file: 'src/scheduler.py (week_template.plan_week, training_contract._placements place their own)',
    knowledgeRatio: 65,
    yamlFromSource: [
      'synthetic_goal.priorities (modality weights)',
      'phase_sequence[].priority_override — matched on the phase kind, so two phases of one kind share the first\'s',
      'framework.sessions_per_week, allocation_mode, modality_priority (committed / core)',
      'framework.cadence_options (rotating week to week)',
      'framework.deload_protocol.frequency_weeks',
      'framework.recovery.allow_consecutive (+ phases)',
    ],
    yamlFromTarget: [
      'recovery_cost (high/medium/low)',
      'recovery_hours_min',
      'incompatible_in_session_with',
      'session_position',
      'priority_tier (kept when days are scarce), typical_duration_minutes',
    ],
    bakedLogic: [
      'Largest-remainder rounding converts priority weights → integer session counts',
      '_RECOVERY_COST_RANK {high:3, medium:2, low:1} — placement order; an unknown cost counts as low',
      'Recovery windows: a modality\'s own recovery_hours_min (24 h without one); two high-cost modalities max(48 h, either\'s); checked both ways and against last week\'s end (_neighbours)',
      'recovery.allow_consecutive lifts a pair whose window is 24 h or less',
      'Days from cadence_options; a phase kind that spreads cadence takes the first pattern; _DEFAULT_SPREAD without one',
      'Incompatibility: no two incompatible_in_session_with modalities share a day',
      'Templated phases and training contracts place their own sessions — every shipped single-philosophy track',
    ],
    hardcodedValues: [
      '_RECOVERY_COST_RANK — only 3 cost levels recognised',
      '_HIGH_COST_FLOOR_HOURS = 48 (the modality schema agrees: never under 48)',
      'Day scoring (+3, −6, ×1.25, −12 a session), allocation thresholds 0.8 / 0.7, 75 ideal minutes',
    ],
  },
  {
    id: 'modality-archetype',
    source: 'Modality',
    target: 'Archetype',
    fn: 'selector.select_archetype()',
    file: 'src/selector.py',
    knowledgeRatio: 50,
    yamlFromSource: ['modality id (primary filter)', 'recent sessions (the last 14 archetype ids, heavy body regions)'],
    yamlFromTarget: [
      'applicable_phases',
      'training_levels',
      'required_equipment',
      'scaling.equipment_limited',
      'scaling.time_limited',
      'duration_estimate_minutes (and scaling.deload\'s)',
      'pool_only / test-only — never picked by modality',
      'modality fallback_rank, or the framework\'s fallback_modalities — the cross-modality fallback order',
      'data/commons/constraints/category_equipment.yaml — the equipment each exercise category needs',
      'slots → regional load (data/commons/recovery_regions.yaml; regional_load overrides)',
    ],
    bakedLogic: [
      'Runs only for a session left to choose: template days, contract modules and tests are placed, not scored',
      'Scoring: +6 full equipment, −3 if in the last 14, +3/−2 day fit, up to −8 injury impact, −10 per slot whose category the equipment blocks, +10 the preferred (split-day) archetype',
      'Regional load: −2/−1 per body region a session a day/two days before loaded heavily, cap −4 (recovery_regions.yaml)',
      'Ties: the least recently used, then the first authored',
      'scaling.equipment_limited (or the generator\'s relaxed pass) lets an archetype past the equipment filter, without the +6',
      'scaling.time_limited lets an over-long archetype through; with none fitting, the shortest is kept and trimmed to the session (populate_session)',
      'No archetype for the phase: fall back in the framework\'s or the modalities\' order (aerobic_base → durability → mobility), recorded as substituted_for',
    ],
    hardcodedValues: [
      'Short-day cap 50 min (api TIME_MAP short 40 / long 75)',
    ],
  },
  {
    id: 'archetype-exercise',
    source: 'Archetype Slot',
    target: 'Exercise',
    fn: 'selector.select_exercise()',
    file: 'src/selector.py',
    knowledgeRatio: 55,
    yamlFromSource: [
      'slot.slot_type',
      'slot.exercise_filter: exercise_ids, ordered, movement_pattern, category, bilateral, equipment_required, exclude_movement_pattern, intensity',
      'slot.intensity (heavy sets × reps make a main lift)',
    ],
    yamlFromTarget: [
      'movement_patterns',
      'category',
      'equipment',
      'requires / unlocks',
      'contraindicated_with',
      'effort',
      'named_only / test_only',
      'data/commons/movement_patterns.yaml complements — what a complementary mobility block recovers',
      'data/commons/training_levels.yaml — the level order, and the level that unlocks everything',
      'data/commons/intensities.yaml — the intensities that make a main lift',
    ],
    bakedLogic: [
      'Candidates: the goal\'s packages and those they borrow from (provenance), plus unattributed exercises; the whole library only under a non-strict policy',
      'exercise_ids (in order when ordered), movement_pattern aliases (data/commons/movement_patterns.yaml) and category filter together',
      'Level prerequisites: requires resolved transitively against data/commons/level_concepts.yaml and the package\'s level_seeds.yaml',
      'Slot constraints: AMRAP / for_time slots reject skill, mobility and rehab; zone1–2 aerobic slots keep low effort; phase exclude_exercises',
      'Scoring: −2 per recent use (last 40), +0.5 for unlocks (not in a slot that names its exercises), +0.5 for defined movement_patterns; ties to the first authored',
      'Main lifts (heavy sets × reps) keep one exercise through a phase unless it rotate_main_lifts',
      'A phase kind that excludes_max_effort (taper) drops effort: max exercises',
    ],
    hardcodedValues: [],
  },
  {
    id: 'exercise-progression',
    source: 'Exercise + Slot',
    target: 'Load Prescription',
    fn: 'progression.calculate_load()',
    file: 'src/progression.py',
    knowledgeRatio: 75,
    yamlFromSource: [
      'slot.slot_type',
      'slot.sets / reps / intensity / rpe_target',
      'slot.rest_sec, work_sec, time_cap_sec, hold_seconds',
      'slot.duration_minutes / duration_sec',
      'slot.distance_m',
      'slot.scaling.intensity_pct / volume_multiplier',
      'slot.load (as written), slot.standard (a test\'s scored slot)',
      'slot.switch_at_sec, rest_until_hr_pct (watch cues)',
      'block.alternate {exercise_id, when} — an EMOM block\'s even rounds another movement when the track\'s options say so',
    ],
    yamlFromTarget: [
      'exercise.starting_load_kg (by level), weekly_increment_kg and sessions_per_week',
      'exercise.competition_pace',
      'exercise.category — only for the no-start-load note',
      'data/commons/progression.yaml — RPE load factors and the weekly ramps (a framework\'s progression_defaults overrides them)',
      'data/commons/training_levels.yaml — each level\'s share of a distance slot',
      'data/commons/intensities.yaml — which intensities prescribe heart-rate zones, and their bands',
    ],
    bakedLogic: [
      'Model (training_contract.resolve_model): the framework\'s progression_overrides for the modality, its own model when prescription_policy is framework, else the modality\'s, else linear_load',
      'Dispatch by model and slot type',
      'Time and distance ceilings: the phase kind\'s volume_multiplier (data/commons/phase_kinds.yaml)',
      'Deload: deload_protocol.volume_reduction_pct is the share kept; a counts_as_deload kind\'s share is the total',
      'as_written frameworks and a test\'s scored slot (standard_tests.protocol_load) are prescribed exactly as the source writes them',
      'An alternating interval (Wildman\'s Option C): odd rounds the block\'s movement, even rounds its alternate if the athlete\'s equipment and injuries allow it; the load carries alternate, its note leads with it, and both watches title each round (alternateName)',
    ],
    hardcodedValues: [
      '_DEFAULT_INCREMENT_KG 2.5 and the other defaults: 3 × 5, deload share 0.6, density 0.70 / 0.75, AMRAP 1200 s',
    ],
  },
]

// ─── Authoring ────────────────────────────────────────────────────────────────

type ExtStatus = 'yes' | 'partial' | 'no' | 'n/a'

interface AuthoringRow {
  type: string
  color: string
  create: ExtStatus
  edit: ExtStatus
  remove: ExtStatus
  writes: string
  notes: string[]
}

// Every write route needs a signed-in user and AUTHORING_ENABLED (an empty
// SUPABASE_URL — local dev — enables them without it) and is validated
// against docs/schemas (422 with the errors). api.py.
const AUTHORING: AuthoringRow[] = [
  {
    type: 'Philosophy (tracks, phases)',
    color: '#94a3b8',
    create: 'no',
    edit: 'no',
    remove: 'no',
    writes: '—',
    notes: [
      'No route; the file is written by hand or through the MCP server',
      'src/phases.validate_philosophy_tracks checks track and phase ids (validate_entities.py)',
    ],
  },
  {
    type: 'Framework',
    color: '#8b5cf6',
    create: 'no',
    edit: 'partial',
    remove: 'no',
    writes: 'the custom package only',
    notes: [
      'PUT /api/frameworks/<id> ✅ — name, source_philosophy, sessions_per_week, cadence_options, deload_protocol, applicable_when, notes, recovery — custom package only',
      'No POST, no DELETE',
    ],
  },
  {
    type: 'Modality',
    color: '#06b6d4',
    create: 'yes',
    edit: 'no',
    remove: 'no',
    writes: 'data/commons/modalities/ (shared)',
    notes: [
      'POST /api/modalities ✅',
      'A new modality needs its display block and tools/gen_client_vocab.py for every client\'s colours, labels and icons',
    ],
  },
  {
    type: 'Archetype',
    color: '#f97316',
    create: 'yes',
    edit: 'yes',
    remove: 'yes',
    writes: 'the custom package only',
    notes: [
      'POST, PUT, DELETE /api/archetypes ✅ — the custom package only (403 elsewhere)',
      'slot_type is a schema enum, checked on create and edit',
    ],
  },
  {
    type: 'Exercise',
    color: '#ef4444',
    create: 'yes',
    edit: 'yes',
    remove: 'yes',
    writes: 'the custom package only',
    notes: [
      'POST, PUT, DELETE /api/exercises ✅ — the custom package only (403 elsewhere)',
      'Loads come from starting_load_kg / weekly_increment_kg / sessions_per_week; without them, generic defaults',
    ],
  },
  {
    type: 'Other package files',
    color: '#64748b',
    create: 'no',
    edit: 'no',
    remove: 'no',
    writes: '—',
    notes: [
      'No route for analytics, watch, level_seeds, exercise_media, training_contract, fidelity, source_weeks or the standards',
    ],
  },
  {
    type: 'MCP server',
    color: '#10b981',
    create: 'yes',
    edit: 'yes',
    remove: 'yes',
    writes: 'any file under data/packages/',
    notes: [
      'mcp_server.py: write_package_file, validate_package, delete_package — local, inside the packages folder',
      'Checks every file kind with the gates\' own validator, and a package with add_package\'s checks (docs/mcp/README.md)',
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

function SectionTitle({ children }: { children: ReactNode }) {
  return (
    <h2 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-3">
      {children}
    </h2>
  )
}

// ─── Main component ───────────────────────────────────────────────────────────

interface Props {
  result?: TracedProgram | null
}

export function ModelInteractionPanel({ result }: Props) {
  const [selectedEdge, setSelectedEdge] = useState<Edge | null>(EDGES[1])
  const [expandedRow, setExpandedRow] = useState<string | null>(null)

  // Fetch ontology data for dynamic counts
  const { data: ontology } = useOntology()

  const counts: NodeCounts | null = ontology ? {
    Philosophy: ontology.philosophies.length,
    Framework: ontology.frameworks.length,
    Modality: ontology.modalities.length,
    Archetype: ontology.archetypes.length,
    Exercise: ontology.exercises.length,
  } : null

  const NODES = counts
    ? getNodes(counts)
    : getNodes({ Philosophy: 0, Framework: 0, Modality: 0, Archetype: 0, Exercise: 0 }).map(n => ({ ...n, count: '—' }))

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
    <div className="space-y-6 px-4 md:px-6 py-4 max-w-5xl">

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

      {/* ── Section 2: Pipeline strip ── */}
      <div>
        <SectionTitle>Pipeline Interactions</SectionTitle>
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

      {/* ── Edge detail ── */}
      {selectedEdge && (
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm flex flex-wrap items-center gap-2">
              <span className="text-muted-foreground">{selectedEdge.source}</span>
              <ChevronRight className="size-3 text-muted-foreground" />
              <span>{selectedEdge.target}</span>
              <Badge variant="outline" className="md:ml-auto font-mono text-[10px] whitespace-normal">
                {selectedEdge.file}
              </Badge>
            </CardTitle>
            <p className="text-xs font-mono text-primary mt-1 break-all">{selectedEdge.fn}</p>
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
                    Hardcoded — the same for every package
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

      {/* ── Section 3: Authoring ── */}
      <div>
        <SectionTitle>Authoring — what the API can write</SectionTitle>
        <div className="rounded-lg border border-border overflow-x-auto">
          <table className="w-full text-xs min-w-[640px]">
            <thead>
              <tr className="border-b border-border bg-muted/30">
                <th className="text-left px-3 py-2 text-muted-foreground font-medium">Model type</th>
                <th className="px-3 py-2 text-muted-foreground font-medium text-center">Create</th>
                <th className="px-3 py-2 text-muted-foreground font-medium text-center">Edit</th>
                <th className="px-3 py-2 text-muted-foreground font-medium text-center">Delete</th>
                <th className="text-left px-3 py-2 text-muted-foreground font-medium">Writes to</th>
                <th className="text-left px-3 py-2 text-muted-foreground font-medium">Notes</th>
              </tr>
            </thead>
            <tbody>
              {AUTHORING.map((row, i) => {
                const isExpanded = expandedRow === row.type
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
                    <td className="px-3 py-2.5"><div className="flex justify-center"><StatusIcon status={row.create} /></div></td>
                    <td className="px-3 py-2.5"><div className="flex justify-center"><StatusIcon status={row.edit} /></div></td>
                    <td className="px-3 py-2.5"><div className="flex justify-center"><StatusIcon status={row.remove} /></div></td>
                    <td className="px-3 py-2.5 text-[11px] text-muted-foreground">{row.writes}</td>
                    <td className="px-3 py-2.5">
                      <button
                        className="text-[10px] text-muted-foreground hover:text-foreground transition-colors"
                        onClick={() => setExpandedRow(isExpanded ? null : row.type)}
                      >
                        {isExpanded ? '▲ hide' : '▼ show'}
                      </button>
                      {isExpanded && (
                        <ul className="mt-2 space-y-1 pl-1">
                          {row.notes.map((n, ni) => (
                            <li
                              key={ni}
                              className={cn(
                                'text-[11px] leading-relaxed',
                                n.includes('✅') ? 'text-emerald-700 dark:text-emerald-300' : 'text-muted-foreground'
                              )}
                            >
                              {n}
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
          Every write route needs a signed-in user and <code className="bg-muted px-1 rounded">AUTHORING_ENABLED</code> (local
          dev enables them) and is checked against <code className="bg-muted px-1 rounded">docs/schemas</code>.
          The gaps and the order they close in: <code className="bg-muted px-1 rounded">docs/roadmap.md</code> items 9 and 20 —
          Builder readiness.
        </p>
      </div>

    </div>
  )
}
