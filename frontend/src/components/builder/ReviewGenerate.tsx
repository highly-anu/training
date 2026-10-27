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
import { useGenerateDraft } from '@/api/programs'
import { usePhilosophies } from '@/api/philosophies'
import { useFrameworks } from '@/api/frameworks'
import { usePreviewStore } from '@/store/previewStore'
import { builderGenerateParams } from '@/lib/builderParams'
import { scheduleToConstraints, type ScheduleConstraints } from '@/lib/scheduleToConstraints'
import { builderTrack, findTrack, mainFramework, mergedEntryRequirements, primaryTrack } from '@/lib/tracks'

export function ReviewGenerate() {
  const navigate = useNavigate()
  const {
    selectedGoalIds,
    sourceMode,
    selectedPhilosophyIds,
    constraints,
    eventDate,
    startDate,
    selectedTrackId,
    startPhaseId,
    numWeeks,
    lanes,
  } = useBuilderStore()
  const { customInjuryFlags, weeklySchedule } = useProfileStore()
  const { mutate, isPending, error, data } = useGenerateDraft()
  const { data: philosophies } = usePhilosophies()
  const { data: frameworks } = useFrameworks()

  const feasibilitySignals = useFeasibility()
  const hasFeasibilityErrors = feasibilitySignals.some((s) => s.severity === 'error')
  const hasErrors = data?.validation && !data.validation.feasible

  // Always derive schedule-based constraints from the saved weekly schedule.
  // This overrides stale persisted values in the builder store so the API call
  // and the Configuration Summary always reflect the actual training days.
  const scheduleOverride: Partial<ScheduleConstraints> = weeklySchedule ? scheduleToConstraints(weeklySchedule) : {}

  // Whether the user has made a selection that allows generation
  const canGenerate = sourceMode !== null
    ? selectedGoalIds.length > 0   // ProgramSource sets this when a philosophy/priorities are confirmed
    : selectedGoalIds.length > 0

  function handleGenerate() {
    if (!canGenerate) return
    const params = builderGenerateParams(useBuilderStore.getState(), weeklySchedule, customInjuryFlags)
    mutate(params, {
      onSuccess: (draft) => {
        // A draft, not the program: the preview shows it, what the
        // constraints held back, and starts it only when asked. A refusal
        // goes there too — the preview says which change alone would let
        // it build, and can adjust and try again — but never starts.
        if (draft?.validation) {
          usePreviewStore.getState().open('new', params, draft)
          navigate('/program/preview')
        }
      },
    })
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

  // The track that will run, and its phases
  const picked = useMemo(
    () => builderTrack(philosophies, selectedPhilosophyIds, selectedTrackId, constraints.training_level),
    [philosophies, selectedPhilosophyIds, selectedTrackId, constraints.training_level],
  )
  const activeTrack = sourceMode === 'philosophy' || sourceMode === 'blend' ? picked?.track : undefined
  // Several tracks: each is listed, and the athlete answers what any of them asks.
  const composed = sourceMode === 'blend' && lanes.length > 1
  const laneTracks = useMemo(() => (composed ? lanes : []).map((l) => {
    const phil = philosophies?.find((p) => p.id === l.philosophyId)
    return { lane: l, philosophy: phil, track: findTrack(phil, l.trackId) ?? primaryTrack(phil, constraints.training_level) }
  }), [composed, lanes, philosophies, constraints.training_level])
  const requirements = composed
    ? mergedEntryRequirements(laneTracks.map((t) => t.track), constraints.training_level ?? 'intermediate')
    : activeTrack?.entry_requirements
  const requiredSkills = requirements?.mastered_exercises_by_level?.[constraints.training_level ?? 'intermediate']
    ?? requirements?.mastered_exercises ?? []
  const entryReady = !requirements || (
    requirements.training_levels.includes(constraints.training_level ?? 'intermediate') &&
    requiredSkills.every((id) => constraints.mastered_exercises?.includes(id)) &&
    (requirements.kettlebell_count < 2 || (constraints.kettlebell_count ?? 0) >= 2)
  )
  const trackLabel = activeTrack?.name ?? 'Auto-select'
  const startPhaseName = activeTrack?.phases.find((p) => p.id === startPhaseId)?.name

  // Compute ideal schedule from framework expectations
  const idealSchedule = useMemo(() => {
    // The expectations of the framework that stands for the track
    const framework = mainFramework(activeTrack, frameworks)

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
  }, [frameworks, activeTrack, constraints])

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
          Review & preview.
        </h2>
        <p className="text-sm text-muted-foreground leading-relaxed max-w-lg">
          Verify your configuration below, then preview the program: what it plans, what your
          equipment, injuries, level and schedule hold back. Nothing changes until you start it.
        </p>
      </div>

      {/* Summary */}
      <div className="rounded-xl border bg-card p-5 space-y-3">
        <h3 className="text-sm font-semibold text-foreground">Configuration Summary</h3>
        <Separator />
        <dl className="space-y-2 text-sm">
          <Row label="Source" value={sourceLabel} />
          {composed ? laneTracks.map(({ lane, philosophy, track }, i) => {
            const total = lanes.reduce((n, l) => n + l.weight, 0) || 1
            const start = track?.phases.find((p) => p.id === lane.startPhaseId)?.name
            return (
              <Row key={`${lane.philosophyId}-${i}`}
                   label={`Track · ${Math.round((lane.weight / total) * 100)}%`}
                   value={`${philosophy?.name ?? lane.philosophyId} — ${track?.name ?? ''}${start && !eventDate ? ` (from ${start})` : ''}`} />
            )
          }) : <Row label="Track" value={trackLabel} />}
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
          {activeTrack && !composed && (
            <div className="flex justify-between gap-4">
              <dt className="text-muted-foreground shrink-0">Phases</dt>
              <dd className="font-medium text-foreground text-right">
                <div className="flex flex-wrap gap-1 justify-end">
                  {activeTrack.phases.map((p) => (
                    <span key={p.id} className="text-xs px-1.5 py-0.5 rounded bg-primary/10 text-primary">
                      {p.name} ({p.weeks}w)
                    </span>
                  ))}
                </div>
              </dd>
            </div>
          )}
          {!composed && startPhaseName && !eventDate && <Row label="Starts at" value={startPhaseName} />}
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
      {!composed && weeklySchedule && idealSchedule && actualSchedule && (
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
      {requirements && (
        <div className="space-y-2 text-sm">
          {!requirements.training_levels.includes(constraints.training_level ?? 'intermediate') &&
            <p>This track supports {requirements.training_levels.join(', ')} athletes. Choose a different track or correct your level.</p>}
          {requiredSkills.map((id) => (
            <label key={id} className="flex items-center gap-2">
              <input type="checkbox" checked={constraints.mastered_exercises?.includes(id) ?? false}
                onChange={(event) => useBuilderStore.getState().updateConstraints({ mastered_exercises: event.target.checked
                  ? [...(constraints.mastered_exercises ?? []), id]
                  : (constraints.mastered_exercises ?? []).filter((value) => value !== id) })} />
              I can perform {requirements.exercise_names?.[id] ?? id.replaceAll('_', ' ')} with controlled technique.
            </label>
          ))}
          {requirements.kettlebell_count >= 2 && <label className="flex items-center gap-2">
            <input type="checkbox" checked={(constraints.kettlebell_count ?? 0) >= 2}
              onChange={(event) => useBuilderStore.getState().updateConstraints({ kettlebell_count: event.target.checked ? 2 : 1 })} />
            I have two matching kettlebells appropriate for these exercises.
          </label>}
          {(requirements.starting_loads?.length ?? 0) > 0 && (
            <div className="space-y-1.5 pt-1">
              <p className="text-muted-foreground">
                The weight you last made on each lift, if you know it (optional). Leave one empty and its
                first session works up to a weight from the empty bar.
              </p>
              <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
                {requirements.starting_loads!.map(({ id, name }) => (
                  <label key={id} className="flex items-center justify-between gap-2 rounded-md border px-2 py-1">
                    <span>{name}</span>
                    <input
                      aria-label={`${name} kg`}
                      inputMode="decimal"
                      placeholder="kg"
                      className="h-7 w-16 rounded border bg-background px-1.5 text-right"
                      value={constraints.starting_loads_kg?.[id] ?? ''}
                      onChange={(event) => {
                        const kg = Number(event.target.value)
                        const next = { ...(constraints.starting_loads_kg ?? {}) }
                        if (event.target.value && kg > 0) next[id] = kg
                        else delete next[id]
                        useBuilderStore.getState().updateConstraints({ starting_loads_kg: next })
                      }}
                    />
                  </label>
                ))}
              </div>
            </div>
          )}
        </div>
      )}
      <motion.div
        animate={{ scale: isPending ? 0.98 : 1 }}
        transition={{ duration: 0.2 }}
      >
        <Button
          size="lg"
          className="w-full gap-2"
          onClick={handleGenerate}
          disabled={isPending || !canGenerate || !entryReady || hasErrors === true || hasFeasibilityErrors}
        >
          {isPending ? (
            <>
              <Loader2 className="size-4 animate-spin" />
              Generating…
            </>
          ) : (
            <>
              <Wand2 className="size-4" />
              Preview program
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
