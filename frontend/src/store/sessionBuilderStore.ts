import { create } from 'zustand'
import { persist } from 'zustand/middleware'
import { emptyDraft, type DraftSession } from '@/lib/sessionBuilder'

/**
 * The manual session builder's draft (docs/roadmap.md item 24), kept across a
 * reload: a session half built is not lost. Every edit is a pure function of
 * `lib/sessionBuilder`, applied through `edit`.
 */
interface SessionBuilderState {
  draft: DraftSession
  /** Whether the draft differs from what was last saved or opened. */
  dirty: boolean
  edit: (change: (draft: DraftSession) => DraftSession) => void
  open: (draft: DraftSession) => void
  saved: (draft: DraftSession) => void
  reset: () => void
}

export const useSessionBuilderStore = create<SessionBuilderState>()(
  persist(
    (set) => ({
      draft: emptyDraft(),
      dirty: false,
      edit: (change) => set((s) => {
        const draft = change(s.draft)
        return draft === s.draft ? s : { draft, dirty: true }
      }),
      open: (draft) => set({ draft, dirty: false }),
      saved: (draft) => set({ draft, dirty: false }),
      reset: () => set({ draft: emptyDraft(), dirty: false }),
    }),
    { name: 'training-session-builder-v1', version: 1 },
  ),
)
