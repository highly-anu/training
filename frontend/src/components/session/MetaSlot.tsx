import { cn } from '@/lib/utils'
import type { ExerciseAssignment } from '@/api/types'

interface MetaSlotProps {
  assignment: ExerciseAssignment
}

export function MetaSlot({ assignment }: MetaSlotProps) {
  const role = assignment.slot_role ?? 'info'
  const label = role === 'warm_up' ? 'Warm-Up' : role === 'cool_down' ? 'Cool-Down' : 'Note'

  return (
    <div className="flex items-center gap-3 rounded-md bg-muted/40 px-3 py-2">
      <span className="text-[10px] text-muted-foreground/70 uppercase tracking-wider w-16 shrink-0">
        {label}
      </span>
      <p className={cn('text-xs text-muted-foreground italic')}>
        {assignment.exercise?.name ?? assignment.slot_role?.replace(/_/g, ' ')}
        {assignment.notes && ` — ${assignment.notes}`}
      </p>
    </div>
  )
}
