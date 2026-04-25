import { useEffect, useMemo, useState } from 'react'
import { Check, X, GripVertical, RotateCcw } from 'lucide-react'
import { useBuilderStore } from '@/store/builderStore'
import { useProfileStore } from '@/store/profileStore'
import { useFrameworks } from '@/api/frameworks'
import { usePhilosophies } from '@/api/philosophies'
import { blendExpectations } from '@/lib/feasibility'
import { scheduleToConstraints } from '@/lib/scheduleToConstraints'
import type { Day, DaySchedule, SessionType } from '@/api/types'

const DAYS: Day[] = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
const DAY_SHORT: Record<Day, string> = {
  Monday: 'Mon',
  Tuesday: 'Tue',
  Wednesday: 'Wed',
  Thursday: 'Thu',
  Friday: 'Fri',
  Saturday: 'Sat',
  Sunday: 'Sun',
}

const SESSION_TYPES: { id: SessionType; label: string; minutes: number }[] = [
  { id: 'rest', label: 'Rest', minutes: 0 },
  { id: 'short', label: 'Short', minutes: 40 },
  { id: 'long', label: 'Long', minutes: 75 },
  { id: 'mobility', label: 'Mobility', minutes: 20 },
]

export function GuidedScheduler() {
  const {
    updateConstraints,
    selectedGoalIds,
    goalWeights,
    sourceMode,
    selectedFrameworkId,
    selectedPhilosophyIds,
  } = useBuilderStore()

  const { weeklySchedule, setWeeklySchedule } = useProfileStore()
  const { data: frameworks = [] } = useFrameworks()
  const { data: philosophies = [] } = usePhilosophies()

  const exp = useMemo(
    () => blendExpectations([], selectedGoalIds, goalWeights, {
      sourceMode,
      frameworks,
      selectedFrameworkId,
      selectedPhilosophyIds,
      philosophies,
    }),
    [selectedGoalIds, goalWeights, sourceMode, frameworks, selectedFrameworkId, selectedPhilosophyIds, philosophies],
  )

  // Initialize from Profile schedule or create default
  const schedule = useMemo<Record<Day, DaySchedule>>(() => {
    if (weeklySchedule) return weeklySchedule

    // Create default schedule
    return Object.fromEntries(
      DAYS.map((day) => [
        day,
        {
          session1: 'rest' as SessionType,
          session2: 'rest' as SessionType,
          session3: 'rest' as SessionType,
          session4: 'rest' as SessionType,
        },
      ])
    ) as Record<Day, DaySchedule>
  }, [weeklySchedule])

  // Sync persisted schedule into constraints on mount (and whenever the saved schedule changes).
  // Without this, days_per_week stays at the store default (4) even when the profile has 7 days.
  useEffect(() => {
    syncToConstraints(schedule)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [weeklySchedule])

  // State for customized recommendations (null = use auto-calculated)
  const [customRecommendations, setCustomRecommendations] = useState<Record<Day, DaySchedule> | null>(null)

  // Drag state
  const [dragSource, setDragSource] = useState<{ day: Day; sessionIdx: number } | null>(null)

  // Calculate actual schedule metrics
  const actualMetrics = useMemo(() => {
    let days = 0
    let longSessions = 0
    let shortSessions = 0
    let mobilitySessions = 0
    let totalMinutes = 0

    Object.values(schedule).forEach((day) => {
      const sessions = [day.session1, day.session2, day.session3, day.session4]
      const nonRest = sessions.filter((s) => s !== 'rest')

      if (nonRest.length > 0) days++
      longSessions += nonRest.filter((s) => s === 'long').length
      shortSessions += nonRest.filter((s) => s === 'short').length
      mobilitySessions += nonRest.filter((s) => s === 'mobility').length

      nonRest.forEach((s) => {
        const config = SESSION_TYPES.find((st) => st.id === s)
        if (config) totalMinutes += config.minutes
      })
    })

    return { days, longSessions, shortSessions, mobilitySessions, totalMinutes }
  }, [schedule])

  // Ideal metrics from program
  const idealMetrics = useMemo(() => {
    if (!exp) return null

    const idealWeekly = exp.ideal_long_session_minutes != null
      ? (exp.ideal_days_per_week - 1) * exp.ideal_session_minutes + exp.ideal_long_session_minutes
      : exp.ideal_days_per_week * exp.ideal_session_minutes

    return {
      days: exp.ideal_days_per_week,
      totalMinutes: idealWeekly,
      sessionMinutes: exp.ideal_session_minutes,
      longSessionMinutes: exp.ideal_long_session_minutes,
      supportsSecondary: exp.supports_split_days,
    }
  }, [exp])

  // Update a specific session
  function updateSession(day: Day, sessionSlot: 'session1' | 'session2' | 'session3' | 'session4', type: SessionType) {
    const newSchedule = {
      ...schedule,
      [day]: {
        ...schedule[day],
        [sessionSlot]: type,
      },
    }
    setWeeklySchedule(newSchedule)
    syncToConstraints(newSchedule)
  }

  // Sync schedule to constraints format
  function syncToConstraints(sched: Record<Day, DaySchedule>) {
    updateConstraints(scheduleToConstraints(sched))
  }

  // Calculate recommended schedule
  const recommendedSchedule = useMemo<Record<Day, DaySchedule> | null>(() => {
    if (!idealMetrics) return null

    const newSchedule = {} as Record<Day, DaySchedule>

    // Reset all to rest
    DAYS.forEach((day) => {
      newSchedule[day] = {
        session1: 'rest',
        session2: 'rest',
        session3: 'rest',
        session4: 'rest',
      }
    })

    // Spread training days across the week
    const trainingDayIndices: number[] = []
    const step = Math.floor(7 / idealMetrics.days)
    for (let i = 0; i < idealMetrics.days; i++) {
      const idx = Math.min(i * step, 6)
      if (!trainingDayIndices.includes(idx)) {
        trainingDayIndices.push(idx)
      }
    }

    // Fill remaining if needed
    while (trainingDayIndices.length < idealMetrics.days && trainingDayIndices.length < 7) {
      for (let i = 0; i < 7; i++) {
        if (!trainingDayIndices.includes(i)) {
          trainingDayIndices.push(i)
          break
        }
      }
    }

    trainingDayIndices.forEach((idx, position) => {
      const day = DAYS[idx]
      const isLastDay = position === trainingDayIndices.length - 1
      const hasLongSession = idealMetrics.longSessionMinutes != null

      if (hasLongSession && isLastDay) {
        // Long day
        newSchedule[day].session1 = 'long'
      } else {
        // Regular session based on ideal minutes
        if (idealMetrics.sessionMinutes >= 60) {
          newSchedule[day].session1 = 'long'
        } else if (idealMetrics.sessionMinutes >= 40) {
          newSchedule[day].session1 = 'short'
        } else {
          newSchedule[day].session1 = 'short'
        }

        // Add mobility if supports split days
        if (idealMetrics.supportsSecondary) {
          newSchedule[day].session2 = 'mobility'
        }
      }
    })

    return newSchedule
  }, [idealMetrics])

  // Use custom recommendations if available, otherwise auto-calculated
  const activeRecommendations = customRecommendations ?? recommendedSchedule

  // Apply ideal schedule
  function applyIdeal() {
    if (!activeRecommendations) return
    setWeeklySchedule(activeRecommendations)
    syncToConstraints(activeRecommendations)
  }

  // Drag and drop handlers for recommendations
  function handleDragStart(day: Day, sessionIdx: number, sessionType: SessionType) {
    if (sessionType === 'rest') return
    setDragSource({ day, sessionIdx })
  }

  function handleDragOver(e: React.DragEvent) {
    e.preventDefault() // Allow drop
  }

  function handleDrop(targetDay: Day) {
    if (!dragSource || !activeRecommendations) return

    const newRecs = { ...activeRecommendations }
    const sourceDay = dragSource.day
    const sourceSessions = [
      newRecs[sourceDay].session1,
      newRecs[sourceDay].session2,
      newRecs[sourceDay].session3,
      newRecs[sourceDay].session4,
    ]

    // Get the session being dragged
    const draggedSession = sourceSessions[dragSource.sessionIdx]
    if (draggedSession === 'rest') return

    // Remove from source
    const updatedSourceSessions = [...sourceSessions]
    updatedSourceSessions[dragSource.sessionIdx] = 'rest'

    // Compact source (remove gaps)
    const compactedSource: SessionType[] = updatedSourceSessions.filter((s) => s !== 'rest')
    while (compactedSource.length < 4) compactedSource.push('rest')

    newRecs[sourceDay] = {
      session1: compactedSource[0] as SessionType,
      session2: compactedSource[1] as SessionType,
      session3: compactedSource[2] as SessionType,
      session4: compactedSource[3] as SessionType,
    }

    // Add to target
    const targetSessions = [
      newRecs[targetDay].session1,
      newRecs[targetDay].session2,
      newRecs[targetDay].session3,
      newRecs[targetDay].session4,
    ]
    const targetNonRest: SessionType[] = targetSessions.filter((s) => s !== 'rest')
    targetNonRest.push(draggedSession)
    while (targetNonRest.length < 4) targetNonRest.push('rest')

    newRecs[targetDay] = {
      session1: targetNonRest[0] as SessionType,
      session2: targetNonRest[1] as SessionType,
      session3: targetNonRest[2] as SessionType,
      session4: targetNonRest[3] as SessionType,
    }

    setCustomRecommendations(newRecs)
    setDragSource(null)
  }

  // Reset to auto-calculated recommendations
  function resetRecommendations() {
    setCustomRecommendations(null)
  }

  // Calculate coverage
  const coverage = idealMetrics && idealMetrics.totalMinutes > 0
    ? Math.min(actualMetrics.totalMinutes / idealMetrics.totalMinutes, 1.5)
    : null

  return (
    <div className="space-y-5">
      {/* Program guidance */}
      {idealMetrics && (
        <div className="rounded-xl border border-border/50 bg-card/30 p-4 space-y-3">
          <div className="flex items-start justify-between gap-4">
            <div>
              <p className="text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium mb-1">
                Program recommendations
              </p>
              <div className="grid grid-cols-2 gap-x-6 gap-y-1 text-xs">
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Training days</span>
                  <span className="font-semibold text-foreground">{idealMetrics.days} days/week</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Session length</span>
                  <span className="font-semibold text-foreground">{idealMetrics.sessionMinutes} min</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Weekly volume</span>
                  <span className="font-semibold text-foreground">{idealMetrics.totalMinutes} min/week</span>
                </div>
                {idealMetrics.supportsSecondary && (
                  <div className="flex justify-between">
                    <span className="text-muted-foreground">Split sessions</span>
                    <span className="font-semibold text-foreground">Supported</span>
                  </div>
                )}
              </div>
            </div>
            <div className="flex gap-2 shrink-0">
              {customRecommendations && (
                <button
                  type="button"
                  onClick={resetRecommendations}
                  className="text-xs px-3 py-1.5 rounded-md border border-border hover:border-primary text-muted-foreground hover:text-foreground transition-colors flex items-center gap-1.5"
                  title="Reset to auto-calculated"
                >
                  <RotateCcw className="size-3" />
                  Reset
                </button>
              )}
              <button
                type="button"
                onClick={applyIdeal}
                className="text-xs px-3 py-1.5 rounded-md border border-border hover:border-primary text-foreground hover:bg-muted transition-colors"
              >
                Apply to profile
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Weekly schedule table */}
      <div className="rounded-xl border border-border/50 bg-card/30 overflow-hidden">
        <table className="w-full text-xs">
          <thead className="border-b border-border/50 bg-muted/30">
            <tr>
              <th className="text-left p-3 font-semibold text-muted-foreground uppercase tracking-wider text-[10px]">
                Day
              </th>
              <th className="text-left p-3 font-semibold text-muted-foreground uppercase tracking-wider text-[10px]">
                Recommended
              </th>
              <th className="text-left p-3 font-semibold text-muted-foreground uppercase tracking-wider text-[10px]">
                Your Profile
              </th>
              <th className="text-center p-3 font-semibold text-muted-foreground uppercase tracking-wider text-[10px] w-16">
                Match
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-border/30">
            {DAYS.map((day) => {
              const daySchedule = schedule[day]
              const recommendedDay = activeRecommendations?.[day]

              const sessions = [
                { slot: 'session1' as const, actual: daySchedule.session1, recommended: recommendedDay?.session1 },
                { slot: 'session2' as const, actual: daySchedule.session2, recommended: recommendedDay?.session2 },
                { slot: 'session3' as const, actual: daySchedule.session3, recommended: recommendedDay?.session3 },
                { slot: 'session4' as const, actual: daySchedule.session4, recommended: recommendedDay?.session4 },
              ]

              const actualNonRest = sessions.filter((s) => s.actual !== 'rest')
              const recommendedNonRest = sessions.filter((s) => s.recommended && s.recommended !== 'rest')
              const allMatch = sessions.every((s) => s.actual === s.recommended)

              return (
                <tr
                  key={day}
                  className="hover:bg-muted/20 transition-colors"
                  onDragOver={handleDragOver}
                  onDrop={() => handleDrop(day)}
                >
                  <td className="p-3 font-semibold text-foreground">
                    {DAY_SHORT[day]}
                  </td>
                  <td className="p-3">
                    {recommendedNonRest.length > 0 ? (
                      <div className="flex flex-wrap gap-1">
                        {recommendedNonRest.map(({ recommended }, idx) => {
                          const config = SESSION_TYPES.find((s) => s.id === recommended)!
                          const isDragging = dragSource?.day === day && dragSource?.sessionIdx === idx
                          return (
                            <div
                              key={idx}
                              draggable
                              onDragStart={() => handleDragStart(day, idx, recommended!)}
                              onDragEnd={() => setDragSource(null)}
                              className="inline-flex items-center gap-1 px-2 py-0.5 rounded border border-border bg-muted/40 text-foreground font-medium cursor-move hover:bg-muted transition-colors"
                              style={{ opacity: isDragging ? 0.5 : 1 }}
                            >
                              <GripVertical className="size-3 text-muted-foreground" />
                              {config.label}
                            </div>
                          )
                        })}
                      </div>
                    ) : (
                      <span className="text-muted-foreground">Rest</span>
                    )}
                  </td>
                  <td className="p-3">
                    {actualNonRest.length > 0 ? (
                      <div className="flex flex-wrap gap-1">
                        {actualNonRest.map(({ slot, actual }, idx) => {
                          const config = SESSION_TYPES.find((s) => s.id === actual)!
                          return (
                            <button
                              key={idx}
                              type="button"
                              onClick={() => {
                                const currentIdx = SESSION_TYPES.findIndex((s) => s.id === actual)
                                const nextIdx = (currentIdx + 1) % SESSION_TYPES.length
                                updateSession(day, slot, SESSION_TYPES[nextIdx].id)
                              }}
                              className="inline-block px-2 py-0.5 rounded border border-border bg-card hover:bg-muted text-foreground font-medium transition-colors"
                            >
                              {config.label}
                            </button>
                          )
                        })}
                        <button
                          type="button"
                          onClick={() => {
                            const nextSlot = `session${actualNonRest.length + 1}` as 'session1' | 'session2' | 'session3' | 'session4'
                            if (actualNonRest.length < 4) {
                              updateSession(day, nextSlot, 'short')
                            }
                          }}
                          className="inline-block px-2 py-0.5 rounded border border-dashed border-border text-muted-foreground hover:border-foreground hover:text-foreground transition-colors text-[10px]"
                        >
                          + Add
                        </button>
                      </div>
                    ) : (
                      <button
                        type="button"
                        onClick={() => {
                          const firstRec = sessions.find((s) => s.recommended && s.recommended !== 'rest')
                          updateSession(day, 'session1', firstRec?.recommended ?? 'long')
                        }}
                        className="text-muted-foreground hover:text-foreground transition-colors"
                      >
                        Rest · click to add
                      </button>
                    )}
                  </td>
                  <td className="p-3 text-center">
                    {allMatch ? (
                      <Check className="size-4 text-foreground mx-auto" />
                    ) : (
                      <X className="size-4 text-muted-foreground/30 mx-auto" />
                    )}
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>

      {/* Summary */}
      {idealMetrics && (
        <div className="rounded-xl border border-border/50 bg-card/30 p-4">
          <div className="flex items-center justify-between text-xs mb-2">
            <div>
              <span className="text-muted-foreground">Your schedule: </span>
              <span className="font-semibold text-foreground">
                {actualMetrics.days} days · {actualMetrics.totalMinutes} min/week
              </span>
            </div>
            {coverage != null && (
              <span className="font-semibold text-foreground">
                {Math.round(coverage * 100)}% of ideal
              </span>
            )}
          </div>
          <div className="h-2 w-full rounded-full bg-muted overflow-hidden">
            <div
              className="h-full rounded-full bg-foreground/60 transition-all duration-300"
              style={{ width: `${Math.min(Math.round((coverage ?? 0) * 100), 100)}%` }}
            />
          </div>
          {coverage != null && coverage < 0.8 && (
            <p className="text-[10px] text-muted-foreground mt-2">
              {coverage < 0.6
                ? 'Below 60% of ideal volume — consider adding more days or time.'
                : 'Below 80% of ideal volume — close to target.'}
            </p>
          )}
        </div>
      )}
    </div>
  )
}
