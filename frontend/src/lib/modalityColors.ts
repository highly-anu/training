import type { ModalityId } from '@/api/types'
import { MODALITY_DISPLAY } from '@/lib/gen/clientVocab'

export interface ModalityColor {
  hex: string
  bg: string
  text: string
  border: string
  label: string
}

// Each modality's label, colour and tint classes come from its file in
// data/commons/modalities (`display`), through tools/gen_client_vocab.py, which
// writes the phone's, the widgets' and the watch's tables from the same data.
// Text shades are a PAIR pulling away from their own background: -700 or -800
// for light mode (on a /15 tint over white), -300 for dark. Nothing lighter
// than -600 clears WCAG AA 4.5:1 on the light end — these render at
// text-[10px]/text-xs. See docs/frontend-design.md §8.1.
export const MODALITY_COLORS: Record<ModalityId, ModalityColor> = Object.fromEntries(
  Object.entries(MODALITY_DISPLAY).map(([id, { hex, bg, text, border, label }]) => [id, { hex, bg, text, border, label }]),
) as Record<ModalityId, ModalityColor>

/** A modality's hex and label by an id the server sent as a plain string;
 *  slate and the id in words for one the map does not know. */
export function modalityHex(id: string | null | undefined): string {
  return (id && MODALITY_COLORS[id as ModalityId]?.hex) || '#94a3b8'
}

export function modalityLabel(id: string | null | undefined): string {
  return id ? MODALITY_COLORS[id as ModalityId]?.label ?? id.replace(/_/g, ' ') : ''
}
