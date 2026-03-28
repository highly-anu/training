import type { ModalityId } from '@/api/types'

export function sortPriorities(
  priorities: Partial<Record<ModalityId, number>>
): Array<{ modality: ModalityId; weight: number }> {
  return Object.entries(priorities)
    .filter(([, weight]) => (weight ?? 0) > 0)
    .sort(([, a], [, b]) => (b ?? 0) - (a ?? 0))
    .map(([modality, weight]) => ({
      modality: modality as ModalityId,
      weight: weight ?? 0,
    }))
}
