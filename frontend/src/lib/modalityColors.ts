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
const COMMONS: Record<string, ModalityColor> = Object.fromEntries(
  Object.entries(MODALITY_DISPLAY).map(([id, { hex, bg, text, border, label }]) => [id, { hex, bg, text, border, label }]),
)

// A package may bring modalities of its own (its vocabulary.yaml; roadmap
// 20.6), which no build of the web knows. The server sends each with its
// `display` (GET /api/modalities); `registerModalities` keeps them here, and a
// lookup of an id that is neither the commons' nor registered answers a
// neutral style and the id in words — never undefined, so a session of a
// modality this build has not met still draws.
const registered: Record<string, ModalityColor> = {}
let version = 0

/** Counts each time a served modality was learned or changed: a page keyed on it draws again. */
export function modalityVocabularyVersion(): number {
  return version
}

function neutral(id: string): ModalityColor {
  return {
    hex: '#94a3b8',
    bg: 'bg-slate-500/15',
    text: 'text-slate-700 dark:text-slate-300',
    border: 'border-slate-500/40',
    label: id.replace(/_/g, ' '),
  }
}

/** What the server says of a modality the build does not know. */
export interface ServedModality {
  id: string
  name?: string
  display?: { label?: string; color?: string; tint?: string }
}

/**
 * Keep the display of every served modality the build does not carry.
 * Its tint classes are those of the commons modality of the same colour
 * family (the only ones the stylesheet holds; the server refuses a tint the
 * commons do not use). Returns whether anything new was learned.
 */
export function registerModalities(served: ServedModality[] | undefined): boolean {
  let learned = false
  for (const m of served ?? []) {
    if (!m?.id || m.id in COMMONS) continue
    const family = m.display?.tint ? `bg-${m.display.tint}-500/15` : null
    const like = Object.values(COMMONS).find((c) => c.bg === family) ?? neutral(m.id)
    const next: ModalityColor = {
      hex: m.display?.color ?? like.hex,
      bg: like.bg,
      text: like.text,
      border: like.border,
      label: m.display?.label ?? m.name ?? neutral(m.id).label,
    }
    const had = registered[m.id]
    if (!had || had.hex !== next.hex || had.label !== next.label || had.bg !== next.bg) {
      registered[m.id] = next
      learned = true
      version += 1
    }
  }
  return learned
}

export const MODALITY_COLORS: Record<ModalityId, ModalityColor> = new Proxy(COMMONS, {
  get(target, key, receiver) {
    if (typeof key !== 'string' || key in target) return Reflect.get(target, key, receiver)
    return registered[key] ?? neutral(key)
  },
}) as Record<ModalityId, ModalityColor>

/** A modality's hex and label by an id the server sent as a plain string;
 *  slate and the id in words for one the map does not know. */
export function modalityHex(id: string | null | undefined): string {
  return (id && MODALITY_COLORS[id as ModalityId]?.hex) || '#94a3b8'
}

export function modalityLabel(id: string | null | undefined): string {
  return id ? MODALITY_COLORS[id as ModalityId]?.label ?? id.replace(/_/g, ' ') : ''
}
