/**
 * The words for what a program's constraints held back: a slot's
 * `blocked_by` (selector._explain_unfilled) and a session's substitution.
 */
import { describe, it, expect } from 'vitest'
import { blockerText, emptySlotText, heldBackCounts, sessionNotes } from './heldBack'
import type { ExerciseAssignment, GeneratedProgram, Session } from '@/api/types'

const names = {
  exercise: (id: string) => ({ back_squat: 'Back Squat', strict_pull_up: 'Strict Pull-up' } as Record<string, string>)[id],
  flag: (id: string) => ({ knee_meniscus_post_op: 'Knee (post-op)' } as Record<string, string>)[id],
}

describe('blockerText', () => {
  it('names the equipment a lift needs', () => {
    expect(blockerText({ cause: 'equipment', exercise: 'back_squat', needs: ['barbell', 'pull_up_bar'] }, names))
      .toBe('Back Squat needs barbell, pull up bar')
  })
  it('names the flag that rules a lift out', () => {
    expect(blockerText({ cause: 'injury', exercise: 'back_squat', flags: ['knee_meniscus_post_op'] }, names))
      .toBe('Back Squat is ruled out by Knee (post-op)')
  })
  it('names the level and what it requires', () => {
    expect(blockerText({ cause: 'level', exercise: 'muscle_up', level: 'novice', requires: ['strict_pull_up'] }, names))
      .toBe('muscle up is not unlocked at novice (needs Strict Pull-up)')
  })
})

const empty = (extra: Partial<ExerciseAssignment>) => ({ exercise: null, load: {}, ...extra }) as unknown as ExerciseAssignment

describe('emptySlotText', () => {
  it('is nothing for a filled slot or a structural one', () => {
    expect(emptySlotText({ exercise: { id: 'x' }, load: {} } as unknown as ExerciseAssignment)).toBeNull()
    expect(emptySlotText(empty({ skip_exercise: true }))).toBeNull()
  })
  it('falls back to the older flags on a program stored before blocked_by', () => {
    expect(emptySlotText(empty({ equipment_gap: true }))).toBe('Nothing fits your equipment')
    expect(emptySlotText(empty({ injury_skip: true }))).toBe('Ruled out by an injury flag')
  })
})

describe('sessionNotes and heldBackCounts', () => {
  const session = (extra: Partial<Session>) => ({ modality: 'max_strength', archetype: { id: 'a' }, exercises: [], ...extra }) as unknown as Session
  it('says what a session stands in for, and why', () => {
    expect(sessionNotes(session({ substituted_for: 'max_strength', substitution_cause: 'level' })))
      .toEqual(['In place of max strength (none written for your level)'])
    expect(sessionNotes(session({ equipment_scaled: ['barbell'] }))).toEqual(['Scaled: written for barbell'])
  })
  it('counts empty slots and the sessions they are in', () => {
    const program = { weeks: [{ schedule: {
      Monday: [session({ exercises: [empty({ blocked_by: { cause: 'equipment', needs: ['barbell'] } }), empty({ equipment_gap: true })] })],
      Wednesday: [session({ substituted_for: 'power' })],
      Friday: [session({})],
    } }] } as unknown as GeneratedProgram
    expect(heldBackCounts(program)).toEqual({ slots: 2, sessions: 2 })
  })
})
