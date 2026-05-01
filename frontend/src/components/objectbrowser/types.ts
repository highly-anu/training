export type ModelType =
  | 'exercises'
  | 'archetypes'
  | 'modalities'
  | 'frameworks'
  | 'philosophies'
  | 'benchmarks'
  | 'injuryFlags'
  | 'equipmentProfiles'

export interface NavigateToFn {
  (type: ModelType, id: string): void
}

export interface OpenInOntologyFn {
  (nodeId: string): void
}
