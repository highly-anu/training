import { create } from 'zustand'

/**
 * What the athlete typed into the describe form, kept while a build runs so
 * that "Try again" after a failed build starts from their words, not from a
 * blank page. In memory only: a description is not a setting.
 */
interface MethodDraft {
  description: string
  pastedText: string
  webSearch: boolean
  keep: (draft: { description: string; pastedText: string; webSearch: boolean }) => void
  clear: () => void
}

export const useMethodDraft = create<MethodDraft>()((set) => ({
  description: '',
  pastedText: '',
  webSearch: false,
  keep: (draft) => set(draft),
  clear: () => set({ description: '', pastedText: '', webSearch: false }),
}))
