import type { Framework, ModalityId, Philosophy } from '@/api/types'
import { MODALITY_COLORS } from '@/lib/modalityColors'

/**
 * How a philosophy becomes a priority vector for the builder. Lived inside
 * ProgramSource; Explore's "Build with this" needs the same derivation, so it
 * is one function now.
 */

export const MODALITY_ORDER: ModalityId[] = [
  'max_strength', 'relative_strength', 'strength_endurance', 'power',
  'aerobic_base', 'anaerobic_intervals', 'mixed_modal_conditioning',
  'durability', 'mobility', 'movement_skill', 'combat_sport', 'rehab',
]

export const DEFAULT_PRIORITIES = Object.fromEntries(
  MODALITY_ORDER.map((id) => [id, 1 / MODALITY_ORDER.length])
) as Record<ModalityId, number>

/**
 * Normalised priorities from the philosophy's primary framework's
 * sessions-per-week; equal weight across its bias modalities when it has none.
 */
export function derivePhilosophyPriorities(
  phil: Philosophy,
  frameworks: Framework[]
): Record<ModalityId, number> {
  const philFrameworks = frameworks.filter((f) => f.source_philosophy === phil.id)
  const sessions = philFrameworks[0]?.sessions_per_week

  if (sessions && Object.keys(sessions).length > 0) {
    const total = Object.values(sessions).reduce((s, v) => s + (v ?? 0), 0)
    if (total > 0) {
      return Object.fromEntries(
        MODALITY_ORDER.map((id) => [id, (sessions[id as ModalityId] ?? 0) / total])
      ) as Record<ModalityId, number>
    }
  }

  const biasIds = (phil.bias ?? []).filter((b): b is ModalityId => b in MODALITY_COLORS)
  const n = biasIds.length || 1
  return Object.fromEntries(
    MODALITY_ORDER.map((id) => [id, biasIds.includes(id) ? 1 / n : 0])
  ) as Record<ModalityId, number>
}

/** A philosophy with sequential phases runs as a "Full Program" with no fixed framework. */
export function philosophyHasSequentialPhases(phil: Philosophy): boolean {
  return !!(phil.framework_groups?.some((g) => g.type === 'sequential')
    || (phil.canonical_phase_sequence && phil.canonical_phase_sequence.length > 0))
}

export function primaryFrameworkFor(phil: Philosophy, frameworks: Framework[]): Framework | undefined {
  return frameworks.find((f) => f.source_philosophy === phil.id)
}
