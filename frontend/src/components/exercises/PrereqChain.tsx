import { ArrowDown } from 'lucide-react'
import { cn } from '@/lib/utils'
import type { Exercise } from '@/api/types'

interface PrereqChainProps {
  exercise: Exercise
  allExercises: Exercise[]
  onSelect: (id: string) => void
}

export function PrereqChain({ exercise, allExercises, onSelect }: PrereqChainProps) {
  const requires = allExercises.filter((e) => exercise.requires.includes(e.id))
  const unlocks = allExercises.filter((e) => exercise.unlocks.includes(e.id))

  if (!requires.length && !unlocks.length) {
    return (
      <p className="text-xs text-muted-foreground">No prerequisite chain found.</p>
    )
  }

  return (
    <div className="flex flex-col items-center gap-1">
      {/* Prerequisites above */}
      {requires.map((req) => (
        <button
          key={req.id}
          onClick={() => onSelect(req.id)}
          className="rounded-full border border-border bg-muted px-3 py-1 text-xs text-muted-foreground hover:border-primary/50 hover:text-foreground transition-colors"
        >
          {req.name}
        </button>
      ))}

      {requires.length > 0 && (
        <ArrowDown className="size-3.5 text-muted-foreground/50" />
      )}

      {/* Current exercise */}
      <div className={cn(
        'rounded-full border-2 border-primary bg-primary/10 px-3 py-1 text-xs font-semibold text-primary'
      )}>
        {exercise.name}
      </div>

      {unlocks.length > 0 && (
        <ArrowDown className="size-3.5 text-muted-foreground/50" />
      )}

      {/* Unlocks below */}
      {unlocks.map((u) => (
        <button
          key={u.id}
          onClick={() => onSelect(u.id)}
          className="rounded-full border border-border bg-muted px-3 py-1 text-xs text-muted-foreground hover:border-primary/50 hover:text-foreground transition-colors"
        >
          {u.name}
        </button>
      ))}
    </div>
  )
}
