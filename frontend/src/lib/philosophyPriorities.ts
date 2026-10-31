import type { Framework, ModalityId, Philosophy } from '@/api/types'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import { MODALITY_IDS } from '@/lib/gen/clientVocab'
import { mainFramework, resolveTrack } from '@/lib/tracks'

/**
 * How a philosophy becomes a priority vector for the builder. Lived inside
 * ProgramSource; Explore's "Build with this" needs the same derivation, so it
 * is one function now.
 */

/** The modalities in their listed order (each modality file's `display.order`). */
export const MODALITY_ORDER: readonly ModalityId[] = MODALITY_IDS

export const DEFAULT_PRIORITIES = Object.fromEntries(
  MODALITY_ORDER.map((id) => [id, 1 / MODALITY_ORDER.length])
) as Record<ModalityId, number>

/**
 * Normalised priorities from the track's main framework's sessions-per-week
 * (the primary track unless one is named — the same framework the server's
 * goal takes its priorities from); equal weight across the philosophy's bias
 * modalities when it has none.
 */
export function derivePhilosophyPriorities(
  phil: Philosophy,
  frameworks: Framework[],
  trackId?: string | null,
): Record<ModalityId, number> {
  const sessions = mainFramework(resolveTrack(phil, trackId), frameworks)?.sessions_per_week

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
