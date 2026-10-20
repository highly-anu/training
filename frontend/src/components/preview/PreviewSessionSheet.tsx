import { useState } from 'react'
import { ArrowLeftRight, CircleSlash, RefreshCw } from 'lucide-react'
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from '@/components/ui/sheet'
import { Button } from '@/components/ui/button'
import { ModalityBadge } from '@/components/shared/ModalityBadge'
import { TestBadge } from '@/components/standards/TestBadge'
import { SwapExerciseSheet } from '@/components/session/SwapExerciseSheet'
import { ReplaceSessionSheet } from '@/components/session/ReplaceSessionSheet'
import { useHeldBackNames } from '@/hooks/useHeldBackNames'
import { emptySlotText, idLabel, sessionNotes } from '@/lib/heldBack'
import { formatLoad } from '@/lib/formatLoad'
import { usePreviewStore } from '@/store/previewStore'
import type { GeneratedProgram } from '@/api/types'

export interface PreviewSessionTarget {
  weekIndex: number
  day: string
  sessionIndex: number
}

interface PreviewSessionSheetProps {
  program: GeneratedProgram
  target: PreviewSessionTarget | null
  onClose: () => void
  philosophyIds: string[]
}

/**
 * One session of the preview's draft: its exercises with their loads, what
 * the athlete's constraints left empty and why, and swaps that edit the
 * draft only (the swap and replace sheets with their draft overrides).
 */
export function PreviewSessionSheet({ program, target, onClose, philosophyIds }: PreviewSessionSheetProps) {
  const names = useHeldBackNames()
  const replaceExercise = usePreviewStore((s) => s.replaceExercise)
  const replaceSession = usePreviewStore((s) => s.replaceSession)
  const [swapIndex, setSwapIndex] = useState<number | null>(null)
  const [replacing, setReplacing] = useState(false)

  const weekData = target ? program.weeks[target.weekIndex] : undefined
  const session = target && weekData ? weekData.schedule[target.day]?.[target.sessionIndex] : undefined
  if (!target || !weekData || !session) return null

  const notes = sessionNotes(session)

  return (
    <>
      <Sheet open onOpenChange={(open) => !open && onClose()}>
        <SheetContent className="w-full sm:max-w-md overflow-y-auto">
          <SheetHeader>
            <SheetTitle>{session.archetype?.name ?? idLabel(session.modality)}</SheetTitle>
            <SheetDescription>
              Week {weekData.week_number} · {target.day}
              {session.archetype?.duration_estimate_minutes
                ? ` · ${session.archetype.duration_estimate_minutes} min` : ''}
            </SheetDescription>
            <div className="flex flex-wrap items-center gap-1.5 pt-1">
              <ModalityBadge modality={session.modality} size="sm" />
              {session.test && <TestBadge test={session.test} />}
            </div>
          </SheetHeader>

          {notes.length > 0 && (
            <ul className="mt-4 space-y-1 rounded-md border border-amber-500/30 bg-amber-500/5 p-3 text-xs">
              {notes.map((n) => <li key={n}>{n}</li>)}
            </ul>
          )}

          <ul className="mt-4 space-y-2">
            {session.exercises.map((ea, i) => {
              if (ea.meta || ea.skip_exercise) return null
              const empty = emptySlotText(ea, names)
              const load = ea.exercise ? formatLoad(ea.load) : ''
              return (
                <li key={i} className="rounded-lg border bg-card px-3 py-2.5">
                  <div className="flex items-start justify-between gap-2">
                    <div className="min-w-0">
                      <p className="text-sm font-medium">
                        {ea.exercise?.name ?? <span className="text-muted-foreground">{idLabel(ea.slot_role ?? 'slot')}</span>}
                      </p>
                      {load && <p className="mt-0.5 text-xs font-mono text-primary">{load}</p>}
                      {ea.substituted_for && (
                        <p className="mt-0.5 text-[11px] text-muted-foreground">
                          In place of {names.exercise?.(ea.substituted_for) ?? idLabel(ea.substituted_for)}
                          {ea.substituted_by_flag && ` (${names.flag?.(ea.substituted_by_flag) ?? idLabel(ea.substituted_by_flag)})`}
                        </p>
                      )}
                      {empty && (
                        <p className="mt-0.5 inline-flex items-start gap-1 text-[11px] text-amber-700 dark:text-amber-300">
                          <CircleSlash className="mt-0.5 size-3 shrink-0" aria-hidden="true" />
                          {empty}
                        </p>
                      )}
                    </div>
                    {ea.exercise && session.archetype && (
                      <Button variant="ghost" size="sm" className="h-7 shrink-0 gap-1 px-2 text-xs"
                        onClick={() => setSwapIndex(i)}>
                        <ArrowLeftRight className="size-3" aria-hidden="true" /> Swap
                      </Button>
                    )}
                  </div>
                </li>
              )
            })}
          </ul>

          <Button variant="outline" size="sm" className="mt-4 w-full gap-1.5" onClick={() => setReplacing(true)}>
            <RefreshCw className="size-3.5" aria-hidden="true" /> Replace this session
          </Button>
          <p className="mt-2 text-[11px] text-muted-foreground">
            Changes here edit this preview only; nothing is saved until you start the program.
          </p>
        </SheetContent>
      </Sheet>

      {swapIndex !== null && (
        <SwapExerciseSheet
          open
          onOpenChange={(open) => !open && setSwapIndex(null)}
          program={program}
          weekData={weekData}
          weekIndex={target.weekIndex}
          day={target.day}
          sessionIndex={target.sessionIndex}
          exerciseIndex={swapIndex}
          philosophyIds={philosophyIds}
          onPick={(assignment) => replaceExercise(target.weekIndex, target.day, target.sessionIndex, swapIndex, assignment)}
        />
      )}
      {replacing && (
        <ReplaceSessionSheet
          open
          onOpenChange={(open) => !open && setReplacing(false)}
          session={session}
          weekIndex={target.weekIndex}
          weekData={weekData}
          day={target.day}
          sessionIndex={target.sessionIndex}
          program={program}
          onReplace={(s) => replaceSession(target.weekIndex, target.day, target.sessionIndex, s)}
        />
      )}
    </>
  )
}
