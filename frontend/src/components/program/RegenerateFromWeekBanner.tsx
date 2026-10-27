import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQueryClient } from '@tanstack/react-query'
import { differenceInCalendarDays, format, parseISO } from 'date-fns'
import { Check, Loader2, RefreshCw, ScanEye } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { useProgramStore } from '@/store/programStore'
import { useProfileStore } from '@/store/profileStore'
import { usePreviewStore } from '@/store/previewStore'
import {
  adoptProgramConstraints, commitRegeneratedTail, isInfeasible, useConstraintChangeCheck, useRegenerateFromWeek,
  type GenerateParams,
} from '@/api/programs'
import { constraintDifferences, mergedConstraints } from '@/lib/programConstraintsDiff'
import { regenerateSource, tailResume } from '@/lib/programSource'
import { useDebounce } from '@/hooks/useDebounce'

/**
 * Shown on Profile when the profile's level, equipment, schedule or injuries
 * no longer match the active program's constraints — but only when the
 * difference changes the program.
 *
 * It used to offer a regenerate for any difference: adding a kettlebell no
 * session uses asked to rebuild the plan. Now the server builds the rest of
 * the program both ways (POST /programs/constraint-change). A change that
 * moves nothing is recorded on the program (PATCH /user/program/constraints)
 * and the offer never appears; one that does says how many sessions it moves,
 * and opens them in the preview or applies them from the current week,
 * keeping the weeks and days already behind the athlete.
 */
export function RegenerateFromWeekBanner() {
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const program = useProgramStore((s) => s.currentProgram)
  const programStartDate = useProgramStore((s) => s.programStartDate)
  const revision = useProgramStore((s) => s.revision)
  const sourceGoalIds = useProgramStore((s) => s.sourceGoalIds)
  const sourceGoalWeights = useProgramStore((s) => s.sourceGoalWeights)
  const trainingLevel = useProfileStore((s) => s.trainingLevel)
  const equipment = useProfileStore((s) => s.equipment)
  const injuryFlags = useProfileStore((s) => s.injuryFlags)
  const customInjuryFlags = useProfileStore((s) => s.customInjuryFlags)
  const weeklySchedule = useProfileStore((s) => s.weeklySchedule)
  const regenerate = useRegenerateFromWeek()
  // What the last difference came to, said once it is gone: the banner used
  // to vanish the moment an apply removed the difference it was about.
  const [outcome, setOutcome] = useState<{ applied: number } | { adopted: true } | null>(null)

  const profile = useMemo(() => ({ trainingLevel, equipment, injuryFlags, weeklySchedule }),
                          [trainingLevel, equipment, injuryFlags, weeklySchedule])
  const diffs = useMemo(() => constraintDifferences(program?.constraints, profile), [program, profile])

  const startIdx = useMemo(() => {
    if (!program || !programStartDate) return 0
    const days = differenceInCalendarDays(new Date(), parseISO(programStartDate))
    return Math.max(0, Math.min(Math.floor(days / 7), program.weeks.length - 1))
  }, [program, programStartDate])
  const remaining = program ? program.weeks.length - startIdx : 0
  const ids = sourceGoalIds.filter((id) => id !== '_blended')

  // The regenerate this profile asks for, and the same request with the
  // program's own constraints — the two the server compares.
  const request = useMemo(() => {
    if (!program || diffs.length === 0 || remaining <= 0) return null
    const source = regenerateSource(ids, sourceGoalWeights, program)
    if (!source.philosophyId && !source.philosophyIds && !source.lanes) return null
    const resume = tailResume(program, startIdx)
    const params: GenerateParams = {
      ...source,
      trackId: resume.trackId,
      ...(resume.lanes ? { lanes: resume.lanes } : {}),
      startPhaseId: resume.startPhaseId,
      constraints: mergedConstraints(resume.constraints, profile),
      numWeeks: remaining,
      weekInProgram: startIdx + 1,
      customInjuryFlags,
      // The days already behind the athlete this week stay as they are.
      keepBefore: format(new Date(), 'yyyy-MM-dd'),
    }
    return { params, baseline: resume.constraints }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [program, diffs.length, remaining, startIdx, profile, customInjuryFlags, sourceGoalWeights, sourceGoalIds])

  // Toggling several items in a row asks once, after the last.
  const requestKey = useDebounce(request ? JSON.stringify(request) : null, 1500)
  const settled = request && requestKey === JSON.stringify(request) ? request : null
  const check = useConstraintChangeCheck(settled?.params ?? null, settled?.baseline ?? null, revision)

  // Unaffected: the program is what the new settings would build, so it now
  // says it was built for them. Once per answer.
  // Keyed with the revision: a stale adopt reloads the program, and its new
  // revision checks and adopts again.
  const adopted = useRef<string | null>(null)
  const [adoptFailed, setAdoptFailed] = useState(false)
  const adoptKey = `${revision}|${requestKey}`
  const adopt = useCallback(() => {
    if (!settled) return
    const c = settled.params.constraints
    setAdoptFailed(false)
    void adoptProgramConstraints(
      { equipment: c.equipment, training_level: c.training_level, injury_flags: c.injury_flags,
        ...(c.days_per_week ? { days_per_week: c.days_per_week } : {}) },
      customInjuryFlags,
    ).then((result) => {
      if (result === 'adopted') setOutcome({ adopted: true })
      // Never dropped silently: the banner used to go blank and never retry.
      else if (result === 'failed') setAdoptFailed(true)
    })
  }, [settled, customInjuryFlags])
  useEffect(() => {
    if (!settled || check.data?.affected !== false || check.data?.comparable === false
        || adopted.current === adoptKey) return
    adopted.current = adoptKey
    adopt()
  }, [check.data, settled, adoptKey, adopt])

  // A new difference starts over (adjusted during render, not in an effect).
  const [prevDiffCount, setPrevDiffCount] = useState(diffs.length)
  if (diffs.length !== prevDiffCount) {
    setPrevDiffCount(diffs.length)
    if (diffs.length > 0) setOutcome(null)
  }

  if (!program) return null
  if (diffs.length === 0) {
    if (!outcome) return null
    return (
      <p className="mx-6 mt-4 inline-flex items-center gap-1.5 text-xs text-muted-foreground" aria-live="polite">
        <Check className="size-3.5" aria-hidden="true" />
        {'applied' in outcome
          ? `Rebuilt ${outcome.applied} week${outcome.applied === 1 ? '' : 's'} with these settings. The previous plan is in Program ▸ History.`
          : 'Your program doesn’t change with these settings.'}
      </p>
    )
  }
  if (!request) return null

  const result = check.data
  if (!check.isError && (!result || check.isFetching)) {
    return (
      <p className="mx-6 mt-4 inline-flex items-center gap-1.5 text-xs text-muted-foreground" aria-live="polite">
        <Loader2 className="size-3.5 animate-spin" aria-hidden="true" /> Checking whether this changes your program…
      </p>
    )
  }
  if (result && !result.affected) {
    return adoptFailed ? (
      <div className="mx-6 mt-4 flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
        <span>Your program doesn&apos;t change with these settings, but recording them on it failed.</span>
        <Button size="sm" variant="outline" className="h-7 text-xs" onClick={adopt}>Try again</Button>
      </div>
    ) : null
  }

  const tail = result?.program
  const refused = !!tail && isInfeasible(tail)

  function preview() {
    if (!tail || !request) return
    usePreviewStore.getState().open('regenerate', request.params, tail,
                                    { startIdx, changes: result?.changes ?? [] })
    navigate('/program/preview?mode=regenerate&tab=calendar')
  }

  function applyNow() {
    if (!request) return
    if (tail && !refused) {
      if (commitRegeneratedTail(queryClient, tail, request.params)) setOutcome({ applied: remaining })
      return
    }
    // The check failed: regenerate as before, without knowing what it moves.
    regenerate.mutate(request.params, { onSuccess: () => setOutcome({ applied: remaining }) })
  }

  const changed = result?.sessions.changed ?? 0
  const fromWeek = result?.first_week_number

  return (
    <div className="mx-6 mt-4 rounded-lg border border-primary/30 bg-primary/5 p-4 space-y-3">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="text-sm font-semibold">
            {check.isError || result?.comparable === false
              ? 'Your program was built for different settings'
              : refused
                ? "These settings can't build the rest of your program"
                : `These settings change ${changed} session${changed === 1 ? '' : 's'}${fromWeek ? ` from week ${fromWeek}` : ''}`}
          </p>
          <ul className="mt-1 text-xs text-muted-foreground space-y-0.5">
            {diffs.map((d) => (
              <li key={d.field}>
                <span className="font-medium text-foreground">{d.label}:</span> {d.program} → {d.profile}
              </li>
            ))}
          </ul>
          {refused && tail?.validation?.errors?.[0] && (
            <p className="mt-1 text-xs text-muted-foreground">{tail.validation.errors[0].message}</p>
          )}
        </div>
        <div className="flex flex-wrap items-center gap-2">
          {tail && (
            <Button size="sm" variant={refused ? 'default' : 'outline'} onClick={preview}>
              <ScanEye className="size-3.5" aria-hidden="true" /> {refused ? 'See why' : 'Preview changes'}
            </Button>
          )}
          {!refused && (
            <Button size="sm" onClick={applyNow} disabled={regenerate.isPending || ids.length === 0}>
              <RefreshCw className={regenerate.isPending ? 'size-3.5 animate-spin' : 'size-3.5'} />
              {regenerate.isPending ? 'Regenerating…' : `Apply from week ${startIdx + 1}`}
            </Button>
          )}
        </div>
      </div>
      <p className="text-[11px] text-muted-foreground">
        {startIdx > 0
          ? `Keeps the ${startIdx} week${startIdx === 1 ? '' : 's'} already behind you and rebuilds the remaining ${remaining} with these settings.`
          : `Rebuilds the program's ${remaining} weeks with these settings; the days already behind you this week keep their sessions.`}
        {' '}The current plan stays in Program ▸ History.
      </p>
      {regenerate.isError && (
        <p className="text-xs text-red-700 dark:text-red-300">
          {regenerate.error instanceof Error ? regenerate.error.message : 'Could not regenerate'}
        </p>
      )}
    </div>
  )
}
