import { useEffect, useState } from 'react'
import { ArrowLeftRight } from 'lucide-react'
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetDescription } from '@/components/ui/sheet'
import { Button } from '@/components/ui/button'
import { LoadingCard } from '@/components/shared/LoadingCard'
import { useSubstituteExercise } from '@/api/programs'
import { useProgramStore } from '@/store/programStore'
import { formatLoad } from '@/lib/formatLoad'
import type { ExerciseAlternative, GeneratedProgram, WeekData } from '@/api/types'

interface SwapExerciseSheetProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  program: GeneratedProgram
  weekData: WeekData
  weekIndex: number
  day: string
  sessionIndex: number
  exerciseIndex: number
}

/**
 * Swap one exercise for a ranked alternative that fits the same slot. The
 * server applies the selector's rules; picking one replaces the assignment
 * in place and saves through the usual revision-checked path.
 */
export function SwapExerciseSheet({
  open, onOpenChange, program, weekData, weekIndex, day, sessionIndex, exerciseIndex,
}: SwapExerciseSheetProps) {
  const session = weekData.schedule[day]?.[sessionIndex]
  const assignment = session?.exercises[exerciseIndex]
  const sourceGoalIds = useProgramStore((s) => s.sourceGoalIds)
  const replaceExercise = useProgramStore((s) => s.replaceExercise)
  const substitute = useSubstituteExercise()
  const [alternatives, setAlternatives] = useState<ExerciseAlternative[] | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!open || !session?.archetype || !assignment?.exercise) return
    setAlternatives(null)
    setError(null)
    substitute.mutate(
      {
        archetypeId: session.archetype.id,
        slotRole: assignment.slot_role ?? '',
        exerciseId: assignment.exercise.id,
        modality: session.modality,
        constraints: program.constraints,
        philosophyIds: sourceGoalIds.filter((id) => id !== '_blended'),
        phase: weekData.phase,
        weekInPhase: weekData.week_in_phase ?? 1,
        isDeload: !!weekData.is_deload,
        exclude: session.exercises.map((e) => e.exercise?.id).filter((id): id is string => !!id),
      },
      {
        onSuccess: (res) => setAlternatives(res.alternatives),
        onError: (err) => setError(err instanceof Error ? err.message : 'No alternatives'),
      }
    )
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, weekIndex, day, sessionIndex, exerciseIndex])

  if (!session || !assignment?.exercise) return null

  function pick(alt: ExerciseAlternative) {
    replaceExercise(weekIndex, day, sessionIndex, exerciseIndex, alt.assignment)
    onOpenChange(false)
  }

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent className="w-full sm:max-w-md overflow-y-auto">
        <SheetHeader>
          <SheetTitle>Swap {assignment.exercise.name}</SheetTitle>
          <SheetDescription>
            Alternatives that fit this slot under the program's methodology, your equipment and injury flags.
            The load is worked out for week {weekData.week_number}.
          </SheetDescription>
        </SheetHeader>

        <div className="mt-4 space-y-2">
          {substitute.isPending && <LoadingCard />}
          {error && <p className="text-sm text-muted-foreground">{error}</p>}
          {alternatives?.map((alt) => {
            const ex = alt.assignment.exercise
            if (!ex) return null
            const loadStr = formatLoad(alt.assignment.load)
            return (
              <button
                key={ex.id}
                type="button"
                onClick={() => pick(alt)}
                className="w-full rounded-lg border border-border bg-card px-4 py-3 text-left transition-colors hover:border-primary/40 hover:bg-card/80"
              >
                <div className="flex items-center justify-between gap-3">
                  <p className="text-sm font-medium">{ex.name}</p>
                  <span className="shrink-0 inline-flex items-center gap-1 text-[11px] text-primary">
                    <ArrowLeftRight className="size-3" aria-hidden="true" /> Use this
                  </span>
                </div>
                {loadStr && <p className="mt-0.5 text-xs font-mono text-primary">{loadStr}</p>}
                {alt.reasons.length > 0 && (
                  <p className="mt-1 text-[11px] text-muted-foreground">{alt.reasons.join(' · ')}</p>
                )}
              </button>
            )
          })}
        </div>

        <div className="mt-4">
          <Button variant="ghost" size="sm" className="w-full text-muted-foreground" onClick={() => onOpenChange(false)}>
            Keep {assignment.exercise.name}
          </Button>
        </div>
      </SheetContent>
    </Sheet>
  )
}
