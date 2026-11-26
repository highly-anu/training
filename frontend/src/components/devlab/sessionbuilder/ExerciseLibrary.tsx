import { useEffect, useMemo, useRef, useState, type KeyboardEvent } from 'react'
import { useDraggable } from '@dnd-kit/core'
import { GripVertical, Plus, Search, X } from 'lucide-react'
import type { Exercise } from '@/api/types'
import { useDebounce } from '@/hooks/useDebounce'
import { searchExercises } from '@/lib/sessionBuilder'
import { EX_CATEGORY_COLORS } from '@/lib/exploreColors'
import { useProfileStore } from '@/store/profileStore'
import { Tip } from '@/components/shared/Tip'
import { cn } from '@/lib/utils'

const words = (id: string) => id.replace(/_/g, ' ')

/**
 * One exercise of the library. The pointer drags it into a block; a click, Enter
 * or Space adds it. The list is one tab stop: the arrow keys move through it.
 */
function LibraryCard({ exercise, onAdd, current, onKeyDown, onFocus }: {
  exercise: Exercise
  onAdd: (exercise: Exercise) => void
  /** The card Tab lands on. */
  current: boolean
  onKeyDown: (e: KeyboardEvent<HTMLButtonElement>) => void
  onFocus: () => void
}) {
  const { listeners, setNodeRef, setActivatorNodeRef, isDragging } = useDraggable({
    id: `ex|${exercise.id}`, data: { type: 'exercise', exercise },
  })
  // The keyboard adds with Enter; only the pointer drags, so the sensor's own key handler stays off.
  const { onKeyDown: _keyboardDrag, ...pointer } = listeners ?? {}
  void _keyboardDrag
  return (
    <li ref={setNodeRef} className={cn('rounded-md border bg-card', isDragging && 'opacity-40')}>
      <button type="button" ref={setActivatorNodeRef} {...pointer} data-card tabIndex={current ? 0 : -1}
        aria-label={`Add ${exercise.name}`} onClick={() => onAdd(exercise)} onKeyDown={onKeyDown} onFocus={onFocus}
        className="flex w-full min-w-0 cursor-grab touch-none items-center gap-2 rounded-md px-1.5 py-1.5 text-left hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring active:cursor-grabbing">
        <GripVertical className="size-3.5 shrink-0 text-muted-foreground" />
        <span className="size-2 shrink-0 rounded-full" style={{ background: EX_CATEGORY_COLORS[exercise.category] ?? 'currentColor' }} />
        <span className="min-w-0 flex-1">
          <span className="block truncate text-sm">{exercise.name}</span>
          <span className="block truncate text-xs text-muted-foreground">
            {[...new Set([words(exercise.category), ...((exercise.equipment ?? []) as string[]).filter((e) => e !== 'none').map(words)])].join(' · ')}
          </span>
        </span>
        <Plus className="size-4 shrink-0 text-muted-foreground" />
      </button>
    </li>
  )
}

/**
 * The exercises to build from, opened on demand: one search that narrows as it
 * is typed, and filters. Escape (or Close) puts it away.
 */
export function ExerciseLibrary({ id, exercises, onAdd, onClose }: {
  id?: string
  exercises: Exercise[]
  onAdd: (exercise: Exercise) => void
  onClose: () => void
}) {
  const [query, setQuery] = useState('')
  const [categories, setCategories] = useState<string[]>([])
  const [ownedOnly, setOwnedOnly] = useState(false)
  const [current, setCurrent] = useState(0)
  const search = useRef<HTMLInputElement>(null)
  const list = useRef<HTMLUListElement>(null)
  const owned = useProfileStore((s) => s.equipment)
  const asked = useDebounce(query, 150)
  const all = useMemo(() => [...new Set(exercises.map((e) => e.category))].sort(), [exercises])
  const results = useMemo(
    () => searchExercises(exercises, { query: asked, categories, equipment: ownedOnly ? owned : null }),
    [exercises, asked, categories, ownedOnly, owned],
  )
  const at = Math.min(current, Math.max(results.length - 1, 0))
  const toggle = (category: string) =>
    setCategories((now) => (now.includes(category) ? now.filter((c) => c !== category) : [...now, category]))
  const chip = (on: boolean) => cn(
    'rounded-full border px-2 py-0.5 text-xs focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
    on ? 'border-primary bg-primary/10 text-foreground' : 'text-muted-foreground hover:text-foreground')

  // Opened to look something up: the search is where the typing goes.
  useEffect(() => { search.current?.focus() }, [])

  const card = (i: number) => list.current?.querySelectorAll<HTMLButtonElement>('[data-card]')[i]
  function go(i: number) {
    const to = Math.max(0, Math.min(i, results.length - 1))
    setCurrent(to)
    card(to)?.focus()
  }
  function onCardKey(e: KeyboardEvent<HTMLButtonElement>, i: number) {
    if (e.key === 'ArrowDown') { e.preventDefault(); go(i + 1) }
    else if (e.key === 'ArrowUp') { e.preventDefault(); if (i === 0) search.current?.focus(); else go(i - 1) }
    else if (e.key === 'Home') { e.preventDefault(); go(0) }
    else if (e.key === 'End') { e.preventDefault(); go(results.length - 1) }
  }

  return (
    // Escape from any of its controls puts the library away.
    // eslint-disable-next-line jsx-a11y/no-noninteractive-element-interactions
    <section id={id} aria-label="Exercises" className="flex min-h-0 flex-col gap-2"
      onKeyDown={(e) => {
        if (e.key !== 'Escape') return
        e.stopPropagation()
        // In the search, Escape first empties it.
        if (e.target === search.current && query) setQuery('')
        else onClose()
      }}>
      <div className="flex items-center gap-1">
        <div className="relative flex-1">
          <Search className="pointer-events-none absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
          <input ref={search} type="search" aria-label="Search exercises" value={query}
            onChange={(e) => { setQuery(e.target.value); setCurrent(0) }}
            onKeyDown={(e) => { if (e.key === 'ArrowDown' && results.length) { e.preventDefault(); go(at) } }}
            placeholder="Search exercises…"
            className="h-9 w-full rounded-md border border-input bg-background pl-8 pr-3 text-sm placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring" />
        </div>
        <Tip label="Close" keys="Esc">
          <button type="button" aria-label="Close the exercises" onClick={onClose}
            className="rounded p-1.5 text-muted-foreground hover:bg-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
            <X className="size-4" />
          </button>
        </Tip>
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
      <ul ref={list} aria-label="Exercises to add: the arrow keys move, Enter adds"
        className="flex min-h-0 flex-1 flex-col gap-1 overflow-y-auto p-0.5 pr-1">
        {results.map((exercise, i) => (
          <LibraryCard key={exercise.id} exercise={exercise} onAdd={onAdd} current={i === at}
            onKeyDown={(e) => onCardKey(e, i)} onFocus={() => setCurrent(i)} />
        ))}
      </ul>
    </section>
  )
}
