import { useMemo, useState } from 'react'
import { useDraggable } from '@dnd-kit/core'
import { GripVertical, Plus, Search } from 'lucide-react'
import type { Exercise } from '@/api/types'
import { useDebounce } from '@/hooks/useDebounce'
import { searchExercises } from '@/lib/sessionBuilder'
import { EX_CATEGORY_COLORS } from '@/lib/exploreColors'
import { useProfileStore } from '@/store/profileStore'
import { Tip } from '@/components/shared/Tip'
import { cn } from '@/lib/utils'

const words = (id: string) => id.replace(/_/g, ' ')

function LibraryCard({ exercise, onAdd }: { exercise: Exercise; onAdd: (exercise: Exercise) => void }) {
  const { attributes, listeners, setNodeRef, setActivatorNodeRef, isDragging } = useDraggable({
    id: `ex|${exercise.id}`, data: { type: 'exercise', exercise },
  })
  return (
    <li ref={setNodeRef} className={cn('flex items-center gap-1 rounded-md border bg-card pr-1', isDragging && 'opacity-40')}>
      <button type="button" ref={setActivatorNodeRef} {...attributes} {...listeners}
        aria-label={`Drag ${exercise.name} into the session`}
        className="flex min-w-0 flex-1 cursor-grab touch-none items-center gap-2 rounded-l-md px-1.5 py-1.5 text-left hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring active:cursor-grabbing">
        <GripVertical className="size-3.5 shrink-0 text-muted-foreground" />
        <span className="size-2 shrink-0 rounded-full" style={{ background: EX_CATEGORY_COLORS[exercise.category] ?? 'currentColor' }} />
        <span className="min-w-0">
          <span className="block truncate text-sm">{exercise.name}</span>
          <span className="block truncate text-xs text-muted-foreground">
            {[...new Set([words(exercise.category), ...((exercise.equipment ?? []) as string[]).filter((e) => e !== 'none').map(words)])].join(' · ')}
          </span>
        </span>
      </button>
      <Tip label={`Add ${exercise.name}`}>
        <button type="button" aria-label={`Add ${exercise.name}`} onClick={() => onAdd(exercise)}
          className="rounded p-1.5 text-muted-foreground hover:bg-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
          <Plus className="size-4" />
        </button>
      </Tip>
    </li>
  )
}

/** The exercises to build from: one search that narrows as it is typed, and filters. */
export function ExerciseLibrary({ exercises, onAdd }: { exercises: Exercise[]; onAdd: (exercise: Exercise) => void }) {
  const [query, setQuery] = useState('')
  const [categories, setCategories] = useState<string[]>([])
  const [ownedOnly, setOwnedOnly] = useState(false)
  const owned = useProfileStore((s) => s.equipment)
  const asked = useDebounce(query, 150)
  const all = useMemo(() => [...new Set(exercises.map((e) => e.category))].sort(), [exercises])
  const results = useMemo(
    () => searchExercises(exercises, { query: asked, categories, equipment: ownedOnly ? owned : null }),
    [exercises, asked, categories, ownedOnly, owned],
  )
  const toggle = (category: string) =>
    setCategories((now) => (now.includes(category) ? now.filter((c) => c !== category) : [...now, category]))
  const chip = (on: boolean) => cn(
    'rounded-full border px-2 py-0.5 text-xs focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
    on ? 'border-primary bg-primary/10 text-foreground' : 'text-muted-foreground hover:text-foreground')

  return (
    <section aria-label="Exercises" className="flex min-h-0 flex-col gap-2">
      <div className="relative">
        <Search className="pointer-events-none absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
        <input type="search" aria-label="Search exercises" value={query} onChange={(e) => setQuery(e.target.value)}
          placeholder="Search exercises…"
          className="h-9 w-full rounded-md border border-input bg-background pl-8 pr-3 text-sm placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring" />
      </div>
      <div className="flex flex-wrap gap-1" role="group" aria-label="Filter by category">
        {all.map((category) => (
          <button key={category} type="button" aria-pressed={categories.includes(category)} onClick={() => toggle(category)}
            className={chip(categories.includes(category))}>{words(category)}</button>
        ))}
        <button type="button" aria-pressed={ownedOnly} onClick={() => setOwnedOnly((v) => !v)} className={chip(ownedOnly)}>
          with my equipment
        </button>
      </div>
      <p className="text-xs text-muted-foreground" role="status">
        {results.length === 0 ? 'No exercise matches.' : `${results.length}${results.length === 60 ? '+' : ''} of ${exercises.length}`}
      </p>
      <ul className="flex min-h-0 flex-1 flex-col gap-1 overflow-y-auto pr-1">
        {results.map((exercise) => <LibraryCard key={exercise.id} exercise={exercise} onAdd={onAdd} />)}
      </ul>
    </section>
  )
}
