import type { ReactNode } from 'react'
import type { ExerciseAssignment, Session } from '@/api/types'
import { WorkoutBlocks } from '@/components/blocks/WorkoutBlocks'
import { blockRows } from '@/lib/blocks'
import { modalityHex } from '@/lib/modalityColors'

/**
 * A session's exercises in their blocks (src/session_blocks.py): a round's
 * movements inside their round, the start and the finisher labelled. The rows
 * are the caller's, so each keeps its logger and its swap.
 */
export function SessionExercises({ session, row }: {
  session: Session
  row: (assignment: ExerciseAssignment, index: number) => ReactNode
}) {
  const rows = blockRows(session)
  if (!rows) return <div className="space-y-2">{session.exercises.map(row)}</div>
  return (
    <WorkoutBlocks
      blocks={session.blocks!}
      accent={modalityHex(session.modality)}
      renderMovement={(m) => {
        const i = rows.get(m.role)!
        return row(session.exercises[i], i)
      }}
    />
  )
}
