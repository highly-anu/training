import type { ShareRecipe } from '@/api/shares'
import type { BuilderLane, SourceMode } from '@/store/builderStore'

/**
 * A shared program's recipe as the program builder holds a draft: the source,
 * the track and where it starts, the length, a contract's options — and
 * nothing of the athlete, whose own settings the builder's later steps add.
 * Weights are the builder's 0–100; it normalises them when it generates.
 */
export interface RecipeDraft {
  sourceMode: SourceMode
  selectedGoalIds: string[]
  selectedPhilosophyIds: string[]
  philosophyWeights: Record<string, number>
  selectedTrackId: string | null
  startPhaseId: string | null
  numWeeks: number | null
  lanes: BuilderLane[]
  contractOptions: Record<string, string> | null
}

export function draftFromRecipe(recipe: ShareRecipe | null | undefined): RecipeDraft | null {
  if (!recipe) return null
  const base = {
    selectedGoalIds: ['general_gpp'],
    numWeeks: recipe.num_weeks ?? null,
    contractOptions: recipe.contract_options ?? null,
  }
  if (recipe.lanes && recipe.lanes.length > 1) {
    return {
      ...base,
      sourceMode: 'blend',
      selectedPhilosophyIds: [...new Set(recipe.lanes.map((l) => l.philosophy_id))],
      philosophyWeights: {},
      selectedTrackId: null,
      startPhaseId: null,
      lanes: recipe.lanes.map((l) => ({
        philosophyId: l.philosophy_id, trackId: l.track_id ?? null,
        weight: Math.round((l.weight ?? 0) * 100), startPhaseId: l.start_phase ?? null,
      })),
    }
  }
  if (recipe.philosophy_ids && recipe.philosophy_ids.length > 1) {
    return {
      ...base,
      sourceMode: 'blend',
      selectedPhilosophyIds: recipe.philosophy_ids,
      philosophyWeights: Object.fromEntries(recipe.philosophy_ids.map((id) =>
        [id, Math.round((recipe.philosophy_weights?.[id] ?? 1 / recipe.philosophy_ids!.length) * 100)])),
      selectedTrackId: recipe.track_id ?? null,
      startPhaseId: recipe.start_phase ?? null,
      lanes: [],
    }
  }
  const id = recipe.philosophy_id ?? recipe.philosophy_ids?.[0]
  if (!id) return null
  return {
    ...base,
    sourceMode: 'philosophy',
    selectedPhilosophyIds: [id],
    philosophyWeights: {},
    selectedTrackId: recipe.track_id ?? null,
    startPhaseId: recipe.start_phase ?? null,
    lanes: [],
  }
}
