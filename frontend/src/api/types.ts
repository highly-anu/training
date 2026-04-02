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

// ─── Goal Profile ──────────────────────────────────────────────────────────────

export type GoalPriorities = Partial<Record<ModalityId, number>>

export interface PhaseEntry {
  phase: TrainingPhase
  weeks: number
  focus: string
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

export interface Exercise {
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
  sources: string[]
  notes?: string
}

// ─── Archetypes ───────────────────────────────────────────────────────────────

export interface ArchetypeSlot {
  role: string
  slot_type: string
  sets?: number
  reps?: number | string
  intensity?: string
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
  modality: ModalityId
  category: string
  duration_estimate_minutes: number
  required_equipment: EquipmentId[]
  applicable_phases: TrainingPhase[]
  training_levels: TrainingLevel[]
  slots: ArchetypeSlot[]
  sources: string[]
}

// ─── Exercise Load (per session assignment) ───────────────────────────────────

export interface ExerciseLoad {
  sets?: number
  reps?: number | string
  weight_kg?: number
  target_rpe?: number
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
}

// ─── Session ──────────────────────────────────────────────────────────────────

export interface ExerciseAssignment {
  exercise: Exercise
  load: ExerciseLoad
  meta?: boolean
  slot_role?: string
  load_note?: string
  notes?: string
}

export interface Session {
  modality: ModalityId
  archetype: Archetype
  exercises: ExerciseAssignment[]
  duration_min?: number
}

// ─── Generated Program ────────────────────────────────────────────────────────

export interface WeekVolumeSummary {
  week_number: number
  strength_sets: number
  cond_minutes: number
  dur_minutes: number
  mob_minutes: number
  total_minutes: number
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
}

// ─── Generation Trace ─────────────────────────────────────────────────────────

export interface CandidateScore {
  id: string
  name: string
  score: number
  breakdown: Record<string, number>
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
}

export interface TracedProgram extends GeneratedProgram {
  generation_trace?: GenerationTrace
}

// ─── Benchmarks ───────────────────────────────────────────────────────────────

export type BenchmarkLevel = 'entry' | 'intermediate' | 'advanced' | 'elite'

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
  deload_protocol?: { frequency_weeks: number; volume_reduction_pct: number; intensity_change: string }
  sources?: string[]
  notes?: string
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

export type ImportSource = 'apple_health' | 'strava' | 'manual' | 'apple_watch_live' | 'fit_file'
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
}

export interface HRZoneDistribution {
  z1: number // % of time
  z2: number
  z3: number
  z4: number
  z5: number
  method: 'samples' | 'summary_estimate'
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
}

export interface ExercisePerformance {
  sets: SetPerformance[]
  rpe?: RPE
  notes?: string
}

export interface SessionPerformanceLog {
  sessionKey: string
  importedWorkoutId?: string
  exercises: Record<string, ExercisePerformance>
  notes: string
  fatigueRating?: FatigueRating
  completedAt: string
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
  sessionKey: string
  matchConfidence: MatchConfidence
  matchedAt: string
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
