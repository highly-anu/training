import type { PhaseKind } from '@/api/types'
import { PHASE_DISPLAY } from '@/lib/gen/clientVocab'

export interface PhaseColor {
  hex: string
  bg: string
  text: string
  label: string
}

// Each kind's colour, tint classes and fallback label come from
// data/commons/phase_kinds.yaml (`display`), through tools/gen_client_vocab.py,
// which writes the phone's PhaseStyle table from the same data. Text shades are
// a PAIR pulling away from their own background (frontend-design §8.1–8.2).
/** Colour and fallback label by phase KIND. A week's display name is its
 * philosophy's own phase name (`weekPhaseLabel`); `label` is only the fallback
 * for programs stored before tracks. */
export const PHASE_COLORS: Record<PhaseKind, PhaseColor> = PHASE_DISPLAY
