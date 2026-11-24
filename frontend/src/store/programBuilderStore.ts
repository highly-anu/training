import { create } from 'zustand'
import { persist } from 'zustand/middleware'
import { emptyTrack, type DraftTrack } from '@/lib/programBuilder'

/**
 * The manual program builder's draft (docs/roadmap.md item 24.4), kept across
 * a reload. Every edit is a pure function of `lib/programBuilder`.
 */
interface ProgramBuilderState {
  draft: DraftTrack
  /** The phase whose weeks are on screen (its uid); the first when unknown. */
  phaseUid: string | null
  dirty: boolean
  edit: (change: (draft: DraftTrack) => DraftTrack) => void
  selectPhase: (uid: string) => void
  open: (draft: DraftTrack) => void
  reset: () => void
}

export const useProgramBuilderStore = create<ProgramBuilderState>()(
  persist(
    (set) => ({
      draft: emptyTrack(),
      phaseUid: null,
      dirty: false,
      edit: (change) => set((s) => {
        const draft = change(s.draft)
        return draft === s.draft ? s : { draft, dirty: true }
      }),
      selectPhase: (phaseUid) => set({ phaseUid }),
      open: (draft) => set({ draft, phaseUid: draft.phases[0]?.uid ?? null, dirty: false }),
      reset: () => set({ draft: emptyTrack(), phaseUid: null, dirty: false }),
    }),
    { name: 'training-program-builder-v1', version: 1 },
  ),
)
