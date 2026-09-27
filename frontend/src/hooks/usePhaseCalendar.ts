import { useMemo } from 'react'
import { differenceInWeeks } from 'date-fns'
import type { GoalProfile, TrainingPhase } from '@/api/types'

export interface PhaseSegment {
  phase: TrainingPhase
  weeks: number
  focus?: string
  startWeek: number
  endWeek: number
}

export interface PhaseCalendar {
  segments: PhaseSegment[]
  totalWeeks: number
  currentWeek: number | null
  currentPhase: TrainingPhase | null
  weeksToEvent: number | null
}

export function usePhaseCalendar(goal: GoalProfile | undefined, currentWeek = 1): PhaseCalendar {
  return useMemo(() => {
    if (!goal) {
      return { segments: [], totalWeeks: 0, currentWeek: null, currentPhase: null, weeksToEvent: null }
    }

    // A plain loop rather than a side-effecting `.map`: advancing `cursor`
    // from inside the callback is a mutation the React Compiler cannot prove
    // stays within the render, so it bailed out of optimising this hook
    // entirely. The running total is also simply clearer this way.
    const segments: PhaseSegment[] = []
    let cursor = 1
    for (const entry of goal.phase_sequence) {
      segments.push({
        phase: entry.phase,
        weeks: entry.weeks,
        focus: entry.focus,
        startWeek: cursor,
        endWeek: cursor + entry.weeks - 1,
      })
      cursor += entry.weeks
    }

    const totalWeeks = cursor - 1

    const currentPhase =
      segments.find((s) => currentWeek >= s.startWeek && currentWeek <= s.endWeek)
        ?.phase ?? null

    const weeksToEvent = goal.event_date
      ? differenceInWeeks(new Date(goal.event_date), new Date())
      : null

    return { segments, totalWeeks, currentWeek, currentPhase, weeksToEvent }
  }, [goal, currentWeek])
}
