import { useMemo } from 'react'
import { differenceInWeeks } from 'date-fns'
import type { GeneratedProgram, GoalProfile, TrainingPhase, WeekData } from '@/api/types'

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

const EMPTY: PhaseCalendar = { segments: [], totalWeeks: 0, currentWeek: null, currentPhase: null, weeksToEvent: null }

/**
 * The calendar of the program the athlete is on: its stored weeks grouped
 * into phase segments, in order.
 *
 * It used to be built from the methodology's canonical phase sequence —
 * 8 + 6 + 4 = 18 weeks for Starting Strength — whatever the program held, so
 * a 4-week plan read "Week 1 / 18", and the injuries sheet, which sizes its
 * regenerate from this total, asked for 18 weeks and dropped the kept head.
 * The goal still contributes a phase's focus text and the event date.
 */
export function buildPhaseCalendar(
  weeks: WeekData[] | undefined,
  goal: GoalProfile | undefined,
  currentWeek = 1,
): PhaseCalendar {
  const focusOf = new Map<string, string | undefined>(
    (goal?.phase_sequence ?? []).map((entry) => [entry.phase, entry.focus]),
  )
  const segments: PhaseSegment[] = []

  if (weeks && weeks.length > 0) {
    let cursor = 1
    for (const week of weeks) {
      const last = segments[segments.length - 1]
      if (last && last.phase === week.phase) {
        last.weeks += 1
        last.endWeek = cursor
      } else {
        segments.push({ phase: week.phase, weeks: 1, focus: focusOf.get(week.phase), startWeek: cursor, endWeek: cursor })
      }
      cursor += 1
    }
  } else if (goal) {
    // No weeks to read yet (the builder's preview): the methodology's plan.
    let cursor = 1
    for (const entry of goal.phase_sequence) {
      segments.push({ phase: entry.phase, weeks: entry.weeks, focus: entry.focus,
                      startWeek: cursor, endWeek: cursor + entry.weeks - 1 })
      cursor += entry.weeks
    }
  } else {
    return EMPTY
  }

  const totalWeeks = segments.reduce((n, s) => n + s.weeks, 0)
  const currentPhase =
    segments.find((s) => currentWeek >= s.startWeek && currentWeek <= s.endWeek)?.phase ?? null
  const weeksToEvent = goal?.event_date ? differenceInWeeks(new Date(goal.event_date), new Date()) : null

  return { segments, totalWeeks, currentWeek, currentPhase, weeksToEvent }
}

export function usePhaseCalendar(program: GeneratedProgram | undefined, currentWeek = 1): PhaseCalendar {
  return useMemo(
    () => buildPhaseCalendar(program?.weeks, program?.goal, currentWeek),
    [program, currentWeek],
  )
}
