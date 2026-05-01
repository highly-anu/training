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

    let cursor = 1
    const segments: PhaseSegment[] = goal.phase_sequence.map((entry) => {
      const seg: PhaseSegment = {
        phase: entry.phase,
        weeks: entry.weeks,
        focus: entry.focus,
        startWeek: cursor,
        endWeek: cursor + entry.weeks - 1,
      }
      cursor += entry.weeks
      return seg
    })

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
