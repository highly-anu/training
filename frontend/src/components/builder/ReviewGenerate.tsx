import { useMemo } from 'react'
import { Loader2, Wand2 } from 'lucide-react'
import { useNavigate } from 'react-router-dom'
import { motion } from 'framer-motion'
import { Button } from '@/components/ui/button'
import { Separator } from '@/components/ui/separator'
import { ValidationAlert } from '@/components/shared/ValidationAlert'
import { FeasibilityPanel } from './FeasibilityPanel'
import { ScheduleGuidance } from './ScheduleGuidance'
import { useBuilderStore } from '@/store/builderStore'
import { useProfileStore } from '@/store/profileStore'
import { useFeasibility } from '@/hooks/useFeasibility'
import { useGenerateProgram } from '@/api/programs'
import { usePhilosophies } from '@/api/philosophies'
import { useFrameworks } from '@/api/frameworks'
import { scheduleToConstraints } from '@/lib/scheduleToConstraints'
import type { AthleteConstraints } from '@/api/types'

export function ReviewGenerate() {
  const navigate = useNavigate()
  const {
    selectedGoalIds,
    goalWeights,
    sourceMode,
    selectedPhilosophyIds,
    philosophyWeights,
    constraints,
    eventDate,
    startDate,
    selectedFrameworkId,
    priorityOverrides,
    numWeeks,
  } = useBuilderStore()
  const setActiveGoalId = useProfileStore((s) => s.setActiveGoalId)
  const { customInjuryFlags, weeklySchedule } = useProfileStore()
  const { mutate, isPending, error, data } = useGenerateProgram()
  const { data: philosophies } = usePhilosophies()
  const { data: frameworks } = useFrameworks()

  const feasibilitySignals = useFeasibility()
  const hasFeasibilityErrors = feasibilitySignals.some((s) => s.severity === 'error')
  const hasErrors = data?.validation && !data.validation.feasible

  // Always derive schedule-based constraints from the saved weekly schedule.
  // This overrides stale persisted values in the builder store so the API call
  // and the Configuration Summary always reflect the actual training days.
  const scheduleOverride = weeklySchedule ? scheduleToConstraints(weeklySchedule) : {}

  // Whether the user has made a selection that allows generation
  const canGenerate = sourceMode !== null
    ? selectedGoalIds.length > 0   // ProgramSource sets this when a philosophy/priorities are confirmed
    : selectedGoalIds.length > 0

  function handleGenerate() {
    if (!canGenerate) return

    // Normalize blend weights
    const blendTotal = selectedPhilosophyIds.reduce((s, id) => s + (philosophyWeights[id] ?? 50), 0) || 1
    const normalizedPhilWeights = Object.fromEntries(
      selectedPhilosophyIds.map((id) => [id, (philosophyWeights[id] ?? 50) / blendTotal])
    )

    const isMultiGoal = selectedGoalIds.length > 1
    const goalTotal = selectedGoalIds.reduce((s, id) => s + (goalWeights[id] ?? 50), 0)
    const normalizedGoalWeights = Object.fromEntries(
      selectedGoalIds.map((id) => [id, (goalWeights[id] ?? 50) / goalTotal])
    )

    mutate(
      {
        // Philosophy path (modes 1 + 2)
        ...(sourceMode === 'philosophy' ? { philosophyId: selectedPhilosophyIds[0] } : {}),
        ...(sourceMode === 'blend' ? {
          philosophyIds: selectedPhilosophyIds,
          philosophyWeights: normalizedPhilWeights,
        } : {}),
        // Legacy goal path (custom mode)
        ...(sourceMode === 'custom' || sourceMode === null ? {
          goalId: selectedGoalIds[0],
          goalIds: isMultiGoal ? selectedGoalIds : undefined,
          goalWeights: isMultiGoal ? normalizedGoalWeights : undefined,
        } : {}),
        constraints: { ...constraints, ...scheduleOverride } as AthleteConstraints,
        eventDate: eventDate ?? undefined,
        startDate: startDate ?? undefined,
        numWeeks: numWeeks ?? undefined,
        frameworkId: selectedFrameworkId,
        priorityOverrides: priorityOverrides,
        customInjuryFlags,
      },
      {
        onSuccess: (result) => {
          if (result.validation.feasible) {
            setActiveGoalId(selectedGoalIds[0])
            useBuilderStore.getState().reset()
            navigate('/program')
          }
          // If infeasible, stay on step 4 so the ValidationAlert is visible
        },
      }
    )
  }

  // Source summary label
  const sourceLabel = (() => {
    if (sourceMode === 'philosophy') {
      const phil = philosophies?.find((p) => p.id === selectedPhilosophyIds[0])
      return phil?.name ?? selectedPhilosophyIds[0] ?? '—'
    }
    if (sourceMode === 'blend') {
      const names = philosophies?.filter((p) => selectedPhilosophyIds.includes(p.id)).map((p) => p.name) ?? []
      return names.join(' + ') || '—'
    }
    if (sourceMode === 'custom') return 'Custom priorities'
    return '—'
  })()

  // Detect if "Full Program (All Phases)" is selected
  // Full program mode means: no specific framework selected + philosophy has sequential phases
  const isFullProgram = useMemo(() => {
    if (selectedFrameworkId !== null) return false
    if (sourceMode !== 'philosophy') return false

    const phil = philosophies?.find((p) => p.id === selectedPhilosophyIds[0])
    if (!phil) return false

    // Check if philosophy has sequential framework groups or canonical_phase_sequence
    const hasSequential = phil.framework_groups?.some((g) => g.type === 'sequential')
    const hasCanonical = phil.canonical_phase_sequence && phil.canonical_phase_sequence.length > 0

    return hasSequential || hasCanonical
  }, [selectedFrameworkId, sourceMode, selectedPhilosophyIds, philosophies])

  const frameworkLabel = (() => {
    if (selectedFrameworkId) {
      return frameworks?.find((f) => f.id === selectedFrameworkId)?.name ?? selectedFrameworkId.replace(/_/g, ' ')
    }
    if (isFullProgram) {
      return 'Full Program (All Phases)'
    }
    return 'Auto-select'
  })()

  // Get phase sequence for display
  const phaseSequence = useMemo(() => {
    if (!isFullProgram) return null
    const phil = philosophies?.find((p) => p.id === selectedPhilosophyIds[0])
    if (!phil) return null

    return phil.framework_groups?.find((g) => g.type === 'sequential')?.canonical_phase_sequence
           ?? phil.canonical_phase_sequence
           ?? null
  }, [isFullProgram, philosophies, selectedPhilosophyIds])

  // Compute ideal schedule from framework expectations
  const idealSchedule = useMemo(() => {
    // Try to get framework expectations
    let framework = frameworks?.find((f) => f.id === selectedFrameworkId)

    // If no specific framework selected, try to get from philosophy's primary framework
    if (!framework && sourceMode === 'philosophy' && philosophies) {
      const phil = philosophies.find((p) => p.id === selectedPhilosophyIds[0])
      const primaryFwId = phil?.primary_framework_id
      if (primaryFwId) {
        framework = frameworks?.find((f) => f.id === primaryFwId)
      }
    }

    if (!framework?.expectations) {
      // Fallback to constraint-based estimation
      const days = constraints.days_per_week ?? 4
      const sessionMinutes = constraints.session_time_minutes ?? 60

      // All sessions match the constraint length
      return {
        days,
        longSessions: sessionMinutes >= 60 ? days : 0,
        shortSessions: sessionMinutes < 60 ? days : 0,
        mobilitySessions: 0,
        totalMinutes: sessionMinutes * days,
      }
    }

    const exp = framework.expectations

    // Calculate session breakdown to match total expected volume
    const days = exp.ideal_days_per_week
    const targetMinutes = exp.ideal_session_minutes * days

    // If all sessions should be the same length
    if (exp.ideal_session_minutes >= 60) {
      // All long sessions
      return {
        days,
        longSessions: days,
        shortSessions: 0,
        mobilitySessions: 0,
        totalMinutes: targetMinutes,
      }
    } else if (exp.ideal_session_minutes <= 45) {
      // All short sessions
      return {
        days,
        longSessions: 0,
        shortSessions: days,
        mobilitySessions: 0,
        totalMinutes: targetMinutes,
      }
    }

    // Mixed schedule - work backwards from target minutes
    // Default: all sessions match ideal length
    return {
      days,
      longSessions: exp.ideal_session_minutes >= 60 ? days : 0,
      shortSessions: exp.ideal_session_minutes < 60 ? days : 0,
      mobilitySessions: 0,
      totalMinutes: targetMinutes,
    }
  }, [frameworks, selectedFrameworkId, sourceMode, philosophies, selectedPhilosophyIds, constraints])

  // Compute actual schedule from user's weekly schedule
  const actualSchedule = useMemo(() => {
    if (!weeklySchedule) {
      // Fallback to constraints
      const days = constraints.days_per_week ?? 4
      return {
        days,
        longSessions: 0,
        shortSessions: 0,
        mobilitySessions: 0,
        totalMinutes: (constraints.session_time_minutes ?? 60) * days,
      }
    }

    let days = 0,
      long = 0,
      short = 0,
      mobility = 0,
      total = 0

    Object.values(weeklySchedule).forEach((day) => {
      const sessions = [day.session1, day.session2, day.session3, day.session4]
      const nonRest = sessions.filter((s) => s !== 'rest')

      if (nonRest.length > 0) days++
      long += nonRest.filter((s) => s === 'long').length
      short += nonRest.filter((s) => s === 'short').length
      mobility += nonRest.filter((s) => s === 'mobility').length

      // Sum time
      nonRest.forEach((s) => {
        total += s === 'long' ? 75 : s === 'short' ? 40 : s === 'mobility' ? 20 : 0
      })
    })

    return {
      days,
      longSessions: long,
      shortSessions: short,
      mobilitySessions: mobility,
      totalMinutes: total,
    }
  }, [weeklySchedule, constraints])

  // Compute compromises
  const compromises = useMemo(() => {
    if (!idealSchedule || !actualSchedule) return []

    const comp: string[] = []

    if (actualSchedule.days < idealSchedule.days) {
      comp.push(
        `Training days reduced from ${idealSchedule.days} to ${actualSchedule.days} — some modalities may be compressed`
      )
    }

    if (actualSchedule.totalMinutes < idealSchedule.totalMinutes * 0.8) {
      const reduction = Math.round(
        ((idealSchedule.totalMinutes - actualSchedule.totalMinutes) / idealSchedule.totalMinutes) * 100
      )
      comp.push(`Total weekly volume reduced ~${reduction}%`)
    }

    if (actualSchedule.mobilitySessions === 0 && idealSchedule.mobilitySessions > 0) {
      comp.push('No mobility sessions scheduled — consider adding 1-2 for injury prevention')
    }

    return comp
  }, [idealSchedule, actualSchedule])

  return (
    <div className="space-y-6 max-w-3xl mx-auto px-8">

      {/* Header */}
      <div className="space-y-3">
        <p className="text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium">
          Final step
        </p>
        <h2 className="text-2xl font-semibold leading-snug">
          Review & generate.
        </h2>
        <p className="text-sm text-muted-foreground leading-relaxed max-w-lg">
          Verify your configuration below, then generate your personalized training program.
        </p>
      </div>

      {/* Summary */}
      <div className="rounded-xl border bg-card p-5 space-y-3">
        <h3 className="text-sm font-semibold text-foreground">Configuration Summary</h3>
        <Separator />
        <dl className="space-y-2 text-sm">
          <Row label="Source" value={sourceLabel} />
          <Row label="Framework" value={frameworkLabel} />
          {numWeeks && <Row label="Duration" value={`${numWeeks} weeks`} />}
          <Row label="Days / week" value={String(scheduleOverride.days_per_week ?? constraints.days_per_week ?? 4)} />
          <Row
            label="Session time"
            value={
              constraints.weekday_session_minutes != null &&
              constraints.weekend_session_minutes != null &&
              constraints.weekday_session_minutes !== constraints.weekend_session_minutes
                ? `${constraints.weekday_session_minutes}m weekdays / ${constraints.weekend_session_minutes}m weekends`
                : `${constraints.weekday_session_minutes ?? constraints.session_time_minutes ?? 60} min`
            }
          />
          <Row label="Level" value={constraints.training_level ?? 'intermediate'} />
          {isFullProgram && phaseSequence ? (
            <div className="flex justify-between gap-4">
              <dt className="text-muted-foreground shrink-0">Phases</dt>
              <dd className="font-medium text-foreground text-right">
                <div className="flex flex-wrap gap-1 justify-end">
                  {phaseSequence.map((p, i) => (
                    <span key={i} className="text-xs px-1.5 py-0.5 rounded bg-primary/10 text-primary capitalize">
                      {p.phase} ({p.weeks}w)
                    </span>
                  ))}
                </div>
              </dd>
            </div>
          ) : (
            <Row label="Phase" value={constraints.training_phase ?? 'base'} />
          )}
          <Row label="Fatigue" value={constraints.fatigue_state ?? 'normal'} />
          <Row label="Equipment" value={`${(constraints.equipment ?? []).length} items`} />
          <Row label="Injuries" value={(constraints.injury_flags ?? []).length === 0 ? 'None' : (constraints.injury_flags ?? []).length + ' flags'} />
          {startDate && <Row label="Program start" value={startDate} />}
          {eventDate && <Row label="Event date" value={eventDate} />}
        </dl>
      </div>

      {/* Pre-generation feasibility */}
      {!data && <FeasibilityPanel mode="full" />}

      {/* Schedule guidance */}
      {weeklySchedule && idealSchedule && actualSchedule && (
        <ScheduleGuidance ideal={idealSchedule} actual={actualSchedule} compromises={compromises} />
      )}

      {/* Post-generation validation feedback */}
      {data?.validation && <ValidationAlert validation={data.validation} />}
      {error && (
        <p className="text-sm text-destructive">{(error as Error).message}</p>
      )}

      {/* Schedule adjustments/compromises */}
      {data?.compromises && data.compromises.length > 0 && (
        <div className="rounded-lg border border-warning/40 bg-warning/10 p-4 space-y-2">
          <h4 className="text-sm font-semibold text-warning-foreground">Schedule Adjustments</h4>
          <ul className="text-xs text-muted-foreground space-y-1">
            {data.compromises.map((msg, i) => (
              <li key={i}>• {msg}</li>
            ))}
          </ul>
          <p className="text-xs text-muted-foreground/80 pt-1 border-t border-warning/20">
            Your program has been adapted to fit your availability. Consider adding more training days for the full program experience.
          </p>
        </div>
      )}

      {/* Generate button */}
      <motion.div
        animate={{ scale: isPending ? 0.98 : 1 }}
        transition={{ duration: 0.2 }}
      >
        <Button
          size="lg"
          className="w-full gap-2"
          onClick={handleGenerate}
          disabled={isPending || !canGenerate || hasErrors === true || hasFeasibilityErrors}
        >
          {isPending ? (
            <>
              <Loader2 className="size-4 animate-spin" />
              Generating…
            </>
          ) : (
            <>
              <Wand2 className="size-4" />
              Generate Program
            </>
          )}
        </Button>
      </motion.div>
    </div>
  )
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between gap-4">
      <dt className="text-muted-foreground shrink-0">{label}</dt>
      <dd className="font-medium text-foreground capitalize">{value}</dd>
    </div>
  )
}
