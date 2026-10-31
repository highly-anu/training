// ─── Enumerations ─────────────────────────────────────────────────────────────

/**
 * The modality ids and the shared phase kinds (data/commons/modalities,
 * data/commons/phase_kinds.yaml), generated from the commons by
 * tools/gen_client_vocab.py. A philosophy names and describes its own phases;
 * each declares one of these kinds, which is what the engine and the colour
 * palette key on. Never shown as a phase's description.
 */
export type { ModalityId, PhaseKind } from '@/lib/gen/clientVocab'
import type { EquipmentId, ModalityId, PhaseKind } from '@/lib/gen/clientVocab'

/** @deprecated the phase kind; use PhaseKind. */
export type TrainingPhase = PhaseKind

export type TrainingLevel = 'novice' | 'intermediate' | 'advanced' | 'elite'

export type FatigueState = 'fresh' | 'normal' | 'accumulated' | 'overreached'

/** The equipment ids (data/commons/constraints/equipment.yaml), generated. */
export type { EquipmentId } from '@/lib/gen/clientVocab'

export type InjuryFlagId =
  | 'knee_meniscus_post_op'
  | 'shoulder_impingement'
  | 'shoulder_instability'
  | 'lumbar_disc'
  | 'ankle_sprain'
  | 'wrist_injury'
  | 'hip_flexor_strain'
  | 'tennis_elbow'
  | 'golfers_elbow'
  | 'neck_strain'
  | 'achilles_tendinopathy'
  | 'patellar_tendinopathy'

export type EffortLevel = 'low' | 'medium' | 'high' | 'max'

export type EquipmentProfileId =
  | 'barbell_gym'
  | 'home_kb_only'
  | 'bodyweight_only'
  | 'outdoor_ruck_only'
  | 'home_barbell'

// ─── Weekly Schedule ───────────────────────────────────────────────────────────

export type Day = 'Monday' | 'Tuesday' | 'Wednesday' | 'Thursday' | 'Friday' | 'Saturday' | 'Sunday'

export type SessionType = 'rest' | 'short' | 'long' | 'mobility'

export interface DaySchedule {
  session1: SessionType
  session2: SessionType
  session3: SessionType
  session4: SessionType
}

// ─── Goal Profile ──────────────────────────────────────────────────────────────

export type GoalPriorities = Partial<Record<ModalityId, number>>

/** One phase on a goal's phase_sequence: the kind plus the philosophy's own phase. */
export interface PhaseEntry {
  phase: PhaseKind
  phase_id?: string
  name?: string
  weeks: number
  framework_id?: string | null
  focus?: string
  description?: string
  adaptations?: string[]
  intensity?: string
  repeatable?: boolean
  priority_override?: GoalPriorities
}

/** The track a goal was built from. */
export interface GoalTrack {
  id: string
  name: string
  description?: string | null
  philosophy_id: string
}

/** One track of a composed program (src/composition.py), with its own phases. */
export interface GoalCompositionTrack {
  lane_key: string
  philosophy_id: string
  id: string
  name: string
  weight: number
  kind: 'contract' | 'template'
  description?: string | null
  phase_sequence: PhaseEntry[]
}

export interface FrameworkSelection {
  default_framework: string
  alternatives: Array<{ framework_id: string; condition: string }>
}

export interface GoalProfile {
  id: string
  name: string
  description: string
  priorities: GoalPriorities
  primary_sources: string[]
  phase_sequence: PhaseEntry[]
  track?: GoalTrack
  /** A composed program's tracks, the lead first (`track` and `phase_sequence` are its). */
  tracks?: GoalCompositionTrack[]
  minimum_prerequisites: Record<string, number>
  incompatible_with: Array<string | { goal_id: string; reason?: string }>
  framework_selection: FrameworkSelection
  event_date?: string | null
  notes?: string
  expectations?: GoalExpectations
}

export interface GoalExpectations {
  min_weeks: number
  ideal_weeks: number
  min_days_per_week: number
  ideal_days_per_week: number
  min_session_minutes: number
  ideal_session_minutes: number        // typical session length (most days)
  ideal_long_session_minutes?: number  // weekly long effort, if the goal has one
  supports_split_days: boolean
  notes?: string
}

// ─── Constraints ──────────────────────────────────────────────────────────────

export interface DayConfig {
  minutes: number         // 0 = rest day
  has_secondary: boolean  // true = add a short mobility/skill session after the primary
}

export interface AthleteConstraints {
  kettlebell_weights_kg?: number[]
  mastered_exercises?: string[]
  kettlebell_count?: number
  /** A training contract's lift → the weight last made on it (Starting Strength). */
  starting_loads_kg?: Record<string, number>
  module_progression_state?: Record<string, { completed?: number; weight_kg?: number }>
  equipment: EquipmentId[]
  equipment_profile?: EquipmentProfileId | 'custom'
  days_per_week: number
  session_time_minutes: number
  weekday_session_minutes?: number
  weekend_session_minutes?: number
  allow_split_sessions?: boolean
  secondary_days?: number[]           // specific days (1-7) with secondary sessions enabled
  day_configs?: Record<number, DayConfig>  // per-day availability; drives derived fields
  training_level: TrainingLevel
  injury_flags: InjuryFlagId[]
  avoid_movements: string[]
  /** Legacy start: a phase kind, mapped to the first phase of that kind. */
  training_phase?: PhaseKind
  /** Start phase id from the chosen track. */
  start_phase?: string
  track_id?: string
  periodization_week: number
  fatigue_state: FatigueState
  event_date?: string
  preferred_days?: number[]
  forced_rest_days?: number[]
  notes?: string
}

export interface Equipment {
  id: EquipmentId
}

export interface EquipmentProfile {
  id: EquipmentProfileId
  name: string
  description: string
  equipment: EquipmentId[]
}

export interface InjuryFlag {
  id: InjuryFlagId
  name: string
  description: string
  excluded_movement_patterns: string[]
  excluded_exercises: string[]
  modified_exercises?: Array<{ instead_of: string; use: string }>
  training_phase_forced?: TrainingPhase
  notes?: string
}

// ─── Exercise ─────────────────────────────────────────────────────────────────

export interface ExerciseProgressions {
  load?: string
  volume?: string
  complexity?: string
}

export type AnimationType = 'gif' | 'lottie' | 'svg_css' | 'none'
export type AnimationSource = 'free_exercise_db' | 'exercisedb_api' | 'custom'

export interface ExerciseAnimation {
  type: AnimationType
  gif_url?: string
  gif_alt?: string
  gif_source?: AnimationSource
  external_id?: string
  lottie_path?: string
  lottie_source?: string
  svg_path?: string
}

export interface MuscleDiagram {
  highlight_primary: string[]
  highlight_secondary: string[]
}

export interface ExerciseMedia {
  description?: string
  cue_points?: string[]
  muscles_primary?: string[]
  muscles_secondary?: string[]
  common_errors?: string[]
  coaching_focus?: string
  animation?: ExerciseAnimation
  muscle_diagram?: MuscleDiagram
}

export interface Exercise extends ExerciseMedia {
  id: string
  name: string
  category: string
  modality: ModalityId[]
  equipment: EquipmentId[]
  effort: EffortLevel
  bilateral: boolean
  movement_patterns: string[]
  requires: string[]
  unlocks: string[]
  contraindicated_with: InjuryFlagId[]
  progressions: ExerciseProgressions
  scaling_down?: string[]
  typical_volume?: { sets?: number; reps?: number; duration_sec?: number; distance_m?: number }
  starting_load_kg?: Record<string, number>
  weekly_increment_kg?: number
  sources: string[]
  notes?: string
  /** First package to declare this id. Display only — use _packages for provenance. */
  _package?: string
  /** Every package that declares this exercise id. */
  _packages?: string[]
}

// ─── Archetypes ───────────────────────────────────────────────────────────────

export interface ArchetypeSlot {
  role: string
  slot_type: string
  sets?: number
  reps?: number | string
  duration_sec?: number
  distance_m?: number
  intensity?: string
  intensity_pct_1rm?: number
  rest_sec?: number
  notes?: string
  skip_exercise?: boolean
  exercise_filter?: {
    movement_pattern?: string
    category?: string
    /** The exercises the slot may take — how 1,748 of 1,762 slots pick. */
    exercise_ids?: string[]
    /** Take them in the written order, the first that fits. */
    ordered?: boolean
  }
}

/** A movement pattern exercises declare (`movement_patterns`): Explore's level
 *  below Exercise. GET /api/explore/links. */
export interface Movement {
  id: string
  name: string
  exerciseCount: number
  /** The slot-filter aliases that include it (movement_patterns.yaml: press, hinge…). */
  filterGroups: string[]
  /** The analytics group it counts toward (push, pull, hinge…), if any. */
  rollup: string | null
}

/** How Explore's levels connect, computed with the selector's own slot rule
 *  (src/explore_links.py). */
export interface ExploreLinks {
  movements: Movement[]
  /** What each exercise and archetype needs, as the generator reads it: a set
   *  of equipment enables one when it covers the list (open space is free). */
  equipment: {
    vocabulary: string[]
    exercises: Record<string, string[]>
    archetypes: Record<string, string[]>
  }
  links: {
    philosophyFramework: {
      philosophy: string
      framework: string
      owner: boolean
      phases: { trackId: string; trackName: string; trackIndex: number; phaseId: string; phaseName: string; order: number }[]
    }[]
    frameworkModality: { framework: string; modality: string; sessionsPerWeek: number | null; tier: 'committed' | 'core' | 'supplementary' | null }[]
    modalityArchetype: { modality: string; archetype: string; package: string | null }[]
    archetypeExercise: { archetype: string; exercise: string; slots: string[]; via: 'listed' | 'filter' }[]
    exerciseMovement: { exercise: string; movement: string }[]
    /** `requires` and `unlocks` folded together: `from` comes before `to`. */
    exerciseProgression: { from: string; to: string; declaredBy: ('requires' | 'unlocks')[] }[]
    /** `requires` entries that are no exercise — what the athlete brings. */
    exerciseConcepts: { exercise: string; concept: string }[]
  }
}

export interface Archetype {
  id: string
  name: string
  _package?: string
  modality: ModalityId
  category: string
  duration_estimate_minutes: number
  required_equipment: EquipmentId[]
  applicable_phases: TrainingPhase[]
  training_levels: TrainingLevel[]
  slots: ArchetypeSlot[]
  sources: string[]
  notes?: string
  scaling?: {
    deload?: string
    time_limited?: string
    equipment_limited?: string
  }
}

// ─── Exercise Load (per session assignment) ───────────────────────────────────

export interface ExerciseLoad {
  prescription_version?: number
  progression_model?: string
  module_id?: string
  forecast_step?: number
  conditional?: boolean
  advances_module?: boolean
  elapsed_sec?: number
  sets?: number
  reps?: number | string
  weight_kg?: number
  target_rpe?: number
  rir?: number          // reps in reserve
  suggested_weight_kg?: number
  duration_minutes?: number
  zone_target?: string
  distance_km?: number
  distance_m?: number
  reps_per_round?: number
  /** Reps round by round where they change (Fran's [21, 15, 9]), in place of reps_per_round. */
  rep_scheme?: number[]
  target_rounds?: number
  time_minutes?: number
  format?: string
  hold_seconds?: number
  focus?: string
  intensity?: string
  /** Structured interval timing — e.g. Tabata's 20s work / 10s rest. */
  work_sec?: number
  rest_sec?: number
  /** Resolved HR zone bounds (1–5) for the slot's intensity token. */
  zone_lower?: number
  zone_upper?: number
  /** Pack weight for rucks and loaded carries. */
  pack_load_kg?: number
  /** A training contract's lift (`load_per_exposure`): the lift it moves on,
   *  the kg it adds when made, and a first session that works up to a weight. */
  lift?: string
  increment_kg?: number
  work_up?: boolean
  stalled?: boolean
  load_note?: string
}

// ─── Session ──────────────────────────────────────────────────────────────────

export interface ExerciseAssignment {
  exercise: Exercise
  load: ExerciseLoad
  meta?: boolean
  slot_role?: string
  slot_type?: string
  rest_sec?: number
  load_note?: string
  notes?: string
  /** Set when an injury flag blocked every candidate for this slot.
   *  Previously read via an inline cast in ExerciseRow.tsx. */
  injury_skip?: boolean
  /** Unfilled because the philosophy's packages own nothing for this slot. */
  coverage_gap?: boolean
  /** Unfilled because no exercise fits the athlete's equipment. */
  equipment_gap?: boolean
  /** NO_EXERCISE_IN_ALLOWED_PACKAGES | EQUIPMENT_UNAVAILABLE | LEVEL_LOCKED */
  gap_reason?: string | null
  /** The exercise an injury flag's `modified_exercises` replaced with this one. */
  substituted_for?: string
  /** The injury flag whose substitute this is. */
  substituted_by_flag?: string
  /** What emptied the slot, named (selector._explain_unfilled); absent on a filled slot. */
  blocked_by?: SlotBlocker
  /** Links an `amrap_movement` component to the `amrap` slot it belongs to. */
  parent_slot_role?: string
  /** Structural slot with no exercise (BJJ rounds, circuit round wrappers). */
  skip_exercise?: boolean
  /** The standard this slot measures, when it is a test's scored slot. */
  standard?: { id: string; result: string | null }
}

export interface ComplementaryExercise {
  exercise: Exercise
  prescription: {
    sets: number
    duration_sec: number
    note: string
  }
}

/** Which philosophy package a session's archetype actually came from. */
export interface SessionProvenance {
  package: string
  /** True when the package is one the philosophy declares in borrows_from. */
  borrowed: boolean
  label?: string
  reason?: string
}

export interface Session {
  modality: ModalityId
  /** null when the philosophy package could not fill this slot (a documented
   *  coverage gap) or an injury excluded every candidate. The type used to
   *  claim this was always present, which hid four unguarded dereferences that
   *  crashed the program view for anyone whose program had such a slot. */
  archetype: Archetype | null
  /** Its workout icon, for its main exercise (src/session_icon.py; derived on
   *  every read, never stored). Absent when none applies. */
  icon?: string
  exercises: ExerciseAssignment[]
  complementary_work?: ComplementaryExercise[]
  duration_min?: number
  provenance?: SessionProvenance | null
  /** A test of the phase's standards, put in place of a session (src/generator._plan_week_tests). */
  test?: SessionTest
  /** Added by the athlete on the fly (POST /sessions/generate `add`): an extra that
   *  counts only once done, and the only kind of session that can be removed. */
  added?: boolean
  /** The modality this session was scheduled in place of (no archetype for it). */
  substituted_for?: string
  /** Why: no archetype of that modality for the athlete's level, or for this phase. */
  substitution_cause?: 'level' | 'phase'
  /** The equipment its archetype asks for that the athlete lacks; it runs scaled. */
  equipment_scaled?: string[]
  /** A composed program's track for this session (`<philosophy>/<track>`), and the
   *  phase, framework and phase week it runs in — its own, not the week's. */
  lane_key?: string
  track_id?: string
  phase?: PhaseKind
  phase_id?: string
  framework?: string
  week_in_phase?: number
  /** Whether this session deloads (its own track's cadence in a composed program). */
  is_deload?: boolean
  /** A session no archetype could fill says why. */
  error?: string
}

/** Why a slot is empty, read from the exercise the lifted constraint would give. */
export interface SlotBlocker {
  cause: 'equipment' | 'injury' | 'level' | 'phase' | 'coverage'
  /** The exercise that would be there. */
  exercise?: string
  /** equipment: the items it needs that the athlete lacks. */
  needs?: string[]
  /** injury: the flags that rule it out. */
  flags?: string[]
  /** level: what it requires that the athlete's level has not reached. */
  requires?: string[]
  level?: string
  /** An injury substitute: the flag it came via. */
  via?: string
}

/** One session a constraint change moves (constraint_impact.diff_programs). */
export interface ConstraintChangeEntry {
  week_index: number
  week_number: number
  day: string
  session_index: number
  change: 'added' | 'removed' | 'modality' | 'archetype' | 'slots'
  before: ImpactSessionView | null
  after: ImpactSessionView | null
  slots?: {
    index: number
    role?: string
    before: { id: string; name: string } | null
    after: { id: string; name: string } | null
    gap_before?: string | null
    gap_after?: string | null
  }[]
}

export interface ImpactSessionView {
  modality: string
  archetype: { id: string; name: string } | null
  test: boolean
  substituted_for?: string | null
}

/** POST /programs/constraint-change */
export interface ConstraintChangeResult {
  affected: boolean
  comparable: boolean
  sessions: { total: number; changed: number }
  first_week_number?: number | null
  changes: ConstraintChangeEntry[]
  validation?: ValidationResult
  /** The tail with the new constraints, when affected. */
  program?: GeneratedProgram
}

export interface ImpactWhy {
  /** equipment | injury | level | proficiency | combined | knock_on */
  cause: string
  text: string
}

/** One change in the Held back comparison (constraint_impact.analyse). */
export interface ImpactChange {
  week_index: number
  week_number: number
  day: string
  session_index: number
  change: 'added' | 'removed' | 'modality' | 'archetype' | 'slots'
  reference: ImpactSessionView | null
  actual: ImpactSessionView | null
  /** A whole-session change: the constraints that, lifted alone, restore it. */
  causes?: string[]
  why?: ImpactWhy[]
  knock_on?: boolean
  slots?: {
    index: number
    role?: string
    kind: 'emptied' | 'filled' | 'swapped'
    from: { id: string; name: string } | null
    to: { id: string; name: string } | null
    gap_reason?: string | null
    causes: string[]
    why: ImpactWhy[]
    knock_on: boolean
  }[]
}

/** POST /programs/impact */
export interface ConstraintImpact {
  feasible: boolean
  reference_generates?: boolean
  detail?: string
  lifts?: Record<string, string>
  lifted?: string[]
  reference?: { equipment?: string[]; training_level?: string; mastered_exercises?: string[]; kettlebell_count?: number }
  /** `total`: every position either program has a session at, so `changed` ≤ `total`. */
  sessions?: { total: number; actual?: number; reference?: number; changed: number; direct?: number }
  totals?: Record<string, { sessions?: number; slots?: number; knock_on?: number }>
  restore?: { equipment?: { id: string; changes: number }[] }
  changes?: ImpactChange[]
  /** A refused request: the one constraint that alone lets it generate. */
  unblocked_by?: { cause: string; text: string }[]
  refused?: { detail?: string; validation?: ValidationResult }
}

export interface SessionTest {
  archetype: string
  standards: string[]
  phase_id?: string
  week_in_phase?: number
  /** The modality of the session it stands in for. */
  in_place_of?: string
  /** That session: its archetype and planned minutes. */
  instead_of?: { archetype?: string; name?: string; modality?: string; minutes?: number }
}

/** What the philosophy could not cover on its own, and what it borrowed. */
export interface CoverageReport {
  philosophy: string | null
  strict: boolean
  unfilled_sessions: { week: number; day: string; modality: string; reason: string }[]
  unfilled_slots: { archetype: string; slot_role: string; reason: string }[]
  borrowed_sessions: {
    week: number
    day: string
    archetype: string
    from_package: string
    label?: string
    reason?: string
  }[]
  /** Sessions scheduled as another modality (NO_ARCHETYPE_FOR_LEVEL | _PHASE). */
  substituted_sessions?: {
    week: number
    day: string
    modality: string
    substituted_for: string
    archetype?: string | null
    reason: string
  }[]
}

// ─── Generated Program ────────────────────────────────────────────────────────

export interface WeekVolumeSummary {
  week_number: number
  strength_sets: number
  /** Time-domain strength (a KB pentathlon set), when a session has no sets. */
  strength_minutes?: number
  cond_minutes: number
  dur_minutes: number
  mob_minutes: number
  total_minutes: number
  elevation_gain_m?: number
  elevation_loss_m?: number
}

export interface WeekData {
  week_number: number
  week_in_phase: number
  /** The phase kind. */
  phase: PhaseKind
  /** The philosophy's own phase id and name (absent on programs stored before tracks). */
  phase_id?: string
  phase_name?: string
  track_id?: string
  is_deload: boolean
  schedule: Record<string, Session[]>
  framework?: string
  /** A test the phase called for that the week could not run, and why (generator._plan_week_tests). */
  tests_skipped?: { archetypes?: string[]; phase_id?: string; week_in_phase?: number; reason: string }[]
  /** A composed program's tracks this week: each one's own phase (the week's
   *  `phase` fields are the lead track's), deload, and session count. */
  lanes?: WeekLane[]
}

export interface WeekLane {
  lane_key: string
  track_id: string
  phase: PhaseKind
  phase_id?: string
  phase_name?: string
  week_in_phase: number
  framework?: string
  is_deload: boolean
  sessions: number
}

/** How a composed program shared the athlete's week between its tracks. */
export interface ProgramComposition {
  days: number[]
  lanes: {
    key: string
    kind: 'contract' | 'template'
    philosophy_id: string
    track_id: string
    name: string
    weight: number
    /** Its share of the athlete's training days, and the days it keeps for itself. */
    days: number
    reserved_days: number[]
    cuts: { optional: boolean; volume: number; exposures: Record<string, number> }
    training_contract?: { id: string; version: number; status: string }
    module_state?: Record<string, { completed: number; weight_kg?: number }>
  }[]
}

export interface ValidationMessage {
  code: string
  message: string
  suggested_fix?: string
}

export interface ValidationResult {
  feasible: boolean
  errors: ValidationMessage[]
  warnings: ValidationMessage[]
  info: ValidationMessage[]
}

/** One archetype or exercise in a phase, against the phase before it. */
export interface PhaseSummaryItem {
  id: string
  name: string
  modality: string
  /** Appearances in the phase (deload weeks included). */
  sessions: number
  /** Appearances per working week (deloads left out, like sessions_per_week).
   *  Absent from servers before it was added. */
  per_week?: number
  /** null in the first phase. */
  status: 'new' | 'continued' | null
}

export interface PhaseSummaryLift {
  id: string
  name: string
  first_kg: number
  last_kg: number
}

/** How a phase's sessions and exercises differ from the phase before it.
 *  Computed by the server on every read (src/phase_summary.py), never stored. */
export interface PhaseSummary {
  phase_id: string
  name: string
  kind: PhaseKind
  framework_id?: string
  week_start: number
  week_end: number
  weeks: number
  deload_weeks: number
  /** Sessions per modality, averaged over the phase's working weeks. */
  sessions_per_week: Record<string, number>
  minutes_per_week: { first: number; last: number; mean: number }
  /** Shares of planned minutes: zone1_2, zone3, zone4_5, max_effort. */
  intensity: Record<string, number>
  archetypes: PhaseSummaryItem[]
  exercises: PhaseSummaryItem[]
  lifts: PhaseSummaryLift[]
  /** The phase's tests of its standards, run or skipped (with why). */
  tests?: Array<{
    week_number: number
    week_in_phase?: number
    day?: string | null
    status: 'planned' | 'skipped'
    reason?: string
    archetype: { id: string | null; name: string | null }
    standards?: Array<{ id: string; name: string }>
    in_place_of?: string | null
  }>
  dropped: {
    archetypes: Omit<PhaseSummaryItem, 'sessions' | 'status'>[]
    exercises: Omit<PhaseSummaryItem, 'sessions' | 'status'>[]
  }
  /** Plain lines naming what differs from the previous phase. */
  changes: string[]
}

export interface GeneratedProgram {
  training_contract?: { id: string; version: number; status: string; forecast?: string }
  module_state?: Record<string, { completed: number; weight_kg?: number }>
  goal: GoalProfile
  constraints: AthleteConstraints
  validation: ValidationResult
  weeks: WeekData[]
  volume_summary?: WeekVolumeSummary[]
  phase_summary?: PhaseSummary[]
  /** A composed program's phase summary per track (two tracks may share a phase id). */
  lane_phase_summary?: { lane_key: string; phases: PhaseSummary[] }[]
  composition?: ProgramComposition
  program_start_date?: string
  compromises?: string[]
  coverage_report?: CoverageReport | null
  /** What the constraints held back (src/blockers.held_back); derived, never stored. */
  held_back?: { slots: number; sessions: number }
}

// ─── Generation Trace ─────────────────────────────────────────────────────────

export interface CandidateScore {
  id: string
  name: string
  score: number
  breakdown: Record<string, number>
  /** An archetype's heavily loaded body regions (src/recovery_regions.py). */
  heavy_regions?: string[]
  package?: string  // First declaring package (display only)
  packages?: string[]  // Every philosophy package declaring this exercise id
}

export interface ArchetypeTrace {
  selected_id: string | null
  filter_counts: Record<string, number>
  candidates: CandidateScore[]
  /** A placed archetype (a test, a week template's day): why, e.g. its category. */
  selection_reason?: string
}

export interface SlotTrace {
  slot_index: number
  slot_role: string
  slot_type: string
  meta: boolean
  movement_pattern: string | null
  selected_id: string | null
  injury_blocked: boolean
  filter_counts: Record<string, number>
  candidates: CandidateScore[]
  /** The contract module that placed the slot. */
  module_id?: string | null
}

export interface ProgressionEntry {
  exercise_id: string
  exercise_name: string
  slot_role: string
  slot_type: string
  model: string
  week: number
  phase: string
  level: string
  is_deload: boolean
  output: Record<string, number | string>
}

export interface SessionTrace {
  modality: string
  /** The contract modules the session carries. */
  modules?: string[]
  archetype: ArchetypeTrace
  slots: SlotTrace[]
  progression: ProgressionEntry[]
}

/**
 * How the scheduler chose the week's framework (src/scheduler.select_framework).
 * Inside a track the week's phase names its framework and decides
 * (`selection_reason: 'phase_framework_override'`); that path records only the
 * pick, so the goal's default, its alternatives and the days check are absent.
 * Every week of every program takes it since tracks landed (2026-10-13).
 */
export interface FrameworkSelectionTrace {
  selected_id: string
  selection_reason: string
  phase_framework_id?: string | null
  forced_override?: string | null
  default_id?: string
  alternatives_checked?: Array<{ framework_id: string; condition: string; matched: boolean }>
  days_constraint?: { athlete_days: number; framework_min: number; framework_max: number; days_fallback: string | null }
}

/**
 * A training contract (src/training_contract.py) places fixed modules: its
 * week has `contract` and no allocation or day assignment, and its framework
 * selection reads `training_contract`. A week the source writes day by day
 * (src/week_template.py) carries its `week_template` instead, likewise with
 * no allocation.
 */
export interface SchedulerTrace {
  framework_selection: FrameworkSelectionTrace
  contract?: string
  week_template?: unknown[]
  allocation?: {
    phase_priorities: Record<string, number>
    raw: Record<string, number>
    final: Record<string, number>
  }
  day_assignment?: {
    modality_order: string[]
    day_pool: number[]
    assignments: Record<string, string[]>
  }
  is_deload: boolean
  deload_freq_weeks?: number
}

export interface WeekTrace {
  week_number: number
  week_in_phase: number
  phase: string
  is_deload: boolean
  scheduler: SchedulerTrace
  sessions: Record<string, SessionTrace[]>
}

export interface GenerationTrace {
  weeks: WeekTrace[]
  primary_sources?: string[]  // Philosophy package IDs (e.g. ['starting_strength'])
  philosophy_mode?: 'synthetic_goal' | 'explicit_goal' | 'training_contract'
}

export interface TracedProgram extends GeneratedProgram {
  generation_trace?: GenerationTrace
}

// ─── Standards ────────────────────────────────────────────────────────────────
// "Standard" everywhere a person reads it; the type, route and key names keep
// "benchmark" because they are stored and on the wire (src/analytics/benchmarks_data.py).

export type BenchmarkLevel = 'entry' | 'intermediate' | 'advanced' | 'elite'

/** Drives which standards' tables the athlete is scored against. */
export type Sex = 'male' | 'female'

export interface BenchmarkStandard {
  id: string
  name: string
  /** data/benchmarks/categories.yaml's ids, or one a package adds (its standards.yaml). */
  category: string
  /** The group's name and place, the same on every screen and both clients. */
  categoryName?: string
  categoryOrder?: number
  /** The modality it measures — its ladder is drawn in that colour. */
  domain?: string
  unit: string
  standards: Record<BenchmarkLevel, number>
  /** The thresholds as printed ("4:30", "1.5×BW"). */
  standardsText?: Record<BenchmarkLevel, string>
  /** What a result field reads: "m:ss", "seconds", "×BW", "reps"… */
  inputHint?: string
  lower_is_better?: boolean
  metricType?: string
  notes?: string
  testProtocol?: string
  /** A run standard: the distance an imported run's fastest window reads as. */
  bestEffort?: { km: number; label: string }
  description?: string
}

/** One value placed on a standard's ladder, by the server (src/standards.py). */
export interface StandardPoint {
  value: number
  valueText: string
  date: string | null
  /** null = below entry. */
  level: BenchmarkLevel | null
  levelIndex: number
  next: BenchmarkLevel | null
  nextText: string | null
  gap: number | null
  gapText: string | null
}

/** Who logged a result: typed in, from a session, a watch, an imported workout. */
export type StandardSource = 'manual' | 'session' | 'garmin' | 'apple_watch' | 'workout'

/** One result, as the server places it (src/standards.py). */
export interface StandardEntry {
  id: number | null
  value: number
  valueText: string
  /** The athlete's day it counts for. */
  date: string
  level: BenchmarkLevel | null
  levelIndex: number
  source: StandardSource
  note: string | null
  /** "140 kg × 2 at 82 kg · est." for a ×BW result logged as a load. */
  inputText: string | null
  sessionUid: string | null
  workoutId: string | null
  /** The program block in force that day (or the test session's). */
  block: { id: number; name: string } | null
}

export interface StandardResult {
  current: StandardPoint
  best: StandardPoint
  count: number
  entries: StandardEntry[]
}

export interface StandardBlock { id: number; name: string; from: string; to: string | null }

/** GET /api/standards/results */
export interface StandardResults {
  sex: Sex
  standards: Record<string, StandardResult>
  /** The program timeline, oldest first, for shading a history chart. */
  blocks?: StandardBlock[]
  bodyweight: { value: number; valueText: string; date: string | null; entries?: StandardEntry[] } | null
  /** The current program's own standards (declared or tested), for Profile's "This program". */
  programStandards?: Array<{ id: string; why: string[] }>
}

/** What a result is sent as: typed text ("4:58"), or for a ×BW standard the load lifted. */
export interface StandardResultInput {
  text?: string
  kg?: number
  reps?: number
  /** The athlete's day (YYYY-MM-DD); today when absent. */
  loggedOn?: string
  note?: string
}

/**
 * A result a logged session suggests — a test slot's outcome, or a single on a
 * lift a ×BW standard is read from — waiting for the athlete
 * (`GET /api/standards/suggestions`, src/standard_results.py). Not a result
 * until confirmed; every word is the server's.
 */
export interface StandardSuggestion {
  id: number
  benchmarkId: string
  name: string
  /** The name without its parenthesis: "1-Mile Run". */
  shortName?: string
  domain: string | null
  value: number
  valueText: string
  level: BenchmarkLevel | null
  levelIndex: number
  next: BenchmarkLevel | null
  nextText: string | null
  /** "20 + 7" for a partial round, the load for a single. */
  inputText: string | null
  /** The result it would follow. */
  current: StandardPoint | null
  bestText: string | null
  isBest: boolean
  /** A re-logged value reopened a saved suggestion: the result saving it corrects. */
  replacesText?: string | null
  origin: 'test_slot' | 'derived_single' | 'best_effort'
  status: 'pending' | 'confirmed' | 'dismissed'
  source: string
  loggedOn: string | null
  sessionUid: string | null
  sessionKey: string | null
  sessionName: string | null
  exerciseId: string | null
  resultId: number | null
}

/** What a session-log save says about the standards it bears on. */
export interface SessionLogStandards {
  pending: StandardSuggestion[]
  confirmed: StandardSuggestion[]
  skipped: Array<{ benchmarkId: string; reason: string }>
  problems: string[]
  error: string | null
}

// ─── Modality ─────────────────────────────────────────────────────────────────

export interface Modality {
  id: ModalityId
  name: string
  description: string
  recovery_cost: 'low' | 'medium' | 'high'
  recovery_hours_min: number
  session_position: string
  compatible_in_session_with: ModalityId[]
  incompatible_in_session_with: ModalityId[]
  min_weekly_minutes: number
  max_weekly_minutes: number
  progression_model: string
  typical_session_minutes?: { min: number; max: number }
  intensity_zones?: Array<{ label: string; description?: string; hr_pct_range?: [number, number] }>
  sources?: string[]
  notes?: string
}

// ─── Philosophy ───────────────────────────────────────────────────────────────

export interface PhilosophyConnections {
  frameworks: string[]
  goals: string[]
}

/** A philosophy's own phase (philosophy.yaml → tracks → phases). */
export interface Phase {
  id: string
  name: string
  kind: PhaseKind
  weeks: number
  framework_id: string
  focus?: string
  description?: string
  adaptations?: string[]
  intensity?: string
  repeatable?: boolean
}

/** One way to follow a philosophy: an ordered list of its own phases. */
export interface Track {
  id: string
  name: string
  description?: string
  phases: Phase[]
  entry_requirements?: {
    training_levels: string[]
    mastered_exercises: string[]
    mastered_exercises_by_level?: Record<string, string[]>
    /** Each required movement's name, by exercise id. */
    exercise_names?: Record<string, string>
    kettlebell_count: number
    /** Lifts that may start from the weight last made (optional; else a work-up). */
    starting_loads?: { id: string; name: string }[]
  }
}

export interface Philosophy {
  id: string
  name: string
  core_principles: string[]
  scope: string[]
  bias: string[]
  avoid_with: string[]
  required_equipment: string[]
  intensity_model: string
  progression_philosophy: string
  sources: string[]
  notes: string
  system_connections: PhilosophyConnections
  primary_track_id?: string
  /** The track a request that names none gets at each level. */
  track_for_level?: Record<string, string>
  tracks: Track[]
  expectations?: GoalExpectations  // Full program expectations (for phased programs)
}

// ─── Framework ────────────────────────────────────────────────────────────────

export interface FrameworkApplicableWhen {
  training_level?: TrainingLevel[]
  days_per_week_min?: number
  days_per_week_max?: number
  goal_priority_min?: Partial<Record<ModalityId, number>>
}

export interface Framework {
  id: string
  name: string
  source_philosophy?: string
  goals_served?: ModalityId[]
  sessions_per_week?: Partial<Record<ModalityId, number>>
  intensity_distribution?: Record<string, number>
  progression_model?: string
  applicable_when?: FrameworkApplicableWhen
  /** Frameworks that interfere with this one. Authored per framework in
   *  data/packages/<id>/frameworks/*.yaml. */
  incompatible_with?: Array<{
    framework_id: string
    reason?: string
    interference_level?: string
    mitigation?: string
  }>
  deload_protocol?: { frequency_weeks: number; volume_reduction_pct: number; intensity_change: string }
  /** Authored in every framework yaml; the analytics scorecard tiers by it. */
  modality_priority?: { committed?: ModalityId[]; core?: ModalityId[]; supplementary?: ModalityId[] }
  cadence_options?: Record<string, number[][]>
  sources?: string[]
  notes?: string
  expectations?: GoalExpectations
}

// ─── Custom Injury ────────────────────────────────────────────────────────────

export interface CustomInjuryFlag {
  id: string
  name: string
  body_part: string
  excluded_movement_patterns: string[]
  excluded_exercises: string[]
}

// ─── Exercise Filters (client-side) ───────────────────────────────────────────

export interface ExerciseFilters {
  search?: string
  modality?: ModalityId[]
  category?: string
  effort?: EffortLevel[]
  equipment?: EquipmentId[]
}

// ─── Ontology (heatmap visualization) ─────────────────────────────────────────

export interface OntologyData {
  philosophies: Philosophy[]
  frameworks: Framework[]
  modalities: Modality[]
  archetypes: Archetype[]
  exercises: Exercise[]
}

// ─── Bio / Performance Data ────────────────────────────────────────────────────

// 'garmin' is written by the Connect IQ watch app and by the Garmin Connect
// webhook; 'watch' by the Apple Watch relay. Both were already reaching the
// database before they were listed here.
export type ImportSource =
  | 'apple_health' | 'strava' | 'manual' | 'apple_watch_live' | 'fit_file'
  | 'garmin' | 'watch'
export type RPE = 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10
export type FatigueRating = 1 | 2 | 3 | 4 | 5
export type MatchConfidence = 'auto' | 'manual' | 'rejected'

export interface HRSample {
  timestamp: string // ISO
  bpm: number
}

export interface GPSPoint {
  lat: number
  lng: number
  altitude?: number | null
  timestamp: string // ISO
  bpm?: number | null
  speed?: number | null // m/s — present in FIT files and Apple Watch live workouts
}

export interface HRZoneDistribution {
  z1: number // % of time
  z2: number
  z3: number
  z4: number
  z5: number
  method: 'samples' | 'summary_estimate'
}

export interface HRConfig {
  maxHROverride?: number | null     // user-measured max HR; null/undefined = use 220-age
  zoneBoundaries?: number[] | null  // 4 upper-boundary fractions [0.60, 0.70, 0.80, 0.90]; null = Friel defaults
}

/** Auto-import settings, stored server-side next to hrConfig so the Garmin
 *  webhook worker can read them — a toggle the browser kept to itself would do
 *  nothing about activities Garmin is already pushing. */
export interface IntegrationSettings {
  /** Master switch over every source. */
  autoImport: boolean
  sources: Record<string, { enabled: boolean }>
}

/** A workout the server matched too weakly to confirm on its own. */
/**
 * A weak match the server could not confirm on its own, written by the
 * automatic import paths (Garmin webhook, iOS Apple Health relay). Shown as a
 * pending match for the athlete to confirm or dismiss; deciding the workout
 * either way (POST /health/matches) deletes the suggestion server-side.
 */
export interface MatchSuggestion {
  importedWorkoutId: string
  sessionKey: string
  /** Durable id of the planned session when the server could resolve one. */
  sessionUid?: string | null
  score: number
  createdAt: string
}

export interface GarminStatus {
  connected: boolean
  /** False when the server has no Garmin credentials — the feature is inert. */
  configured: boolean
  garminUserId?: string | null
  athleteName?: string | null
  connected_at?: string | null
  last_sync_at?: string | null
  last_webhook_at?: string | null
}

export interface ImportedWorkout {
  id: string
  source: ImportSource
  date: string // YYYY-MM-DD
  startTime: string // ISO
  endTime: string // ISO
  durationMinutes: number
  activityType: string // raw source label
  inferredModalityId?: ModalityId
  heartRate: { avg?: number; max?: number; min?: number; samples?: HRSample[] }
  calories?: number
  distance?: { value: number; unit: 'km' | 'm' }
  gpsTrack?: GPSPoint[] | null
  elevation?: { gain: number; loss: number } | null
  rawData: Record<string, unknown>
  /** Present on `GET /health/workouts/<id>` only: the server's analysis. */
  analysis?: WorkoutAnalysis
}

/**
 * One workout analysed on the server (src/analytics/workout_analysis.py) —
 * the numbers both clients show on a workout instead of computing their own.
 */
export interface WorkoutAnalysis {
  version: number
  maxHr: number
  maxHrSource: 'override' | 'age' | 'default'
  zoneBoundaries: number[]
  zoneBoundariesSource: 'custom' | 'shared'
  /** Null when the workout has no heart rate at all. */
  zones: { method: 'samples' | 'summary_estimate'; pct: number[]; minutes: number[] } | null
  trimp: number | null
  trainingEffect: string | null
  recoveryHours: number | null
  decoupling: { pct: number; label: 'efficient' | 'moderate' | 'high' } | null
  bestEfforts: { label: string; km: number; seconds: number; secPerKm: number }[]
  /** What the matched session planned (src/analytics/hr_plan.py); null when
   *  the workout is linked to no session. */
  planned?: WorkoutPlanned | null
}

/** What a session's programming makes of one recording (src/analytics/hr_plan.py):
 *  heart rate counts only where an exercise prescribes zones. */
export interface WorkoutPlanned {
  /** Something in it prescribes zones. */
  track: boolean
  /** What counts: the whole recording, only the zoned exercises, or nothing. */
  mode: 'whole' | 'exercises' | 'none'
  /** What decided: the archetype's `heart_rate`, its slots, or its modality. */
  source: 'declared' | 'slots' | 'modality'
  /** How it was counted: whole, by the watch's exercise times, not timed
   *  (a mixed session without them), no heart rate recorded, or not at all. */
  timing: 'whole' | 'timeline' | 'untimed' | 'unrecorded' | 'none'
  /** Z1–Z5: the planned minutes of the exercises that count. */
  plannedMinutes: number[]
  /** Z1–Z5: the recorded minutes that count. */
  zoneMinutes: number[]
  countedMinutes: number
  /** The slots that prescribe load or effort instead ("main: heavy"). */
  notZoned: string[]
  slots: WorkoutPlannedSlot[]
  sessionUid?: string
  sessionName: string | null
  modality: string | null
}

/** One slot of the session: what it prescribes and, where the watch timed
 *  its exercises, what it recorded. */
export interface WorkoutPlannedSlot {
  role: string
  intensity: string | null
  zones: number[]
  prescribes: 'zones' | 'load'
  exercises: string[]
  plannedMinutes: number
  /** Z1–Z5 inside the watch's times for its exercises; null when untimed. */
  recordedMinutes: number[] | null
  counted: boolean
}

export interface SetPerformance {
  setIndex: number
  repsActual?: number
  weightKg?: number
  rpe?: RPE
  completed: boolean
  durationSeconds?: number
  startOffset?: number  // seconds from session start when this set began
  endOffset?: number    // seconds from session start when this set was logged
}

export interface ExercisePerformance {
  weightKg?: number
  sets: SetPerformance[]
  rpe?: RPE
  notes?: string
  /** A skill practised clean — every rep owned. Movements earned counts these
   *  where the package asks (`require_clean`). */
  clean?: boolean
  /**
   * Outcomes for slots that are not sets × reps — what the OutcomeLogger
   * writes and what src/progression_tracker.py and the analytics engine
   * read. Until the logger existed nothing ever wrote these.
   */
  rounds?: number
  durationSec?: number
  distanceKm?: number
  /** A loaded lift of a training contract (Starting Strength): made or
   *  missed at `weightKg` — what moves its weight on or repeats it. */
  made?: boolean
}

export interface ExerciseTimelineEntry {
  exerciseId: string
  startOffset: number   // seconds from session start
  endOffset: number
  avgHRDuring?: number  // mean bpm during this exercise window
}

export interface SessionPerformanceLog {
  sessionKey: string
  importedWorkoutId?: string
  exercises: Record<string, ExercisePerformance>
  notes: string
  fatigueRating?: FatigueRating
  completedAt: string
  source?: string
  avgHR?: number
  peakHR?: number
  exerciseTimeline?: ExerciseTimelineEntry[]
}

export interface DailyBioLog {
  date: string // YYYY-MM-DD
  restingHR?: number
  hrv?: number // RMSSD ms
  notes?: string
  // Sleep data (populated automatically via Apple Watch sync)
  sleepDurationMin?: number
  deepSleepMin?: number
  remSleepMin?: number
  lightSleepMin?: number
  awakeMins?: number
  sleepStart?: string  // ISO timestamp
  sleepEnd?: string    // ISO timestamp
  spo2Avg?: number     // %
  respiratoryRateAvg?: number // breaths/min
  source?: 'manual' | 'apple_watch'
}

export interface WorkoutMatch {
  importedWorkoutId: string
  /**
   * Program-relative: `"3-Monday-0"` names a different session in every plan the
   * athlete has ever had. Never use it alone to decide whether a match belongs
   * to the session on screen — see lib/sessionMatching.ts.
   */
  sessionKey: string
  /**
   * `"<programVersionId>:w<weekIndex>-<Day>-<index>"`. Names one session of one
   * archived program version, so a match survives a regenerate instead of
   * re-pointing at whatever now occupies that slot. Absent on matches stored
   * before program history existed, and on any the server could not resolve
   * without guessing.
   */
  sessionUid?: string | null
  matchConfidence: MatchConfidence
  matchedAt: string
  /**
   * The server's answer to "is this the active program's match", by dates as
   * well as uid (src/session_scope.py): false for another version's uid, and
   * for an unscoped match whose workout does not fall on the active program's
   * date for its key. Absent on a match made in this browser and not reloaded.
   */
  inCurrentProgram?: boolean
}

/** One activation of one program: what was in force, and when. */
export interface ProgramHistoryEntry {
  activationId: number
  versionId: string
  lineageId: string
  label: string
  goalName: string | null
  sourceGoalIds: string[]
  effectiveFrom: string
  effectiveTo: string | null
  isActive: boolean
  activatedAt: string
  source: string
  startDate: string | null
  weekCount: number
  sessionCount: number
  firstDate: string | null
  lastDate: string | null
  matchedCount: number
  loggedCount: number
}

/** A session as it was planned, flattened onto the calendar day it fell on. */
export interface PlannedSession {
  sessionUid: string
  programVersionId?: string
  date: string
  weekIndex: number
  weekNumber: number | null
  dayName: string
  sessionIndex: number
  sessionKey: string
  modality: ModalityId
  archetypeId: string | null
  archetypeName: string | null
  /** Its workout icon, from the archetype (src/session_icon.for_archetype). */
  icon?: string | null
  durationMinutes: number
  phase: string | null
  isDeload: boolean
  /** False for weeks a plan never got to run, because it was replaced first. */
  wasEffective?: boolean
  matchedWorkoutId?: string | null
  completedAt?: string | null
}

export interface ProgramHistoryDetail {
  versionId: string
  program: GeneratedProgram & Record<string, unknown>
  startDate: string
  weekCount: number
  firstSeenAt: string
  activations: ProgramHistoryEntry[]
  sessions: PlannedSession[]
}

export interface PendingMatch {
  importedWorkout: ImportedWorkout
  candidateSessionKeys: string[]
}

// ─── Session Insights ────────────────────────────────────────────────────────

export type InsightSeverity = 'positive' | 'neutral' | 'warning'

export interface InsightItem {
  key: string
  label: string
  detail: string
  severity: InsightSeverity
  metric?: { prescribed: string; actual: string; unit: string }
}

export interface SessionInsight {
  sessionKey: string
  complianceScore: number // 0-100
  status: 'green' | 'yellow' | 'red'
  insights: InsightItem[]
}

export interface WeekInsightSummary {
  weekNumber: number
  sessionsMatched: number
  sessionsTotal: number
  avgCompliance: number
  status: 'green' | 'yellow' | 'red'
  topFlags: InsightItem[]
}

export interface DevelopmentTrend {
  metric: string
  label: string
  dataPoints: { weekNumber: number; value: number }[]
  direction: 'improving' | 'stable' | 'declining'
  detail: string
}

// ── Progression review types ──────────────────────────────────────────────────

export type ProgressionStatus = 'ahead' | 'on_track' | 'behind' | 'stalled' | 'insufficient_data'
export type ProgressionMetricType = 'weight' | 'volume' | 'time' | 'distance' | 'rounds' | 'complexity' | 'reps'
export type TrendDirection = 'improving' | 'stable' | 'declining'

export interface ExerciseFinding {
  exercise_id: string
  name: string
  metric_type: ProgressionMetricType
  expected_value: number | null
  actual_value: number | null
  unit: string
  status: ProgressionStatus
  trend: TrendDirection
  change_summary: string
  /** What the measure counts, in the analytics vocabulary's words. */
  description?: string
  /** How far a measure without a trend is from one. */
  waiting_for?: string
}

/** How the review's score was made (src/analytics/review.py). */
export interface ScoreBreakdown {
  /** trends: the score is the measures' trends; collecting: none has one yet, no score.
   *  (compliance_only / compliance_and_trends from servers before 2026-10-16.) */
  basis: 'trends' | 'collecting' | 'not_started' | 'compliance_only' | 'compliance_and_trends'
  summary: string
  parts: { id: string; label: string; value: number; weight: number; points: number }[]
  completed: number
  scheduled: number
  measured: number
  waiting: number
  /** Each measure behind the trends part: its points when counted, else how
   *  far it is from a trend. Absent from an older server. */
  measures?: Array<{ id: string; name: string; status: string; points: number | null; detail: string | null }>
}

/** The band the score falls in, why, and every band — one set of labels for both clients. */
export interface ScoreStatus {
  id: 'on_track' | 'mixed' | 'off_track'
  label: string
  reason: string
  bands: { id: 'on_track' | 'mixed' | 'off_track'; label: string; min: number }[]
}

/** A measure of the methodology with no data yet, and what starts it. */
export interface PendingMeasure {
  id: string
  label: string
  description: string | null
  reason: string
  needs: { label: string; where: string }[]
}

export interface ProgressionAdjustment {
  type: string
  target: string
  direction: string
  reason: string
  magnitude: string | null
}

/** One ranked alternative for a slot, as POST /api/exercises/substitute returns it. */
export interface ExerciseAlternative {
  assignment: ExerciseAssignment
  score: number
  reasons: string[]
}

/** What POST /api/programs/adjust changed. */
export interface AdjustResult {
  saved: boolean
  revision: string | null
  programVersionId?: string | null
  applied: { type: string; from_week_index: number; weeks: number[]; exercises: number }
}

/** A Connect IQ watch bound to this account (GET /api/devices). */
export interface PairedDevice {
  deviceToken: string
  deviceName: string | null
  claimedAt: string | null
  lastUsedAt: string | null
}

/** One day's reading from the Connect IQ watch (GET /api/health/wellness/latest).
 *  Snake_case: the row as daily_wellness stores it; absent keys were not read. */
export interface WellnessReading {
  date: string
  source: string
  resting_hr?: number
  resting_hr_7d_avg?: number
  hr_min?: number
  body_battery_max?: number
  body_battery_min?: number
  body_battery_latest?: number
  recovery_time_h?: number
  vo2max?: number
  part_number?: string
  read_at?: string
  received_at?: string
  /** Named from the part number; null for a model data/garmin_devices.json lacks. */
  model?: string | null
}

export interface ProgressionReview {
  period_key: string
  period_type: 'weekly' | 'biweekly'
  generated_at: string | null
  overall_score: number | null
  readiness_trend: TrendDirection
  avg_readiness: number | null
  compliance_pct: number
  exercise_findings: ExerciseFinding[]
  flags: string[]
  recommendations: string[]
  adjustments: ProgressionAdjustment[]
  // Absent from a server that predates src/analytics/review.py.
  score_breakdown?: ScoreBreakdown
  score_status?: ScoreStatus | null
  /** What the compliance covers: "2 of 2 sessions so far · week 1". */
  scope_label?: string
  pending_measures?: PendingMeasure[]
  /** The section's job in one line. */
  purpose?: string
}

export interface MatchedSessionArchetype {
  name: string
  modality: string
  prescribedMinutes: number
}

export interface MatchedSessionWorkout {
  durationMinutes: number
  distanceKm: number | null
  hrAvg: number | null
  hrMax: number | null
  activityType: string
  source: string
  elevationGainM: number | null
}

export interface MatchedSessionSummary {
  sessionKey: string
  weekNumber: number
  dayName: string
  date: string
  importedWorkoutId: string
  archetype: MatchedSessionArchetype
  workout: MatchedSessionWorkout
  matchConfidence: 'auto' | 'manual'
  durationDeltaPct: number | null
  modalityMatch: 'exact' | 'family' | 'other'
  relevantMetrics: string[]
}

export interface ProgressionReviewSummary {
  period_key: string
  period_type: string
  generated_at: string
  overall_score: number | null
}

// ─── Training Load ────────────────────────────────────────────────────────────

export interface WeeklyLoad {
  week: string     // ISO week "2026-W20"
  trimp: number
  sessions: number
}

export interface PMCEntry {
  date: string     // YYYY-MM-DD
  ctl: number      // Chronic Training Load (τ = 42 days)
  atl: number      // Acute Training Load (τ = 7 days)
  tsb: number      // Training Stress Balance = CTL(yesterday) - ATL(yesterday)
  trimp: number    // daily TRIMP input
}

// ─── Async Parse Job ──────────────────────────────────────────────────────────

export interface ParseJobStatus {
  jobId: string
  status: 'queued' | 'parsing' | 'done' | 'error'
  progress: number   // 0.0 – 1.0
  stage: string
  error: string | null
}

// ─── Program analytics (GET /api/analytics/program) ───────────────────────────
// The document src/analytics/document.py produces. Progress entries are shaped by
// the primitive that made them; the common fields are typed, the rest is `extra`.

export type AnalyticsStatus =
  | 'ahead' | 'on_track' | 'behind' | 'stalled' | 'stable_by_design' | 'insufficient_data'
  | 'on_target' | 'off_target' | 'no_target' | 'met' | 'partial' | 'below' | 'off_plan' | 'error'

export type AnalyticsPrimitive =
  | 'set_load' | 'load_at_rpe' | 'rounds' | 'duration' | 'distance' | 'hold_seconds'
  | 'rate' | 'zone_minutes' | 'aerobic_efficiency' | 'unlocks' | 'benchmark_level' | 'session_completion'

export interface AnalyticsSeriesPoint {
  week: number | null
  x: number
  value: number | null
  date?: string
  isDeload: boolean
  [extra: string]: unknown
}

export interface AnalyticsExpectedPoint { week: number | null; x: number; value: number | null; date?: string | null }

export interface AnalyticsCoverage {
  inScope: number
  measured: number
  pct: number
  reason: string | null
}

export interface AnalyticsTrend { direction: 'improving' | 'stable' | 'declining' | 'insufficient_data'; slopePct: number; pointsUsed: number }

export interface AnalyticsExerciseResult {
  exerciseId: string
  name: string
  /** set_load: kg, or reps for a lift with no kg prescribed or logged. */
  unit?: string
  series: AnalyticsSeriesPoint[]
  expected: AnalyticsExpectedPoint[]
  trend: AnalyticsTrend
  status: AnalyticsStatus
  stalled?: boolean
  increment?: number
  prescribedNow?: number | null
  targetRpe?: number | null
  latest?: AnalyticsSeriesPoint | null
  bestEst1rm?: number | null
}

export interface AnalyticsProgressEntry {
  id: string
  label: string
  primitive: AnalyticsPrimitive
  philosophy: string
  weight: number
  headline: boolean
  source: 'declared' | 'default'
  metric: string
  unit: string
  series: AnalyticsSeriesPoint[]
  expected: AnalyticsExpectedPoint[]
  status: AnalyticsStatus
  trend: AnalyticsTrend
  coverage: AnalyticsCoverage
  evidence: string[]
  exercises?: AnalyticsExerciseResult[]
  leadExerciseId?: string | null
  weeks?: Array<Record<string, unknown>>
  byFramework?: Array<Record<string, unknown>>
  benchmarks?: Array<Record<string, unknown>>
  practised?: Array<{ exerciseId: string; name: string; sessions: number }>
  available?: Array<{ exerciseId: string; name: string; requires: string[] }>
  /** unlocks: movements left locked even with practice, those the athlete's
   *  level opened from day one, and the movements the program draws on. */
  lockedCount?: number
  assumedCount?: number
  programTotal?: number
  totals?: Record<string, number | null>
  /** False when no session of this program is in the entry's scope — a
   *  pentathlon cadence in General Practice. Absent on older documents. */
  applies?: boolean
  appliesIn?: Array<{ trackId: string; track: string; phases: string[] }>
  [extra: string]: unknown
}

export interface AnalyticsMethodology {
  philosophy: string
  weight: number
  analytics: 'declared' | 'default'
  headlineId: string | null
  entryIds: string[]
  measurable: number
  /** Entries that apply to this program; absent on older documents. */
  applicable?: number
  headlineSummary?: AnalyticsHeadlineSummary | null
  total: number
}

export interface AnalyticsScorecardRow {
  modality: ModalityId
  family: string
  tier: 'committed' | 'core' | 'supplementary' | 'unscheduled'
  priority: number
  plannedSessions: number
  completedSessions: number
  completionPct: number | null
  plannedMinutes: number
  actualMinutes: number
  weeklyPlannedMinutes: number
  weeklyActualMinutes: number
  minWeeklyMinutes: number | null
  maxWeeklyMinutes: number | null
  doseStatus: 'under' | 'on' | 'over' | 'unknown'
  planDoseStatus: 'under' | 'on' | 'over' | 'unknown'
}

export interface AnalyticsScorecard {
  headline: 'on_plan' | 'off_plan' | 'not_started'
  overallPct: number | null
  tiers: Record<string, { planned: number; completed: number; pct: number | null }>
  elapsedWeeks: number
  modalities: AnalyticsScorecardRow[]
  /** Sessions whose day has come, and how many were done (logged or matched). */
  plannedSessions?: number
  completedSessions?: number
  /** Completion per program week, elapsed sessions only — the Today card. */
  weeks?: { weekIndex: number; weekNumber: number; planned: number; completed: number; pct: number | null }[]
  /** This week: done of those due so far, and how many the week holds. */
  currentWeek?: { weekIndex: number; weekNumber: number; due: number; completed: number; total: number; isDeload: boolean } | null
}

/** A methodology's headline in a sentence, worded on the server for Today. */
export interface AnalyticsHeadlineSummary {
  entryId: string
  label: string
  primitive: AnalyticsPrimitive
  status: AnalyticsStatus
  measurable: boolean
  reason: string | null
  inScope: number
  value: number | null
  unit: string
  text: string | null
  subject: string | null
  trendDirection: string | null
  trendText: string | null
}

export interface AnalyticsFrame {
  status: 'not_started' | 'active' | 'complete'
  startDate: string
  today: string
  plannedWeeks: number
  elapsedWeeks: number
  deloadWeeks: number[]
  philosophies: Array<{
    id: string; name: string; progressionPhilosophy: string | null; intensityModel: string | null
    corePrinciples: string[]; weight: number; analytics: 'declared' | 'default'
  }>
  framework: {
    id: string; name: string; progressionModel: string
    intensityDistribution: Record<string, number> | null
    sessionsPerWeek: Record<string, number> | null
    modalityPriority: Record<string, string[]> | null
    notes: string | null
  } | null
  /** `name` is the phase kind; `label` and `description` are the philosophy's own. */
  phase: { name: string; id?: string | null; label?: string | null; weekInPhase: number | null; weekInProgram: number; totalWeeks: number; focus: string | null; description?: string | null; isDeload: boolean } | null
  track?: GoalTrack | null
  phaseSequence: Array<{ phase: string; phaseId?: string | null; name?: string | null; weeks: number; frameworkId: string | null; focus: string | null; description?: string | null }>
  planFidelity: Array<{ field: string; ideal: number; minimum: number | null; actual: number; unit: string; status: 'below_minimum' | 'below_ideal' | 'meets_ideal' }>
}

export interface AnalyticsIntensityWeek {
  week: number
  isDeload: boolean
  frameworkId: string | null
  zone1_2_pct: number
  zone3_pct: number
  zone4_5_pct: number
  max_effort_pct: number
  unclassified: number
  sessions: number
  classifiedMinutes: number
  actualPct: Record<string, number | null>
  plannedPct: Record<string, number> | null
}

export interface AnalyticsIntensity {
  status: AnalyticsStatus
  coverage: AnalyticsCoverage
  maxHr: number | null
  methods: Record<string, number>
  weeks: AnalyticsIntensityWeek[]
  byFramework: Array<{ frameworkId: string | null; classifiedMinutes: number; actualPct: Record<string, number | null>; plannedPct: Record<string, number> | null; deviationPts: Record<string, number> | null }>
  maxDeviationPts: number | null
  pct1rm?: { sessions: number; meanPct: number | null; rows: Array<{ week: number; exerciseId: string; pctOf1rm: number; targetPct: number | null }> }
  /** Planned against recorded minutes per zone, over the completed sessions
   *  whose programming prescribes heart-rate zones (src/analytics/hr_plan.py). */
  zones?: Array<{ zone: string; label: string; plannedMinutes: number; actualMinutes: number }>
}

export interface AnalyticsMovement {
  sets: { patterns: Array<{ pattern: string; planned: number; done: number }>; rollups: Record<string, { planned: number; done: number }> }
  minutes: { patterns: Array<{ pattern: string; planned: number; done: number }>; rollups: Record<string, { planned: number; done: number }>; assumed: number }
  unilateralShare: { planned: number | null; done: number | null }
  balance: Array<{ a: string; b: string; ratio: number | null; min: number; max: number; level: 'info' | 'warning'; outside: boolean; declared: boolean }>
  byArchetypeCategory: Record<string, { plannedSessions: number; completedSessions: number }>
}

export interface AnalyticsArchetypeRow {
  archetypeId: string
  name: string
  category: string | null
  modality: ModalityId
  scheduled: number
  completed: number
  matched: number
  prescribedMinutes: number
  completionPct: number | null
  meanDurationDeltaPct: number | null
  hr: { avg: number; max: number } | null
  leadLift: { exerciseId: string; firstEst1rm: number; latestEst1rm: number; sessions: number } | null
  slotTypes: string[]
}

export interface AnalyticsBenchmarkRow {
  benchmarkId: string
  name: string
  category: string
  domain: string | null
  unit: string
  metricType: string
  lowerIsBetter: boolean
  why: Array<'tested' | 'linked' | 'declared' | 'philosophy' | 'priority_modality'>
  /** Always true since 2026-10-23: every row is the program's own (tested,
   *  or estimated from a lift it schedules). An older server sent extras,
   *  false here, for "More standards". */
  primary?: boolean
  standards: Record<string, number>
  standardsText?: Record<string, string>
  latest: number | null
  latestDate: string | null
  derived: { value: number | null; est1rm: number; bodyweightKg: number | null; date?: string; reason?: string } | null
  value: number | null
  valueSource: 'logged' | 'derived' | null
  valueText?: string | null
  level: string | null
  levelIndex: number
  next: string | null
  gapToNext: number | null
  nextText?: string | null
  gapText?: string | null
  best?: number | null
  bestText?: string | null
  history: Array<{ date: string; value: number; valueText?: string }>
  /** Where the athlete stood when the block began. */
  atBlockStart?: { value: number; valueText: string; date: string; level: string | null; levelIndex: number } | null
  /** Levels moved this block; null with nothing to compare. */
  levelChange?: number | null
  /** The block's results, its starting standing first. */
  blockHistory?: Array<{ date: string; value: number; valueText: string; level: string | null }>
}

export interface ProgramAnalytics {
  status: 'ok' | 'no_program'
  revision?: string | null
  generatedAt?: string
  frame: AnalyticsFrame
  scorecard: AnalyticsScorecard
  intensity: AnalyticsIntensity
  methodologies: AnalyticsMethodology[]
  progress: AnalyticsProgressEntry[]
  /** Absent from a document cached before 2026-10-23. */
  exerciseSeries?: ExerciseSeriesSection
  movement: AnalyticsMovement
  archetypes: AnalyticsArchetypeRow[]
  benchmarks: { sex: string; blockStart?: string; bodyweightKg: number | null; bodyweightText?: string | null; bodyweightDate: string | null; benchmarks: AnalyticsBenchmarkRow[] }
  load: { pmc?: PMCEntry[]; readiness?: { score: number; status: string }; phase: string | null; isDeload: boolean; tsb: number | null; reading: string | null; note: string }
}

// ─── Exercise series ─────────────────────────────────────────────────────────
// `exerciseSeries` on GET /api/analytics/program — src/analytics/exercise_series.py.
// Every exercise of the program, session by session: prescribed and done, for
// the Progress tab's one chart; `measures` names the progress entries it also draws.

export type ExerciseSeriesMetricId =
  | 'weight' | 'reps' | 'sets' | 'totalReps' | 'volume' | 'est1rm' | 'rpe'
  | 'time' | 'hold' | 'rounds' | 'distance'

export type ExerciseSeriesValues = Partial<Record<ExerciseSeriesMetricId, number | null>>

export interface ExerciseSeriesPoint {
  date: string | null
  week: number
  x: number
  isDeload: boolean
  elapsed: boolean
  /** What the done values come from; null when nothing was logged. */
  source: 'log' | 'workout' | null
  sessionName: string | null
  done: ExerciseSeriesValues
  prescribed: ExerciseSeriesValues
  doneText: string | null
  prescribedText: string | null
  setsDone: Array<{ weightKg: number | null; reps: number | null; seconds: number | null; rpe: number | null }>
}

export interface ExerciseSeriesExercise {
  exerciseId: string
  name: string
  modality: string | null
  metrics: ExerciseSeriesMetricId[]
  defaultMetric: ExerciseSeriesMetricId
  scheduled: number
  logged: number
  points: ExerciseSeriesPoint[]
}

export interface ExerciseSeriesSection {
  metrics: Array<{ id: ExerciseSeriesMetricId; label: string; unit: string }>
  exercises: ExerciseSeriesExercise[]
  measures: Array<{ id: string; label: string; unit: string | null; philosophy: string; primitive: string }>
}

// ─── Development across programs ─────────────────────────────────────────────
// GET /api/analytics/development — src/analytics/development.py. The history
// tables read as one document: blocks (the activation timeline), per-lift
// series across the span, currencies, load with each week's block, and the
// standards ladder over time.

export interface DevelopmentBlock {
  id: number
  versionId: string
  label: string
  methodologies: Array<{ id: string; name: string }>
  from: string
  to: string | null
  isActive: boolean
  weeks: number
  plannedTotal: number
  planned: number
  completed: number
  completionPct: number | null
  source: string | null
}

export interface DevelopmentLiftPoint {
  date: string
  blockId: number | null
  weight: number
  reps: number | null
  est1rm: number | null
  isDeload: boolean
}

export interface DevelopmentPerBlock {
  blockId: number
  sessions: number
  first: number
  last: number
  best: number
  delta: number
}

export interface DevelopmentLift {
  exerciseId: string
  name: string
  unit: string
  points: DevelopmentLiftPoint[]
  perBlock: DevelopmentPerBlock[]
  trend: AnalyticsTrend
  blocks: number
}

export interface DevelopmentCurrency {
  exerciseId: string
  name: string
  metric: 'rounds' | 'minutes' | 'km'
  points: Array<{ date: string; blockId: number | null; value: number; isDeload: boolean }>
  perBlock: DevelopmentPerBlock[]
  trend: AnalyticsTrend
}

export interface DevelopmentBenchmark {
  benchmarkId: string
  name: string
  unit: string
  domain?: string | null
  metricType?: string | null
  lowerIsBetter: boolean
  standards?: Record<string, number>
  standardsText?: Record<string, string>
  /** One of the current program's own standards. */
  inCurrentProgram?: boolean
  history: Array<{ date: string; value: number; valueText?: string; level: string | null; levelIndex: number; blockId?: number | null }>
  latestLevel: string | null
  latestLevelIndex: number
  levelsGained: number
}

export interface DevelopmentAnalytics {
  status: 'ok' | 'no_history'
  window: { from: string; to: string }
  blocks: DevelopmentBlock[]
  lifts: DevelopmentLift[]
  currencies: DevelopmentCurrency[]
  load: {
    weekly: Array<WeeklyLoad & { blockId: number | null }>
    pmc: Array<PMCEntry & { blockId: number | null }>
  }
  benchmarks: DevelopmentBenchmark[]
  generatedAt?: string
}

// ─── Analytics specs (what a philosophy tracks, described) ───────────────────
// GET /api/analytics/specs — src/analytics/describe.py. Static: the composed
// spec of every package (declared analytics.yaml or synthesised default),
// resolved to names, for the Explore tab. No program, no user.

export interface SpecNamed { id: string; name: string }

export interface ProgressSpecScope {
  modalities: SpecNamed[]
  archetypes: SpecNamed[]
  frameworks: SpecNamed[]
  exercises: SpecNamed[]
  movementPatterns: string[]
  slotTypes: string[]
  slotRoles: string[]
  excludeSlotRoles: string[]
}

export type ProgressSpecExpected =
  | { kind: 'prescribed' | 'achieved_plus_increment' | 'none' }
  | { kind: 'load_field' | 'framework_field'; field: string }
  | { kind: 'constant'; value: number; unit?: string }

export interface ProgressSpecEntry {
  id: string
  label: string
  primitive: AnalyticsPrimitive
  headline: boolean
  source: 'declared' | 'default'
  scope: ProgressSpecScope
  expected: ProgressSpecExpected
  stall: { sessions: number; tolerancePct: number } | null
  benchmarks: Array<{ id: string; name: string; unit: string; category: string | null }>
  targetLevel: string | null
  rpmTarget: number | null
  minSessions: number
  notes: string | null
}

export interface SpecNeed {
  field: string
  label: string
  where: string
  entries: string[]
}

export interface PhilosophySpec {
  philosophy: string
  name: string
  source: 'declared' | 'default'
  file: string | null
  progressionPhilosophy: string | null
  headlineId: string | null
  progress: ProgressSpecEntry[]
  movement: { balance: Array<{ a: string; b: string; min: number; max: number }>; declared: boolean }
  benchmarks: Array<{ id: string; name: string; category: string; domain: string | null; unit: string; why: 'declared' | 'entry' | 'source' }>
  needs: SpecNeed[]
}

export interface PrimitiveVocabulary {
  label: string
  measures: string
  unit: string
  needs: string[]
  expectedKinds: string[]
}

export interface AnalyticsSpecs {
  vocabulary: {
    primitives: Record<AnalyticsPrimitive, PrimitiveVocabulary>
    needs: Record<string, { label: string; where: string }>
  }
  philosophies: Record<string, PhilosophySpec>
}

// ─── Explore ▸ Philosophies: GET /philosophies/<id>/describe ────────────────
// A philosophy as its package writes it (src/explore_philosophy.py); the page
// only lays it out.

export interface DescribedMix { modality: string; perWeek: number; share: number }

export interface DescribedTemplatePiece { category: string; name: string; modality: string | null }
export interface DescribedTemplateDay {
  day: string
  rest: boolean
  pieces: DescribedTemplatePiece[]
  warmUp: boolean
  light: boolean
}

export interface DescribedItem {
  exercise: string
  name: string
  role: string | null
  prescription: string
  note: string | null
  optional: boolean
  alternatives: string[]
}

export interface DescribedModule {
  id: string
  name: string
  modality: string
  archetype: string | null
  archetypeName: string | null
  perWeek: number | null
  perWeekByDays: Record<string, number> | null
  levels: string[]
  optional: boolean
  whenMastered: boolean
  requires: string[]
  maxRpe: number | null
  progression: string
  periods: Array<{ name: string; weeks: number; deload: boolean }>
  variants: Array<{ id: string; name: string; archetype: string | null; items: DescribedItem[] }>
  items: DescribedItem[]
  /** One text, or null when the source says it per level (then `adviceByLevel`). */
  advice: string | null
  adviceByLevel: Array<{ level: TrainingLevel; text: string }> | null
}

export type DescribedWeek =
  | { kind: 'template'; weeks: DescribedTemplateDay[][]; dropOrder: string[]; warmUp: string | null }
  | { kind: 'contract'; modules: DescribedModule[] }
  | { kind: 'framework'; sessions: Array<{ modality: string; perWeek: number }> }

export interface DescribedPhase {
  id: string
  name: string
  kind: PhaseKind
  weeks: number
  repeatable: boolean
  framework: { id: string; name: string }
  focus: string | null
  description: string | null
  adaptations: string[]
  intensity: string | null
  intensitySplit: Record<string, number>
  deload: string | null
  tests: Array<{ when: string; sessions: string[]; standards: string[]; onDeload: boolean }>
  notYet: string[]
  week: DescribedWeek
  mix: DescribedMix[]
}

export interface DescribedTrack {
  id: string
  name: string
  description: string | null
  primary: boolean
  forLevels: TrainingLevel[]
  levels: TrainingLevel[]
  builtBy: 'contract' | 'template' | 'framework'
  weeks: number
  repeatable: boolean
  notes: string | null
  kettlebellPair: boolean
  mix: DescribedMix[]
  phases: DescribedPhase[]
}

export interface DescribedSlot {
  role: string
  name: string
  slotType: string
  prescription: string
  note: string | null
  parent: string | null
  listed: boolean
  technique: boolean
  standard: string | null
  exercises: Array<{ id: string; name: string }>
}

export interface DescribedSession {
  id: string
  name: string
  modality: string
  minutes: number | null
  levels: TrainingLevel[]
  test: boolean
  note: string | null
  equipment: string[]
  slots: DescribedSlot[]
}

export interface DescribedSessionGroup {
  kind: 'category' | 'module' | 'modality' | 'tests'
  id: string
  name: string | null
  modality: string | null
  /** One text, or null when the source says it per level (then `adviceByLevel`). */
  advice: string | null
  adviceByLevel: Array<{ level: TrainingLevel; text: string }> | null
  warmUp: boolean
  sessions: string[]
}

export interface PhilosophyDescription {
  id: string
  name: string
  summary: string | null
  accent: string | null
  bias: string[]
  scope: string[]
  avoidWith: string[]
  principles: string[]
  models: { intensity: string | null; progression: string | null }
  levels: TrainingLevel[]
  equipment: Array<{ id: string; name: string }>
  expectations: GoalExpectations | null
  primaryTrackId: string | null
  mix: DescribedMix[]
  tracks: DescribedTrack[]
  borrows: Array<{ package: string; label: string; reason: string | null; modalities: string[] }>
  sources: Array<{ id: string | null; title: string; where: string | null; kind: string | null; read: string | null; published: string | null }>
  rules: Array<{ id: string; text: string; cites: Array<{ source: string; quote: string | null }> }>
  inventions: Array<{ id: string; text: string }>
  open: string[]
  groups: DescribedSessionGroup[]
  sessions: Record<string, DescribedSession>
  glance: PhilosophyGlance
}

// GET /philosophies/glance, and `glance` on the describe document: the
// comparable facts, the same keys for every philosophy (explore_philosophy.glance).

export interface GlancePhase {
  id: string
  name: string
  kind: PhaseKind
  weeks: number
  repeatable: boolean
  focus: string | null
  /** The source's first week, day by day (templates only): modalities, null for rest. */
  days: (string[] | null)[] | null
  daysPerWeek: number | null
  minutes: number | null
  sessionsPerWeek: number
  mix: DescribedMix[]
  intensitySplit: Record<string, number>
  tests: number
}

export interface GlanceTrack {
  id: string
  name: string
  primary: boolean
  forLevels: TrainingLevel[]
  levels: TrainingLevel[]
  builtBy: 'contract' | 'template' | 'framework'
  weeks: number
  repeatable: boolean
  kettlebellPair: boolean
  requires: string[]
  daysPerWeek: { min: number; max: number } | null
  minutes: { min: number; max: number } | null
  mix: DescribedMix[]
  intensity: Record<string, number>
  tests: number
  goals: string[]
  phases: GlancePhase[]
}

export interface PhilosophyGlance {
  id: string
  name: string
  accent: string | null
  bias: string[]
  levels: TrainingLevel[]
  weeks: { min: number; ideal: number } | null
  daysPerWeek: { min: number; ideal: number } | null
  sessionMinutes: { min: number; ideal: number } | null
  longSessionMinutes: number | null
  equipment: Array<{ id: string; name: string }>
  primaryTrackId: string | null
  mix: DescribedMix[]
  intensity: Record<string, number>
  tested: string[]
  measures: { headline: string | null; signals: number; standards: Array<{ id: string; name: string; domain: string | null }> }
  counts: { tracks: number; rules: number; sources: number; inventions: number; open: number; sessions: number }
  tracks: GlanceTrack[]
}

// ─── Dev Lab: package portability (GET /api/dev/portability, src/portability.py) ──

export type PortabilityShape = 'contract' | 'templates' | 'scheduler'

export interface PortabilityPackage {
  id: string
  name: string
  tracks: Array<{ track: string; name: string | null; shape: PortabilityShape }>
  /** present is null for a file the API image leaves out, when this is the image. */
  files: Array<{ id: string; path: string; required: boolean; present: boolean | null }>
  /** done is null where the record's file is not in this deployment (the API image has no docs/). */
  outside: Array<{ id: string; label: string; file: string; done: boolean | null; how: string }>
  vocabulary: Array<{ kind: string; count: number; unknown: string[] }>
  collisions: number
  ready: boolean
}

export interface PortabilityGap {
  id: string
  title: string
  kind: 'gate' | 'tooling' | 'commons' | 'code' | 'client' | 'watch' | 'docs'
  impact: 'blocks' | 'degrades' | 'cosmetic'
  detail?: string
  anchors: string[]
  roadmap: string | null
  status: 'open' | 'by_design'
}

export interface PortabilityReport {
  packagesDir: string
  /** Records outside the folder this deployment cannot read; `ready` says nothing about them. */
  unchecked: string[]
  verdict: string
  packages: PortabilityPackage[]
  collisions: Array<{ kind: string; id: string; packages: string[]; kept: string }>
  sharedExercises: number
  gaps: PortabilityGap[]
}
