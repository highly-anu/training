import type { ExerciseAssignment, GeneratedProgram, Session } from '@/api/types'

/**
 * Index-addressed edits to a program's weeks, shared by the active program
 * (programStore, which then saves) and the preview's draft (previewStore,
 * which does not). Each returns a new program, or the same one when the
 * address names nothing.
 */

export function withSessionReplaced(
  program: GeneratedProgram, weekIndex: number, day: string, sessionIndex: number, newSession: Session,
): GeneratedProgram {
  const weeks = program.weeks.map((week, i) => {
    if (i !== weekIndex) return week
    const sessions = [...(week.schedule[day] ?? [])]
    if (sessionIndex < 0 || sessionIndex >= sessions.length) return week
    sessions[sessionIndex] = newSession
    return { ...week, schedule: { ...week.schedule, [day]: sessions } }
  })
  return { ...program, weeks }
}

export function withExerciseReplaced(
  program: GeneratedProgram, weekIndex: number, day: string, sessionIndex: number,
  exerciseIndex: number, assignment: ExerciseAssignment,
): GeneratedProgram {
  const weeks = program.weeks.map((week, i) => {
    if (i !== weekIndex) return week
    const sessions = [...(week.schedule[day] ?? [])]
    const session = sessions[sessionIndex]
    if (!session || exerciseIndex < 0 || exerciseIndex >= session.exercises.length) return week
    const exercises = [...session.exercises]
    exercises[exerciseIndex] = assignment
    sessions[sessionIndex] = { ...session, exercises }
    return { ...week, schedule: { ...week.schedule, [day]: sessions } }
  })
  return { ...program, weeks }
}
