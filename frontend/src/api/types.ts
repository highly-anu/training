// ─── Enumerations ─────────────────────────────────────────────────────────────

export type ModalityId =
  | 'max_strength'
  | 'strength_endurance'
  | 'relative_strength'
  | 'aerobic_base'
  | 'anaerobic_intervals'
  | 'mixed_modal_conditioning'
  | 'power'
  | 'mobility'
  | 'movement_skill'
  | 'durability'
  | 'combat_sport'
  | 'rehab'

export type TrainingPhase =
  | 'active'
  | 'base'
  | 'build'
  | 'peak'
  | 'taper'
  | 'deload'
  | 'maintenance'
  | 'rehab'
  | 'post_op'
  | 'transition'
  | 'specific'

export type TrainingLevel = 'novice' | 'intermediate' | 'advanced' | 'elite'

export type FatigueState = 'fresh' | 'normal' | 'accumulated' | 'overreached'

export type EquipmentId =
  | 'barbell'
  | 'rack'
  | 'plates'
  | 'kettlebell'
  | 'dumbbell'
  | 'pull_up_bar'
  | 'rings'
  | 'parallettes'
  | 'rower'
  | 'bike'
  | 'ski_erg'
  | 'ruck_pack'
  | 'sandbag'
  | 'sled'
  | 'tire'
  | 'medicine_ball'
  | 'resistance_band'
  | 'rope'
  | 'box'
  | 'ghd'
  | 'jump_rope'
  | 'open_space'
  | 'pool'

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

export interface PhaseEntry {
  phase: TrainingPhase
  weeks: number
  focus?: string
  priority_override?: GoalPriorities
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
  training_phase: TrainingPhase
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
  gap_reason?: string | null
  /** Links an `amrap_movement` component to the `amrap` slot it belongs to. */
  parent_slot_role?: string
  /** Structural slot with no exercise (BJJ rounds, circuit round wrappers). */
  skip_exercise?: boolean
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
  exercises: ExerciseAssignment[]
  complementary_work?: ComplementaryExercise[]
  duration_min?: number
  provenance?: SessionProvenance | null
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
}

// ─── Generated Program ────────────────────────────────────────────────────────

export interface WeekVolumeSummary {
  week_number: number
  strength_sets: number
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
  phase: TrainingPhase
  is_deload: boolean
  schedule: Record<string, Session[]>
  framework?: string
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

export interface GeneratedProgram {
  goal: GoalProfile
  constraints: AthleteConstraints
  validation: ValidationResult
  weeks: WeekData[]
  volume_summary?: WeekVolumeSummary[]
  program_start_date?: string
  compromises?: string[]
  coverage_report?: CoverageReport | null
}

// ─── Generation Trace ─────────────────────────────────────────────────────────

export interface CandidateScore {
  id: string
  name: string
  score: number
  breakdown: Record<string, number>
  package?: string  // First declaring package (display only)
  packages?: string[]  // Every philosophy package declaring this exercise id
}

export interface ArchetypeTrace {
  selected_id: string | null
  filter_counts: Record<string, number>
  candidates: CandidateScore[]
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
  archetype: ArchetypeTrace
  slots: SlotTrace[]
  progression: ProgressionEntry[]
}

export interface FrameworkSelectionTrace {
  forced_override: string | null
  default_id: string
  alternatives_checked: Array<{ framework_id: string; condition: string; matched: boolean }>
  selected_id: string
  selection_reason: string
  days_constraint?: { athlete_days: number; framework_min: number; framework_max: number; days_fallback: string | null }
}

export interface SchedulerTrace {
  framework_selection: FrameworkSelectionTrace
  allocation: {
    phase_priorities: Record<string, number>
    raw: Record<string, number>
    final: Record<string, number>
  }
  day_assignment: {
    modality_order: string[]
    day_pool: number[]
    assignments: Record<string, string[]>
  }
  is_deload: boolean
  deload_freq_weeks: number
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
  philosophy_mode?: 'synthetic_goal' | 'explicit_goal'
}

export interface TracedProgram extends GeneratedProgram {
  generation_trace?: GenerationTrace
}

// ─── Benchmarks ───────────────────────────────────────────────────────────────

export type BenchmarkLevel = 'entry' | 'intermediate' | 'advanced' | 'elite'

/** Drives which benchmark standards the athlete is scored against. */
export type Sex = 'male' | 'female'

export interface BenchmarkStandard {
  id: string
  name: string
  category: 'strength' | 'conditioning' | 'cell'
  domain?: string
  unit: string
  standards: Record<BenchmarkLevel, number>
  lower_is_better?: boolean
  notes?: string
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

export interface FrameworkPhaseEntry {
  phase: string
  weeks: number
  framework_id?: string
  focus?: string
}

export interface FrameworkGroup {
  id: string
  name: string
  type: 'alternatives' | 'sequential'
  frameworks: string[]  // Framework IDs
  canonical_phase_sequence?: FrameworkPhaseEntry[]  // Required when type=sequential
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
  primary_framework_id?: string
  framework_groups?: FrameworkGroup[]  // NEW - replaces frameworks_are_phases
  expectations?: GoalExpectations  // Full program expectations (for phased/sequential programs)

  // DEPRECATED - kept for backward compatibility during transition
  frameworks_are_phases?: boolean
  canonical_phase_sequence?: FrameworkPhaseEntry[]
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
  sets: SetPerformance[]
  rpe?: RPE
  notes?: string
  /**
   * Outcomes for slots that are not sets × reps — what the OutcomeLogger
   * writes and what src/progression_tracker.py and the analytics engine
   * read. Until the logger existed nothing ever wrote these.
   */
  rounds?: number
  durationSec?: number
  distanceKm?: number
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
}

export interface ProgressionAdjustment {
  type: string
  target: string
  direction: string
  reason: string
  magnitude: string | null
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
}

export interface ExerciseHistoryPoint {
  date: string
  week_number: number
  session_key: string
  best_weight_kg: number | null
  total_volume: number | null
  est_1rm: number | null
  best_reps: number | null
  rpe: number | null
  duration_sec: number | null
  distance_km: number | null
  rounds_completed: number | null
  hr_avg: number | null
  hr_max: number | null
  source?: 'matched_workout'
}

export interface ExerciseExpectedPoint {
  week_number: number
  expected_value: number | null
  unit: string
  metric_type: ProgressionMetricType
}

export interface ExerciseHistoryItem {
  exerciseId: string
  name: string
  history: ExerciseHistoryPoint[]
  expected: ExerciseExpectedPoint[]
}

export interface ExerciseHistoryResponse {
  exercises: ExerciseHistoryItem[]
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

export interface AnalyticsExpectedPoint { week: number | null; x: number; value: number | null }

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
  totals?: Record<string, number | null>
  [extra: string]: unknown
}

export interface AnalyticsMethodology {
  philosophy: string
  weight: number
  analytics: 'declared' | 'default'
  headlineId: string | null
  entryIds: string[]
  measurable: number
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
  phase: { name: string; weekInPhase: number | null; weekInProgram: number; totalWeeks: number; focus: string | null; isDeload: boolean } | null
  phaseSequence: Array<{ phase: string; weeks: number; frameworkId: string | null; focus: string | null }>
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
  why: Array<'philosophy' | 'priority_modality' | 'declared'>
  standards: Record<string, number>
  latest: number | null
  latestDate: string | null
  derived: { value: number | null; est1rm: number; bodyweightKg: number | null; date?: string; reason?: string } | null
  value: number | null
  valueSource: 'logged' | 'derived' | null
  level: string | null
  levelIndex: number
  next: string | null
  gapToNext: number | null
  history: Array<{ date: string; value: number }>
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
  movement: AnalyticsMovement
  archetypes: AnalyticsArchetypeRow[]
  benchmarks: { sex: string; bodyweightKg: number | null; bodyweightDate: string | null; benchmarks: AnalyticsBenchmarkRow[] }
  load: { pmc?: PMCEntry[]; readiness?: { score: number; status: string }; phase: string | null; isDeload: boolean; tsb: number | null; reading: string | null; note: string }
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
