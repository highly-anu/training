// The colour each Explore level is drawn in, one place for the landings, the
// detail headers and the lineage pills (docs/frontend-design.md §8.5, §13.8).
import { MODALITY_COLORS } from '@/lib/modalityColors'
import type { ModalityId } from '@/api/types'

export const EX_CATEGORY_COLORS: Record<string, string> = {
  barbell:     '#ef4444',
  kettlebell:  '#f97316',
  bodyweight:  '#10b981',
  aerobic:     '#0ea5e9',
  loaded_carry:'#f59e0b',
  sandbag:     '#ca8a04',
  mobility:    '#14b8a6',
  skill:       '#8b5cf6',
  rehab:       '#84cc16',
}

export const ARCH_CAT_COLORS: Record<string, string> = {
  strength:       '#ef4444',
  conditioning:   '#f97316',
  kettlebell:     '#eab308',
  gpp_durability: '#22c55e',
  movement_skill: '#3b82f6',
}

/** A philosophy is drawn in its first bias's modality colour; its frameworks in its own. */
export function philosophyHex(bias: string[] | undefined): string {
  return MODALITY_COLORS[bias?.[0] as ModalityId]?.hex ?? '#6366f1'
}
