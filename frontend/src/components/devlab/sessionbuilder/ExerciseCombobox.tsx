import { useId, useMemo, useState } from 'react'
import { Search } from 'lucide-react'
import type { Exercise } from '@/api/types'
import { searchExercises } from '@/lib/sessionBuilder'
import { cn } from '@/lib/utils'

/**
 * Type to find an exercise: the suggestions narrow with every key, the arrow
 * keys move through them, Enter takes one, Escape closes.
 */
export function ExerciseCombobox({ exercises, onPick, label, placeholder = 'Add an exercise…', className }: {
  exercises: Exercise[]
  onPick: (exercise: Exercise) => void
  label: string
  placeholder?: string
  className?: string
}) {
  const listId = useId()
  const [query, setQuery] = useState('')
  const [open, setOpen] = useState(false)
  const [active, setActive] = useState(0)
  const results = useMemo(
    () => (query.trim() ? searchExercises(exercises, { query, categories: [] }, 8) : []),
    [exercises, query],
  )
  const shown = open && results.length > 0
  const at = Math.min(active, results.length - 1)

  function pick(exercise: Exercise) {
    onPick(exercise)
    setQuery('')
    setOpen(false)
    setActive(0)
  }

  return (
    <div className={cn('relative', className)}>
      <Search className="pointer-events-none absolute left-2.5 top-1/2 size-3.5 -translate-y-1/2 text-muted-foreground" />
      <input
        role="combobox"
        aria-label={label}
        aria-expanded={shown}
        aria-controls={listId}
        aria-autocomplete="list"
        aria-activedescendant={shown ? `${listId}-${at}` : undefined}
        value={query}
        placeholder={placeholder}
        onChange={(e) => { setQuery(e.target.value); setOpen(true); setActive(0) }}
        onFocus={() => setOpen(true)}
        onBlur={() => setOpen(false)}
        onKeyDown={(e) => {
          if (e.key === 'ArrowDown') { e.preventDefault(); setOpen(true); setActive(Math.min(at + 1, results.length - 1)) }
          else if (e.key === 'ArrowUp') { e.preventDefault(); setActive(Math.max(at - 1, 0)) }
          else if (e.key === 'Enter' && shown) { e.preventDefault(); pick(results[at]) }
          else if (e.key === 'Escape' && open) { e.stopPropagation(); setOpen(false) }
        }}
        className="h-9 w-full rounded-md border border-input bg-background pl-8 pr-3 text-sm placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
      />
      {shown && (
        <ul id={listId} role="listbox" aria-label={`${label}: suggestions`}
          className="absolute z-20 mt-1 max-h-64 w-full overflow-y-auto rounded-md border bg-popover p-1 shadow-md">
          {results.map((exercise, i) => (
            <li key={exercise.id} id={`${listId}-${i}`} role="option" aria-selected={i === at}
              // Before the input's blur, so the pick is not lost with the list.
              onMouseDown={(e) => { e.preventDefault(); pick(exercise) }}
              onMouseEnter={() => setActive(i)}
              className={cn('flex cursor-pointer items-baseline justify-between gap-3 rounded px-2 py-1.5 text-sm',
                i === at && 'bg-accent text-accent-foreground')}>
              <span className="truncate">{exercise.name}</span>
              <span className="shrink-0 text-xs text-muted-foreground">{exercise.category.replace(/_/g, ' ')}</span>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
