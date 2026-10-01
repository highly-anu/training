import { WorkoutRow, type WorkoutMatchStatus } from './WorkoutRow'
import type { ImportedWorkout } from '@/api/types'

interface WorkoutListProps {
  workouts: ImportedWorkout[]
  statusFor: (workout: ImportedWorkout) => WorkoutMatchStatus
  sessionLabelFor?: (workout: ImportedWorkout) => string | null
  onOpen: (workout: ImportedWorkout) => void
  onMatch?: (workout: ImportedWorkout) => void
  onRemove?: (workout: ImportedWorkout) => void
}

export function WorkoutList({ workouts, statusFor, sessionLabelFor, onOpen, onMatch, onRemove }: WorkoutListProps) {
  return (
    <div className="space-y-2">
      {workouts.map((w) => (
        <WorkoutRow
          key={w.id}
          workout={w}
          status={statusFor(w)}
          sessionLabel={sessionLabelFor?.(w)}
          onOpen={() => onOpen(w)}
          onMatch={onMatch ? () => onMatch(w) : undefined}
          onRemove={onRemove ? () => onRemove(w) : undefined}
        />
      ))}
    </div>
  )
}
