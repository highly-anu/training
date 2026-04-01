export type ModelType =
  | 'exercises'
  | 'archetypes'
  | 'modalities'
  | 'goals'
  | 'frameworks'
  | 'philosophies'
  | 'benchmarks'
  | 'injuryFlags'
  | 'equipmentProfiles'

export interface NavigateToFn {
  (type: ModelType, id: string): void
}
