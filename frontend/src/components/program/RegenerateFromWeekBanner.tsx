import { useMemo, useState } from 'react'
import { differenceInCalendarDays, parseISO } from 'date-fns'
import { RefreshCw } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { useProgramStore } from '@/store/programStore'
import { useProfileStore } from '@/store/profileStore'
import { useRegenerateFromWeek } from '@/api/programs'
import { constraintDifferences, mergedConstraints } from '@/lib/programConstraintsDiff'

/**
 * "Your program was built for different settings." Shown on Profile when
 * the profile's level, equipment, schedule or injuries no longer match the
 * active program's constraints; one click regenerates from the current week
 * with the new ones and keeps the weeks already behind the athlete. The
 * same path the Program settings sheet uses for "from tomorrow onwards".
 */
export function RegenerateFromWeekBanner() {
  const program = useProgramStore((s) => s.currentProgram)
  const programStartDate = useProgramStore((s) => s.programStartDate)
  const sourceGoalIds = useProgramStore((s) => s.sourceGoalIds)
  const sourceGoalWeights = useProgramStore((s) => s.sourceGoalWeights)
  const trainingLevel = useProfileStore((s) => s.trainingLevel)
  const equipment = useProfileStore((s) => s.equipment)
  const injuryFlags = useProfileStore((s) => s.injuryFlags)
  const customInjuryFlags = useProfileStore((s) => s.customInjuryFlags)
  const weeklySchedule = useProfileStore((s) => s.weeklySchedule)
  const regenerate = useRegenerateFromWeek()
  const [done, setDone] = useState(false)

  const profile = useMemo(() => ({ trainingLevel, equipment, injuryFlags, weeklySchedule }),
                          [trainingLevel, equipment, injuryFlags, weeklySchedule])
  const diffs = useMemo(() => constraintDifferences(program?.constraints, profile), [program, profile])

  const startIdx = useMemo(() => {
    if (!program || !programStartDate) return 0
    const days = differenceInCalendarDays(new Date(), parseISO(programStartDate))
    return Math.max(0, Math.min(Math.floor(days / 7), program.weeks.length - 1))
  }, [program, programStartDate])

  if (!program || diffs.length === 0 || done) return null
  const remaining = program.weeks.length - startIdx
  const ids = sourceGoalIds.filter((id) => id !== '_blended')

  function run() {
    if (!program) return
    const week = program.weeks[startIdx]
    regenerate.mutate(
      {
        philosophyId: ids.length === 1 ? ids[0] : undefined,
        philosophyIds: ids.length > 1 ? ids : undefined,
        philosophyWeights: ids.length > 1 ? sourceGoalWeights : undefined,
        constraints: mergedConstraints(program.constraints, profile, week?.week_in_phase ?? null),
        numWeeks: remaining,
        customInjuryFlags,
      },
      { onSuccess: () => setDone(true) }
    )
  }

  return (
    <div className="mx-6 mt-4 rounded-lg border border-primary/30 bg-primary/5 p-4 space-y-3">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="text-sm font-semibold">Your program was built for different settings</p>
          <ul className="mt-1 text-xs text-muted-foreground space-y-0.5">
            {diffs.map((d) => (
              <li key={d.field}>
                <span className="font-medium text-foreground">{d.label}:</span> {d.program} → {d.profile}
              </li>
            ))}
          </ul>
        </div>
        <Button size="sm" onClick={run} disabled={regenerate.isPending || remaining <= 0 || ids.length === 0}>
          <RefreshCw className={regenerate.isPending ? 'size-3.5 animate-spin' : 'size-3.5'} />
          {regenerate.isPending ? 'Regenerating…' : `Regenerate from week ${startIdx + 1}`}
        </Button>
      </div>
      <p className="text-[11px] text-muted-foreground">
        Keeps the {startIdx} week{startIdx === 1 ? '' : 's'} already behind you and rebuilds the remaining {remaining} with these settings. The current plan stays in Program ▸ History.
      </p>
      {regenerate.isError && (
        <p className="text-xs text-red-700 dark:text-red-300">
          {regenerate.error instanceof Error ? regenerate.error.message : 'Could not regenerate'}
        </p>
      )}
    </div>
  )
}
