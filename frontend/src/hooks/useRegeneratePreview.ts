import { useNavigate } from 'react-router-dom'
import { isInfeasible, useGenerateDraft, type GenerateParams } from '@/api/programs'
import type { ConstraintChangeEntry, GeneratedProgram } from '@/api/types'
import { spliceRegenerated } from '@/lib/programSource'
import { usePreviewStore } from '@/store/previewStore'
import { useProgramStore } from '@/store/programStore'

/**
 * The regenerated tail as it will be saved: the days already behind the
 * athlete in its first week are the program's own (`spliceRegenerated`), so
 * the preview shows what Apply keeps, not what the generator wrote for them.
 */
export function regeneratePreviewDraft(tail: GeneratedProgram, params: GenerateParams): GeneratedProgram {
  const { currentProgram, programStartDate } = useProgramStore.getState()
  if (!currentProgram || isInfeasible(tail) || params.numWeeks === undefined) return tail
  const keepCount = Math.max(0, currentProgram.weeks.length - params.numWeeks)
  const weeks = spliceRegenerated(currentProgram.weeks, tail.weeks, keepCount, programStartDate, params.keepBefore)
  return { ...tail, weeks: weeks.slice(keepCount) }
}

/**
 * Every regenerate of the active program — "From tomorrow onwards", the
 * injury sheet, a profile change — opens Program ▸ Preview first, and nothing
 * is saved until the athlete confirms Apply there. "From tomorrow" used to
 * save the moment the tail came back; on 2026-10-27 it rebuilt a program two
 * weeks in from week 1 and nobody saw it coming.
 *
 * `open(params, startIdx)` generates the tail and opens it; with `tail` (a
 * comparison already built it) it opens that one.
 */
export function useRegeneratePreview() {
  const navigate = useNavigate()
  const generate = useGenerateDraft()

  function show(params: GenerateParams, startIdx: number, tail: GeneratedProgram,
                changes: ConstraintChangeEntry[]) {
    usePreviewStore.getState().open('regenerate', params, regeneratePreviewDraft(tail, params),
                                    { startIdx, changes })
    navigate('/program/preview?mode=regenerate&tab=calendar')
  }

  return {
    open: (params: GenerateParams, startIdx: number, tail?: GeneratedProgram | null,
           changes: ConstraintChangeEntry[] = []) => {
      if (tail) {
        show(params, startIdx, tail, changes)
        return
      }
      generate.mutate(params, { onSuccess: (t) => show(params, startIdx, t, []) })
    },
    isPending: generate.isPending,
    error: generate.error as Error | null,
  }
}
