import type { Framework, ModalityId, Philosophy } from '@/api/types'
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

/** The listed modalities, then any others named (a package's own, from its
 *  `vocabulary.yaml`: served, never compiled in), each once. */
function withOwn(ids: Iterable<string>): ModalityId[] {
  return [...new Set<string>([...MODALITY_ORDER, ...ids])] as ModalityId[]
}

/**
 * Normalised priorities from the track's main framework's sessions-per-week
 * (the primary track unless one is named — the same framework the server's
 * goal takes its priorities from); equal weight across the philosophy's bias
 * modalities when it has none. A modality the package brings itself has its
 * share like any other: the vector used to cover the compiled list only, so a
 * method made of its own modalities was sent to the server as all zeros.
 */
export function derivePhilosophyPriorities(
  phil: Philosophy,
  frameworks: Framework[],
  trackId?: string | null,
): Record<ModalityId, number> {
  const sessions = mainFramework(resolveTrack(phil, trackId), frameworks)?.sessions_per_week as
    Record<string, number | undefined> | undefined

  if (sessions && Object.keys(sessions).length > 0) {
    const total = Object.values(sessions).reduce<number>((s, v) => s + (v ?? 0), 0)
    if (total > 0) {
      return Object.fromEntries(
        withOwn(Object.keys(sessions)).map((id) => [id, (sessions[id] ?? 0) / total])
      ) as Record<ModalityId, number>
    }
  }

  const biasIds: string[] = phil.bias ?? []
  const n = biasIds.length || 1
  return Object.fromEntries(
    withOwn(biasIds).map((id) => [id, biasIds.includes(id) ? 1 / n : 0])
  ) as Record<ModalityId, number>
}

/** Weighted average of priorities across several philosophies. */
export function deriveBlendedPriorities(
  philIds: string[],
  philWeights: Record<string, number>,
  philosophies: Philosophy[],
  frameworks: Framework[],
): Record<ModalityId, number> {
  const totalW = philIds.reduce((s, id) => s + (philWeights[id] ?? 50), 0)
  const blended: Record<string, number> = Object.fromEntries(MODALITY_ORDER.map((id) => [id, 0]))

  for (const philId of philIds) {
    const phil = philosophies.find((p) => p.id === philId)
    if (!phil) continue
    const w = (philWeights[philId] ?? 50) / totalW
    for (const [id, share] of Object.entries(derivePhilosophyPriorities(phil, frameworks))) {
      blended[id] = (blended[id] ?? 0) + share * w
    }
  }

  const sum = Object.values(blended).reduce((s, v) => s + v, 0)
  if (sum === 0) return DEFAULT_PRIORITIES
  return Object.fromEntries(Object.entries(blended).map(([id, v]) => [id, v / sum])) as Record<ModalityId, number>
}

/** Whether two priority vectors say the same thing (a missing modality is 0). */
export function samePriorities(
  a: Partial<Record<string, number>> | null | undefined,
  b: Partial<Record<string, number>> | null | undefined,
): boolean {
  if (!a || !b) return false
  return [...new Set([...Object.keys(a), ...Object.keys(b)])]
    .every((id) => Math.abs((a[id] ?? 0) - (b[id] ?? 0)) < 1e-6)
}
