import { useMemo } from 'react'
import { differenceInWeeks } from 'date-fns'
import type { GeneratedProgram, GoalProfile, Phase, PhaseEntry, PhaseKind, WeekData } from '@/api/types'
import { phaseEntryFor } from '@/lib/tracks'

export interface PhaseSegment {
  /** The phase kind — colours key on it. */
  phase: PhaseKind
  /** The philosophy's own phase id and name, when the program carries them. */
  phaseId?: string
  name?: string
  weeks: number
  focus?: string
  /** The goal's entry for this phase — the only source of its words. */
  entry?: PhaseEntry
  startWeek: number
  endWeek: number
}

/** Segments for a track's phases, before any program exists (builder, Explore). */
export function trackSegments(phases: Phase[]): PhaseSegment[] {
  const out: PhaseSegment[] = []
  let cursor = 1
  for (const p of phases) {
    out.push({ phase: p.kind, phaseId: p.id, name: p.name, weeks: p.weeks, focus: p.focus,
               startWeek: cursor, endWeek: cursor + p.weeks - 1 })
    cursor += p.weeks
  }
  return out
}

/**
 * One track of a composed program as its own phases ran: its weeks grouped by
 * the track's phase (`week.lanes`), its words from the track's own sequence —
 * the week's phase fields are the lead track's.
 */
export function laneSegments(weeks: WeekData[] | undefined, laneKey: string,
                             sequence: PhaseEntry[] = []): PhaseSegment[] {
  const segments: PhaseSegment[] = []
  let cursor = 1
  for (const week of weeks ?? []) {
    const lane = week.lanes?.find((l) => l.lane_key === laneKey)
    const key = lane?.phase_id ?? lane?.phase
    const last = segments[segments.length - 1]
    if (lane && last && (last.phaseId ?? last.phase) === key) {
      last.weeks += 1
      last.endWeek = cursor
    } else if (lane) {
      const entry = sequence.find((e) => e.phase_id === lane.phase_id)
      segments.push({ phase: lane.phase, phaseId: lane.phase_id, name: lane.phase_name ?? entry?.name,
                      weeks: 1, focus: entry?.focus, entry, startWeek: cursor, endWeek: cursor })
    }
    cursor += 1
  }
  return segments
}

export interface PhaseCalendar {
  segments: PhaseSegment[]
  totalWeeks: number
  currentWeek: number | null
  currentPhase: PhaseKind | null
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
 * The goal still contributes a phase's own words and the event date.
 *
 * Weeks are grouped by the philosophy's phase id, so two phases of the same
 * kind stay two segments; a program stored before tracks groups by kind.
 */
export function buildPhaseCalendar(
  weeks: WeekData[] | undefined,
  goal: GoalProfile | undefined,
  currentWeek = 1,
): PhaseCalendar {
  const segments: PhaseSegment[] = []
  const keyOf = (w: Pick<WeekData, 'phase' | 'phase_id'>) => w.phase_id ?? w.phase

  if (weeks && weeks.length > 0) {
    let cursor = 1
    let lastKey: string | null = null
    for (const week of weeks) {
      const last = segments[segments.length - 1]
      if (last && lastKey === keyOf(week)) {
        last.weeks += 1
        last.endWeek = cursor
      } else {
        const entry = phaseEntryFor(goal, week)
        segments.push({
          phase: week.phase, phaseId: week.phase_id ?? entry?.phase_id,
          name: week.phase_name ?? entry?.name, weeks: 1, focus: entry?.focus, entry,
          startWeek: cursor, endWeek: cursor,
        })
        lastKey = keyOf(week)
      }
      cursor += 1
    }
  } else if (goal) {
    // No weeks to read yet (the builder's preview): the methodology's plan.
    let cursor = 1
    for (const entry of goal.phase_sequence) {
      segments.push({ phase: entry.phase, phaseId: entry.phase_id, name: entry.name, weeks: entry.weeks,
                      focus: entry.focus, entry, startWeek: cursor, endWeek: cursor + entry.weeks - 1 })
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
