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
  incompatible_with: string[]
  framework_selection: FrameworkSelection
  event_date?: string | null
  notes?: string
}

// ─── Constraints ──────────────────────────────────────────────────────────────

export interface AthleteConstraints {
  equipment: EquipmentId[]
  equipment_profile?: EquipmentProfileId | 'custom'
  days_per_week: number
  session_time_minutes: number
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
  training_phase_forced?: TrainingPhase
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
  typical_volume?: { sets: number; reps: number }
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
