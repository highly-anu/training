import { useEffect, useMemo, useRef, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import {
  DndContext, DragOverlay, KeyboardSensor, MeasuringStrategy, PointerSensor, useSensor, useSensors, type DragEndEvent,
} from '@dnd-kit/core'
import { FilePlus2, Library } from 'lucide-react'
import type { Exercise } from '@/api/types'
import { useExercises } from '@/api/exercises'
import { useModalities } from '@/api/modalities'
import { manualRefusal, useManualPreview, useManualSessions, useSaveManualSession } from '@/api/manual'
import { useDebounce } from '@/hooks/useDebounce'
import { pointerFirst } from '@/lib/dndCollision'
import { dropTargetCoordinates } from '@/lib/dndKeyboard'
import { MODALITY_IDS, EQUIPMENT_LABELS } from '@/lib/gen/clientVocab'
import { modalityHex, modalityLabel } from '@/lib/modalityColors'
import {
  addExercise, blockFor, duplicateOf, emptyBlock, fromWire, insertBlock, isBlank, moveBlock, nudgeBlock, nudgeMovement,
  removeBlock, removeMovement, sessionProblems, setKind, suggestModality, toWire, updateBlock, updateMovement,
  STAGES, type BlockStage, type BuilderProblem, type DraftBlock, type DraftSession,
} from '@/lib/sessionBuilder'
import { useSessionBuilderStore } from '@/store/sessionBuilderStore'
import { Button } from '@/components/ui/button'
import { WorkoutBlocks } from '@/components/blocks/WorkoutBlocks'
import { FailedState, LoadingState } from '@/components/shared/states'
import { ConfirmDialog } from '@/components/shared/ConfirmDialog'
import { Tip } from '@/components/shared/Tip'
import { announce } from '@/lib/announce'
import { cn } from '@/lib/utils'
import { BuilderCanvas } from './BuilderCanvas'
import type { BlockActions } from './BlockEditor'
import { ExerciseLibrary } from './ExerciseLibrary'
import { NoteField } from './NoteField'
import { SavedSessions } from './SavedSessions'

const field = 'h-9 rounded-md border border-input bg-background px-2 text-sm placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring'

/** Where the focus goes after an edit, so the keyboard never loses its place. */
type Focus =
  | { movement: string }
  | { block: string; at: 'add' | 'part' | 'menu' }
  | { at: 'first' }

function focusTarget(root: HTMLElement, want: Focus): HTMLElement | null {
  const first = () => root.querySelector<HTMLElement>('[data-canvas] input, [data-canvas] select')
  if ('movement' in want) {
    const row = root.querySelector<HTMLElement>(`[data-movement="${want.movement}"]`)
    const block = row?.closest<HTMLElement>('[data-block]')
    // A movement with no numbers of its own (a timed piece, a practice): the block's.
    return row?.querySelector<HTMLElement>('input') ?? block?.querySelector<HTMLElement>('input:not([role="combobox"])')
      ?? block?.querySelector<HTMLElement>('input') ?? first()
  }
  if ('block' in want) {
    const block = root.querySelector<HTMLElement>(`[data-block="${want.block}"]`)
    if (!block) return first()
    const menu = block.querySelector<HTMLElement>('[data-focus="menu"]')
    if (want.at === 'add') return block.querySelector<HTMLElement>('input[role="combobox"]') ?? menu
    return block.querySelector<HTMLElement>(`[data-focus="${want.at}"]`) ?? menu
  }
  return first()
}

const partLabel = (stage: BlockStage) => STAGES.find((s) => s.id === stage)?.label ?? stage

/**
 * Dev Lab ▸ Session builder (docs/roadmap.md item 24): compose a session from
 * existing exercises — search or drag them in, arrange them in blocks, set
 * their numbers and how they move — see it as the app will draw it, save it,
 * and put it on a day. The server reads the draft; nothing here words a
 * prescription.
 *
 * The screen starts as a name and one exercise field; the library, the notes
 * and the next block are asked for. Tab runs in the order of the work (name,
 * kind, blocks, Add block, Save) and after every edit the focus is put on what
 * comes next (`Focus`); ⌘/Ctrl+Enter saves from anywhere.
 */
export function SessionBuilderPanel() {
  const exercisesQuery = useExercises()
  const { data: modalities } = useModalities()
  const saved = useManualSessions()
  const save = useSaveManualSession()
  const { draft, dirty, edit, open, saved: markSaved, reset } = useSessionBuilderStore()
  const [dragging, setDragging] = useState<{ title: string } | null>(null)
  const [refused, setRefused] = useState<{ problems: BuilderProblem[]; message: string } | null>(null)
  const [replacing, setReplacing] = useState<(() => void) | null>(null)
  const [libraryOpen, setLibraryOpen] = useState(false)
  const root = useRef<HTMLDivElement>(null)
  const browse = useRef<HTMLButtonElement>(null)
  const wanted = useRef<Focus | null>(null)
  const focused = useRef<{ el: HTMLElement; at: number } | null>(null)
  const [focusTick, setFocusTick] = useState(0)

  // After the edit is drawn, the focus goes where the work continues.
  useEffect(() => {
    const want = wanted.current
    wanted.current = null
    const el = want && root.current ? focusTarget(root.current, want) : null
    if (!el) return
    el.focus()
    if (el instanceof HTMLInputElement && el.getAttribute('role') !== 'combobox') el.select()
    focused.current = { el, at: Date.now() }
  }, [focusTick])
  const focusOn = (want: Focus) => { wanted.current = want; setFocusTick((t) => t + 1) }
  /** A menu gives the focus back to its button as it closes; an action that just moved it keeps it. */
  const onMenuClosed = (e: Event) => {
    const last = focused.current
    if (!last || Date.now() - last.at > 1000 || !last.el.isConnected) return
    e.preventDefault()
    last.el.focus()
  }

  const exercises = useMemo(() => exercisesQuery.data ?? [], [exercisesQuery.data])

  // `/dev?tab=session&edit=<id>` opens a saved session, once, when nothing unsaved is in the way.
  const [params, setParams] = useSearchParams()
  const linked = params.get('edit')
  useEffect(() => {
    if (!linked || !saved.data) return
    const session = saved.data.sessions.find((s) => s.id === linked)
    const now = useSessionBuilderStore.getState()
    if (session && now.draft.id !== linked && !(now.dirty && !isBlank(now.draft))) now.open(fromWire(session))
    params.delete('edit')
    setParams(params, { replace: true })
  }, [linked, saved.data, params, setParams])
  const catalog = useMemo(() => Object.fromEntries(exercises.map((e) => [e.id, e])) as Record<string, Exercise>, [exercises])
  const suggested = suggestModality(draft, catalog)
  const modality = draft.modality || suggested || ''
  const wire = useMemo(() => ({ ...toWire(draft), modality }), [draft, modality])
  const asked = useDebounce(wire, 350)
  const blank = isBlank(draft)
  const preview = useManualPreview(asked, !isBlank(fromWire(asked)))
  const shown = blank ? null : preview.data ?? null
  // While the draft is unsaved the server's reading is the truth; a refused save adds the gate's.
  const problems: BuilderProblem[] = [...(shown?.problems ?? []), ...(refused?.problems ?? [])]
    .filter((p, i, all) => all.findIndex((q) => q.message === p.message && q.block === p.block && q.movement === p.movement) === i)

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 4 } }),
    useSensor(KeyboardSensor, { coordinateGetter: dropTargetCoordinates }),
  )

  const change: typeof edit = (fn) => { setRefused(null); edit(fn) }
  const now = (): DraftSession => useSessionBuilderStore.getState().draft
  const addToMain = (exercise: Exercise) => {
    const block = blockFor(exercise, 'main')
    change((d) => insertBlock(d, block, 'main'))
    announce(`${exercise.name} added.`)
    return block
  }
  const addBlock = (kind: Parameters<typeof emptyBlock>[0]) => {
    const block = emptyBlock(kind, 'main')
    change((d) => insertBlock(d, block, 'main'))
    announce('Block added. Type its exercise.')
    focusOn({ block: block.uid, at: 'add' })
  }
  const closeLibrary = () => { setLibraryOpen(false); browse.current?.focus() }

  function actionsFor(block: DraftBlock): BlockActions {
    const id = block.uid
    return {
      update: (patch) => change((d) => updateBlock(d, id, patch)),
      setKind: (kind) => change((d) => setKind(d, id, kind, catalog)),
      remove: () => {
        const at = now().blocks.findIndex((b) => b.uid === id)
        change((d) => removeBlock(d, id))
        const left = now().blocks
        const near = left[Math.max(0, at - 1)]
        announce('Block deleted.')
        focusOn(near ? { block: near.uid, at: 'add' } : { at: 'first' })
      },
      nudge: (by) => {
        change((d) => nudgeBlock(d, id, by))
        announce(by < 0 ? 'Moved earlier.' : 'Moved later.')
        focusOn({ block: id, at: 'menu' })
      },
      toStage: (stage: BlockStage) => {
        change((d) => moveBlock(d, id, stage))
        announce(`Now in ${partLabel(stage)}.`)
        focusOn({ block: id, at: 'part' })
      },
      addExercise: (exercise) => {
        const before = new Set(now().blocks.flatMap((b) => b.movements.map((m) => m.uid)))
        change((d) => addExercise(d, id, exercise))
        const added = now().blocks.flatMap((b) => b.movements).find((m) => !before.has(m.uid))
        if (added) focusOn({ movement: added.uid })
      },
      updateMovement: (uid, patch) => change((d) => updateMovement(d, id, uid, patch)),
      replaceMovement: (uid, movement) => change((d) => updateBlock(d, id, {
        movements: (d.blocks.find((b) => b.uid === id)?.movements ?? []).map((m) => (m.uid === uid ? movement : m)),
      })),
      removeMovement: (uid) => {
        change((d) => removeMovement(d, id, uid))
        focusOn({ block: id, at: 'add' })
      },
      nudgeMovement: (uid, by) => change((d) => nudgeMovement(d, id, uid, by)),
    }
  }

  function onDragEnd(e: DragEndEvent) {
    setDragging(null)
    const from = e.active.data.current as { type: 'exercise'; exercise: Exercise } | { type: 'block'; uid: string } | undefined
    const to = e.over?.data.current as { type: 'gap'; stage: BlockStage; at: number } | { type: 'block'; uid: string } | undefined
    if (!from || !to) return
    if (from.type === 'exercise' && to.type === 'gap') change((d) => insertBlock(d, blockFor(from.exercise, to.stage), to.stage, to.at))
    else if (from.type === 'exercise' && to.type === 'block') change((d) => addExercise(d, to.uid, from.exercise))
    else if (from.type === 'block' && to.type === 'gap') {
      change((d) => {
        // The gap counts the stage as drawn, the dragged block included.
        const inStage = d.blocks.filter((b) => b.stage === to.stage)
        const own = inStage.findIndex((b) => b.uid === from.uid)
        return moveBlock(d, from.uid, to.stage, own >= 0 && own < to.at ? to.at - 1 : to.at)
      })
    }
  }

  /** Open another session in the builder, asking first when this one has unsaved work. */
  const replaceDraft = (next: () => void) => (dirty && !blank ? setReplacing(() => next) : next())

  function saveNow() {
    setRefused(null)
    save.mutate(wire, {
      onSuccess: ({ session }) => { markSaved(fromWire(session)); announce(`${session.name} saved.`) },
      onError: (e) => setRefused(manualRefusal(e)),
    })
  }

  if (exercisesQuery.isLoading) return <div className="p-6"><LoadingState shape="list" label="Loading exercises" /></div>
  if (exercisesQuery.isError) {
    return <div className="p-6"><FailedState title="Could not load the exercises" error={exercisesQuery.error} onRetry={() => exercisesQuery.refetch()} /></div>
  }

  const modalityIds = [...new Set([...(modalities ?? []).map((m) => m.id as string), ...MODALITY_IDS])]
  const titleOf = (data: unknown) => (data as { title?: string; exercise?: Exercise } | undefined)?.exercise?.name
    ?? (data as { title?: string } | undefined)?.title ?? 'item'

  return (
    <DndContext
      sensors={sensors}
      collisionDetection={pointerFirst}
      // Drop targets are measured all through a drag: the page moves under it (gaps open, a problem line appears).
      measuring={{ droppable: { strategy: MeasuringStrategy.Always } }}
      onDragStart={(e) => setDragging({ title: titleOf(e.active.data.current) })}
      onDragEnd={onDragEnd}
      onDragCancel={() => setDragging(null)}
      accessibility={{
        screenReaderInstructions: {
          draggable: 'To place this, press Space or Enter, choose where with the arrow keys, and press Space to drop it. Escape puts it back.',
        },
        announcements: {
          onDragStart: ({ active }) => `Picked up ${titleOf(active.data.current)}.`,
          onDragOver: ({ active, over }) => (over ? `${titleOf(active.data.current)}: ${titleOf(over.data.current)}.` : undefined),
          onDragEnd: ({ active, over }) => (over ? `${titleOf(active.data.current)} dropped ${titleOf(over.data.current)}.`
            : `${titleOf(active.data.current)} was not moved.`),
          onDragCancel: ({ active }) => `Cancelled. ${titleOf(active.data.current)} was not moved.`,
        },
      }}
    >
      {/* ⌘/Ctrl+Enter saves from any field of the builder: the keys of its controls, heard here. */}
      {/* eslint-disable-next-line jsx-a11y/no-static-element-interactions */}
      <div ref={root}
        onKeyDown={(e) => {
          if (e.key !== 'Enter' || !(e.metaKey || e.ctrlKey) || blank || save.isPending) return
          e.preventDefault()
          saveNow()
        }}
        className={cn('grid gap-6 p-6', libraryOpen ? 'lg:grid-cols-[18rem_minmax(0,1fr)] xl:grid-cols-[18rem_minmax(0,1fr)_22rem]'
          : 'xl:grid-cols-[minmax(0,1fr)_22rem]')}>
        {libraryOpen && (
          <aside className="flex max-h-[calc(100vh-10rem)] flex-col gap-4 lg:sticky lg:top-0">
            <ExerciseLibrary id="session-builder-library" exercises={exercises} onAdd={addToMain} onClose={closeLibrary} />
          </aside>
        )}

        <div className="flex min-w-0 flex-col gap-4">
          <div className="flex flex-wrap items-end gap-2">
            <label className="flex min-w-48 flex-1 flex-col gap-1">
              <span className="text-xs text-muted-foreground">Session name</span>
              <input value={draft.name} onChange={(e) => change((d) => ({ ...d, name: e.target.value }))}
                // Enter is "next": on to the exercises.
                onKeyDown={(e) => { if (e.key === 'Enter' && !e.metaKey && !e.ctrlKey) { e.preventDefault(); focusOn({ at: 'first' }) } }}
                placeholder="Squat day" aria-invalid={problems.some((p) => p.field === 'name') || undefined} className={field} />
            </label>
            <label className="flex w-52 flex-col gap-1">
              <span className="text-xs text-muted-foreground">Kind of training</span>
              <span className="flex items-center gap-2">
                <span className="size-3 shrink-0 rounded-full" style={{ background: modality ? modalityHex(modality) : 'transparent' }} />
                <select value={modality} onChange={(e) => change((d) => ({ ...d, modality: e.target.value }))} className={`${field} min-w-0 flex-1`}>
                  <option value="">Choose…</option>
                  {modalityIds.map((id) => <option key={id} value={id}>{modalityLabel(id)}</option>)}
                </select>
              </span>
            </label>
            <Button ref={browse} variant="outline" aria-expanded={libraryOpen} aria-controls="session-builder-library"
              onClick={() => (libraryOpen ? closeLibrary() : setLibraryOpen(true))}>
              <Library className="size-4" /> Browse exercises
            </Button>
          </div>
          {!draft.modality && suggested && (
            <p className="text-xs text-muted-foreground">Read as {modalityLabel(suggested)} from its exercises. Choose another if it is not.</p>
          )}
          <NoteField label="Notes for the whole session" addLabel="Add a session note" value={draft.notes ?? ''}
            onChange={(notes) => change((d) => ({ ...d, notes }))} />
          {refused && refused.problems.length === 0 && <p role="alert" className="text-sm text-bad">{refused.message}</p>}
          {!blank && sessionProblems(problems).map((p) => <p key={p.message} role="alert" className="text-sm text-bad">{p.message}</p>)}

          <BuilderCanvas draft={draft} exercises={exercises} catalog={catalog} problems={blank ? [] : problems} dragging={dragging !== null}
            actionsFor={actionsFor} onAddBlock={addBlock} onMenuClosed={onMenuClosed}
            onFirstExercise={(exercise) => focusOn({ movement: addToMain(exercise).movements[0].uid })} />

          <div className="flex flex-wrap justify-end gap-2 border-t pt-4">
            <Button variant="outline" onClick={() => replaceDraft(reset)}><FilePlus2 className="size-4" /> New</Button>
            <Tip label={draft.id ? 'Save changes' : 'Save session'} keys="⌘ ↵">
              <Button onClick={saveNow} loading={save.isPending} disabled={blank}>{draft.id ? 'Save changes' : 'Save session'}</Button>
            </Tip>
          </div>
        </div>

        <aside className={cn('flex flex-col gap-6', libraryOpen && 'lg:col-span-2 xl:col-span-1')}>
          <section aria-label="Preview" className="flex flex-col gap-3">
            <h3 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">As it will be shown</h3>
            {blank && <p className="text-sm text-muted-foreground">Add an exercise and the session appears here as the app draws it.</p>}
            {!blank && preview.isError && <FailedState size="compact" title="Could not read the draft" error={preview.error} onRetry={() => preview.refetch()} />}
            {shown?.session && (
              <>
                <p className="text-sm text-muted-foreground">
                  About {shown.session.minutes} min
                  {shown.session.equipment.length > 0 && ` · ${shown.session.equipment.map((e) => EQUIPMENT_LABELS[e as keyof typeof EQUIPMENT_LABELS] ?? e).join(', ')}`}
                </p>
                <WorkoutBlocks blocks={shown.session.preview} accent={modalityHex(modality)} />
                {shown.session.forecast.length > 0 && (
                  <div className="flex flex-col gap-2">
                    <h4 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Week by week</h4>
                    {shown.session.forecast.map((f) => (
                      <div key={f.role} className="text-sm">
                        <div className="font-medium">{f.exercise}</div>
                        <ol className="text-muted-foreground">
                          {f.weeks.map((line, i) => <li key={i} className="tabular-nums">Week {i + 1}: {line ?? 'as written'}</li>)}
                        </ol>
                      </div>
                    ))}
                  </div>
                )}
              </>
            )}
            {shown && !shown.ok && <p className="text-sm text-muted-foreground">The preview follows once the marked blocks are complete.</p>}
          </section>

          <section aria-label="Saved sessions" className="flex flex-col gap-2">
            <h3 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Saved sessions</h3>
            {saved.isLoading && <LoadingState shape="list" count={2} label="Loading your sessions" />}
            {saved.isError && <FailedState size="compact" title="Could not load your sessions" error={saved.error} onRetry={() => saved.refetch()} />}
            {saved.data && (
              <SavedSessions sessions={saved.data.sessions} currentId={draft.id}
                onEdit={(s) => replaceDraft(() => open(fromWire(s)))}
                onDuplicate={(s) => replaceDraft(() => open(duplicateOf(s)))}
                onDeleted={(id) => { if (draft.id === id) reset() }} />
            )}
          </section>
        </aside>
      </div>
      <DragOverlay dropAnimation={null}>
        {dragging && <div className="rounded-md border bg-card px-3 py-2 text-sm shadow-xl ring-2 ring-primary/40">{dragging.title}</div>}
      </DragOverlay>
      <ConfirmDialog
        open={replacing !== null}
        onOpenChange={(o) => { if (!o) setReplacing(null) }}
        title="Leave this session unsaved?"
        description="What you changed since the last save is lost."
        confirmLabel="Leave it"
        destructive
        onConfirm={() => { replacing?.(); setReplacing(null) }}
      />
    </DndContext>
  )
}
