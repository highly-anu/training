import { create } from 'zustand'
import type { GenerateParams } from '@/api/programs'
import type { ConstraintChangeEntry, ExerciseAssignment, GeneratedProgram, Session } from '@/api/types'
import { withExerciseReplaced, withSessionReplaced } from '@/lib/programEdits'

/**
 * A generated program the athlete has not started yet (Program ▸ Preview).
 *
 * `new` is a program from the builder, committed with "Start this program";
 * `regenerate` is the rest of the active program rebuilt for the profile's
 * new settings, applied from `startIdx` on. Held in memory only: a program
 * is ~1 MB, and a reload regenerates from the builder (persisted) instead.
 */
export type PreviewMode = 'new' | 'regenerate'

export interface RegeneratePreview {
  /** The week index of the active program the tail starts at. */
  startIdx: number
  /** The sessions the change moves, from POST /programs/constraint-change. */
  changes: ConstraintChangeEntry[]
}

interface PreviewStore {
  mode: PreviewMode
  /** The request that generated the draft; the preview re-asks with edited constraints. */
  params: GenerateParams | null
  draft: GeneratedProgram | null
  /** Swaps and replaced sessions made on this draft (a re-preview discards them). */
  edits: number
  regenerate: RegeneratePreview | null
  open: (mode: PreviewMode, params: GenerateParams, draft: GeneratedProgram, regenerate?: RegeneratePreview) => void
  /** A re-preview: a new draft for new params, and no edits. */
  setDraft: (params: GenerateParams, draft: GeneratedProgram) => void
  replaceSession: (weekIndex: number, day: string, sessionIndex: number, session: Session) => void
  replaceExercise: (weekIndex: number, day: string, sessionIndex: number, exerciseIndex: number,
                    assignment: ExerciseAssignment) => void
  clear: () => void
}

const EMPTY = { mode: 'new' as PreviewMode, params: null, draft: null, edits: 0, regenerate: null }

export const usePreviewStore = create<PreviewStore>()((set) => ({
  ...EMPTY,
  open: (mode, params, draft, regenerate) => set({ mode, params, draft, edits: 0, regenerate: regenerate ?? null }),
  // The constraint-change diff described the first draft; a re-preview has its own.
  setDraft: (params, draft) => set((s) => ({
    params, draft, edits: 0,
    regenerate: s.regenerate ? { ...s.regenerate, changes: [] } : null,
  })),
  // A replaced session can hold back another number of slots, so the
  // server's `held_back` no longer counts this draft; heldBackSummary counts it.
  replaceSession: (weekIndex, day, sessionIndex, session) => set((s) => s.draft
    ? { draft: { ...withSessionReplaced(s.draft, weekIndex, day, sessionIndex, session), held_back: undefined },
        edits: s.edits + 1 }
    : {}),
  replaceExercise: (weekIndex, day, sessionIndex, exerciseIndex, assignment) => set((s) => s.draft
    ? { draft: withExerciseReplaced(s.draft, weekIndex, day, sessionIndex, exerciseIndex, assignment),
        edits: s.edits + 1 }
    : {}),
  clear: () => set(EMPTY),
}))
