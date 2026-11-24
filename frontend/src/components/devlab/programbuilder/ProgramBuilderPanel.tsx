import { useEffect, useMemo, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import {
  DndContext, DragOverlay, KeyboardSensor, PointerSensor, useSensor, useSensors, type DragEndEvent,
} from '@dnd-kit/core'
import { differenceInCalendarDays, format, parseISO } from 'date-fns'
import { ChevronLeft, ChevronRight, Copy, FilePlus2, Pencil, Plus, Trash2 } from 'lucide-react'
import {
  trackRefusal, useDeleteManualTrack, useManualSessions, useManualTrackPreview, useManualTracks, useSaveManualTrack,
  type DescribedTrack,
} from '@/api/manual'
import { useGenerateDraft, type GenerateParams } from '@/api/programs'
import type { AthleteConstraints, PhaseKind } from '@/api/types'
import { useDebounce } from '@/hooks/useDebounce'
import { useRegeneratePreview } from '@/hooks/useRegeneratePreview'
import { dropTargetCoordinates } from '@/lib/dndKeyboard'
import { EQUIPMENT_LABELS } from '@/lib/gen/clientVocab'
import { PHASE_COLORS } from '@/lib/phaseColors'
import {
  addPhase, addWeek, clearWeek, duplicateOf, duplicateWeek, fromWire, isBlank, lighterWeeks, moveSession, nudgePhase,
  phaseStarts, placeSession, placedSessions, problemsAt, removePhase, removeSession, removeWeek, repeatLine, toWire,
  toggleLight, totalWeeks, trackProblems, updatePhase, type Cell, type TrackProblem,
} from '@/lib/programBuilder'
import { regenerateSource, tailResume } from '@/lib/programSource'
import { usePreviewStore } from '@/store/previewStore'
import { useProfileStore } from '@/store/profileStore'
import { useProgramBuilderStore } from '@/store/programBuilderStore'
import { useProgramStore } from '@/store/programStore'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { NumberField } from '@/components/ui/number-field'
import { ConfirmDialog } from '@/components/shared/ConfirmDialog'
import { FailedState, LoadingState } from '@/components/shared/states'
import { Tip } from '@/components/shared/Tip'
import { announce } from '@/lib/announce'
import { toast } from '@/lib/toast'
import { cn } from '@/lib/utils'
import { SessionShelf } from './SessionShelf'
import { WeekGrid, type GridActions } from './WeekGrid'

const field = 'h-9 rounded-md border border-input bg-background px-2 text-sm placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring'
const iconButton = 'rounded p-1.5 text-muted-foreground hover:bg-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-30'
const BACK = '/dev?tab=program'

/** Start date and length, then the existing Program ▸ Preview. */
function StartDialog({ track, packageId, onClose }: { track: DescribedTrack; packageId: string; onClose: () => void }) {
  const navigate = useNavigate()
  const generate = useGenerateDraft()
  const profile = useProfileStore()
  const today = format(new Date(), 'yyyy-MM-dd')
  const [startDate, setStartDate] = useState(today)
  const [weeks, setWeeks] = useState<number | undefined>(track.totalWeeks)
  const [failed, setFailed] = useState<string | null>(null)
  const missing = track.equipment.filter((e) => e !== 'open_space' && !(profile.equipment as string[]).includes(e))

  function preview() {
    setFailed(null)
    const constraints = {
      equipment: profile.equipment, training_level: profile.trainingLevel, injury_flags: profile.injuryFlags,
      avoid_movements: [], periodization_week: 1, fatigue_state: 'normal',
      // The server's: what builds the weeks as they were laid.
      ...track.startWith,
    } as AthleteConstraints
    const params: GenerateParams = {
      philosophyId: packageId, trackId: track.id, numWeeks: weeks ?? track.totalWeeks, startDate, constraints,
      customInjuryFlags: profile.customInjuryFlags,
    }
    generate.mutate(params, {
      onSuccess: (draft) => {
        if (!draft?.validation) return setFailed('The program could not be built. Try again.')
        usePreviewStore.getState().open('new', params, draft)
        navigate(`/program/preview?back=${encodeURIComponent(`${BACK}&track=${track.id}`)}`)
      },
      onError: (e) => setFailed((e as Error).message || 'The program could not be built. Try again.'),
    })
  }

  return (
    <Dialog open onOpenChange={(open) => { if (!open) onClose() }}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Preview “{track.name}”</DialogTitle>
          <DialogDescription>
            The program is built on the days you laid it on and opens as a draft. Nothing is saved until you start it there.
          </DialogDescription>
        </DialogHeader>
        <div className="flex flex-wrap items-end gap-3">
          <label className="flex flex-col gap-1 text-sm">
            <span className="text-xs text-muted-foreground">Starts the week of</span>
            <input type="date" value={startDate} onChange={(e) => setStartDate(e.target.value)} className={field} />
          </label>
          <NumberField label="Weeks" value={weeks} min={1} max={52} onChange={setWeeks} className="w-28" />
        </div>
        {weeks !== undefined && weeks > track.totalWeeks && (
          <p className="text-sm text-muted-foreground">Past week {track.totalWeeks} the last phase carries on.</p>
        )}
        {missing.length > 0 && (
          <p className="text-sm text-warn">
            Your profile has no {missing.map((e) => EQUIPMENT_LABELS[e as keyof typeof EQUIPMENT_LABELS] ?? e).join(', ')}:
            {' '}a day that needs it is left out. The preview's Held back says which.
          </p>
        )}
        {failed && <p role="alert" className="text-sm text-bad">{failed}</p>}
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button onClick={preview} loading={generate.isPending}>Preview program</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

/** The active program runs on this track: the rest of it can be rebuilt from today. */
function RunningNote({ track }: { track: DescribedTrack }) {
  const program = useProgramStore((s) => s.currentProgram)
  const startDate = useProgramStore((s) => s.programStartDate)
  const sourceGoalIds = useProgramStore((s) => s.sourceGoalIds)
  const sourceGoalWeights = useProgramStore((s) => s.sourceGoalWeights)
  const customInjuryFlags = useProfileStore((s) => s.customInjuryFlags)
  const regenerate = useRegeneratePreview()
  if (!program || !startDate || !program.weeks.some((w) => w.framework === track.frameworkId)) return null
  const days = differenceInCalendarDays(new Date(), parseISO(startDate))
  const startIdx = Math.max(0, Math.min(Math.floor(days / 7), program.weeks.length - 1))
  const remaining = program.weeks.length - startIdx

  function rebuild() {
    if (!program) return
    const resume = tailResume(program, startIdx)
    const params: GenerateParams = {
      ...regenerateSource(sourceGoalIds.filter((id) => id !== '_blended'), sourceGoalWeights, program),
      trackId: resume.trackId, startPhaseId: resume.startPhaseId, constraints: resume.constraints,
      numWeeks: remaining, weekInProgram: startIdx + 1, customInjuryFlags,
      keepBefore: format(new Date(), 'yyyy-MM-dd'),
    }
    regenerate.open(params, startIdx)
  }

  return (
    <div className="flex flex-wrap items-center justify-between gap-2 rounded-md border bg-muted/40 px-3 py-2 text-sm">
      <span>Your program runs on this. It keeps the sessions it was built with until you rebuild the weeks ahead.</span>
      <Button variant="outline" size="sm" onClick={rebuild} loading={regenerate.isPending}>Preview changes from today</Button>
    </div>
  )
}

/**
 * Dev Lab ▸ Program builder (docs/roadmap.md item 24.4): lay the saved
 * sessions on the days of a week, the weeks into phases, see what the server
 * reads of it, save, and open it in Program ▸ Preview.
 */
export function ProgramBuilderPanel() {
  const sessionsQuery = useManualSessions()
  const tracksQuery = useManualTracks()
  const save = useSaveManualTrack()
  const remove = useDeleteManualTrack()
  const { draft, phaseUid, dirty, edit, selectPhase, open, reset } = useProgramBuilderStore()
  const [dragging, setDragging] = useState<{ sessionId: string; title: string } | null>(null)
  const [refused, setRefused] = useState<{ problems: TrackProblem[]; message: string } | null>(null)
  const [replacing, setReplacing] = useState<(() => void) | null>(null)
  const [deleting, setDeleting] = useState<DescribedTrack | null>(null)
  const [starting, setStarting] = useState<DescribedTrack | null>(null)

  const sessions = useMemo(() => sessionsQuery.data?.sessions ?? [], [sessionsQuery.data])
  const limits = tracksQuery.data?.limits ?? { tracks: 6, phases: 8, templateWeeks: 8, daySessions: 2, phaseWeeks: 52 }
  const kinds = tracksQuery.data?.kinds ?? []

  // `/dev?tab=program&track=<id>` opens a saved program, once, when nothing unsaved is in the way.
  const [params, setParams] = useSearchParams()
  const linked = params.get('track')
  useEffect(() => {
    if (!linked || !tracksQuery.data) return
    const track = tracksQuery.data.tracks.find((t) => t.id === linked)
    const now = useProgramBuilderStore.getState()
    if (track && now.draft.id !== linked && !(now.dirty && !isBlank(now.draft))) now.open(fromWire(track))
    params.delete('track')
    setParams(params, { replace: true })
  }, [linked, tracksQuery.data, params, setParams])

  const phaseIndex = Math.max(0, draft.phases.findIndex((p) => p.uid === phaseUid))
  const phase = draft.phases[phaseIndex]
  const wire = useMemo(() => toWire(draft), [draft])
  const asked = useDebounce(wire, 350)
  const blank = isBlank(draft)
  const preview = useManualTrackPreview(asked, !isBlank(asked))
  const shown = blank ? null : preview.data ?? null
  const problems: TrackProblem[] = [...(shown?.problems ?? []), ...(refused?.problems ?? [])]
    .filter((p, i, all) => all.findIndex((q) => q.message === p.message && q.phase === p.phase && q.week === p.week && q.day === p.day) === i)
  const savedTrack = tracksQuery.data?.tracks.find((t) => t.id === draft.id)
  const starts = phaseStarts(draft)

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 4 } }),
    useSensor(KeyboardSensor, { coordinateGetter: dropTargetCoordinates }),
  )
  const change: typeof edit = (fn) => { setRefused(null); edit(fn) }

  const actions: GridActions = {
    place: (cell, sessionId) => change((d) => placeSession(d, phase.uid, cell, sessionId)),
    remove: (cell, index) => change((d) => removeSession(d, phase.uid, cell, index)),
    move: (from, index, to) => change((d) => moveSession(d, phase.uid, from, index, to)),
    toggleLight: (cell) => change((d) => toggleLight(d, phase.uid, cell)),
    duplicateWeek: (week) => change((d) => duplicateWeek(d, phase.uid, week, limits.templateWeeks)),
    clearWeek: (week) => change((d) => clearWeek(d, phase.uid, week)),
    removeWeek: (week) => change((d) => removeWeek(d, phase.uid, week)),
  }

  function onDragEnd(e: DragEndEvent) {
    setDragging(null)
    const from = e.active.data.current as { type: 'session'; sessionId: string } | { type: 'placed'; from: Cell; index: number } | undefined
    const to = e.over?.data.current as { type: 'cell'; cell: Cell } | undefined
    if (!from || !to || !phase) return
    if (from.type === 'session') actions.place(to.cell, from.sessionId)
    else actions.move(from.from, from.index, to.cell)
  }

  const replaceDraft = (next: () => void) => (dirty && !blank ? setReplacing(() => next) : next())

  function saveNow() {
    setRefused(null)
    save.mutate(wire, {
      onSuccess: ({ track }) => { open(fromWire(track)); announce(`${track.name} saved.`) },
      onError: (e) => setRefused(trackRefusal(e)),
    })
  }

  if (sessionsQuery.isLoading || tracksQuery.isLoading) return <div className="p-6"><LoadingState shape="grid" label="Loading your sessions and programs" /></div>
  if (sessionsQuery.isError || tracksQuery.isError) {
    return (
      <div className="p-6">
        <FailedState title="Could not load your sessions and programs" error={sessionsQuery.error ?? tracksQuery.error}
          onRetry={() => { void sessionsQuery.refetch(); void tracksQuery.refetch() }} />
      </div>
    )
  }

  const titleOf = (data: unknown) => (data as { title?: string } | undefined)?.title ?? 'item'
  const total = totalWeeks(draft)
  const lighter = phase ? lighterWeeks(phase, draft.deload_every) : []

  return (
    <DndContext
      sensors={sensors}
      onDragStart={(e) => {
        const data = e.active.data.current as { sessionId: string; title: string }
        setDragging({ sessionId: data.sessionId, title: data.title })
      }}
      onDragEnd={onDragEnd}
      onDragCancel={() => setDragging(null)}
      accessibility={{
        screenReaderInstructions: {
          draggable: 'To place this session, press Space or Enter, choose a day with the arrow keys, and press Space to drop it. Escape puts it back.',
        },
        announcements: {
          onDragStart: ({ active }) => `Picked up ${titleOf(active.data.current)}.`,
          onDragOver: ({ active, over }) => (over ? `${titleOf(active.data.current)} is over ${titleOf(over.data.current)}.` : undefined),
          onDragEnd: ({ active, over }) => (over ? `${titleOf(active.data.current)} dropped on ${titleOf(over.data.current)}.`
            : `${titleOf(active.data.current)} was not moved.`),
          onDragCancel: ({ active }) => `Cancelled. ${titleOf(active.data.current)} was not moved.`,
        },
      }}
    >
      <div className="grid gap-6 p-6 lg:grid-cols-[16rem_minmax(0,1fr)] 2xl:grid-cols-[16rem_minmax(0,1fr)_22rem]">
        <aside className="flex max-h-[calc(100vh-10rem)] flex-col gap-4 lg:sticky lg:top-0">
          <SessionShelf sessions={sessions} placed={placedSessions(draft)} />
        </aside>

        <main className="flex min-w-0 flex-col gap-4">
          <div className="flex flex-wrap items-end gap-2">
            <label className="flex min-w-48 flex-1 flex-col gap-1">
              <span className="text-xs text-muted-foreground">Program name</span>
              <input value={draft.name} onChange={(e) => change((d) => ({ ...d, name: e.target.value }))}
                placeholder="Strength block" aria-invalid={problems.some((p) => p.field === 'name') || undefined} className={field} />
            </label>
            <label className="flex w-56 flex-col gap-1">
              <span className="text-xs text-muted-foreground">A lighter week</span>
              <select value={draft.deload_every ?? ''} className={field}
                onChange={(e) => change((d) => ({ ...d, deload_every: e.target.value ? Number(e.target.value) : null }))}>
                <option value="">Never</option>
                {[3, 4, 5, 6, 8].map((n) => <option key={n} value={n}>Every {n}th week of a phase</option>)}
              </select>
            </label>
            <Button variant="outline" onClick={() => replaceDraft(reset)}><FilePlus2 className="size-4" /> New</Button>
            <Button onClick={saveNow} loading={save.isPending} disabled={blank}>{draft.id ? 'Save changes' : 'Save program'}</Button>
          </div>
          {refused && refused.problems.length === 0 && <p role="alert" className="text-sm text-bad">{refused.message}</p>}
          {!blank && trackProblems(problems).map((p) => <p key={p.message} role="alert" className="text-sm text-bad">{p.message}</p>)}
          {savedTrack && <RunningNote track={savedTrack} />}

          <section aria-label="Phases" className="flex flex-col gap-2">
            <div className="flex items-center justify-between">
              <h3 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                Phases · {total} {total === 1 ? 'week' : 'weeks'}
              </h3>
              <Button variant="ghost" size="sm" disabled={draft.phases.length >= limits.phases}
                onClick={() => change((d) => addPhase(d, limits.phases))}><Plus className="size-4" /> Add phase</Button>
            </div>
            <div className="flex gap-1" role="group" aria-label="Choose a phase">
              {draft.phases.map((p, i) => {
                const colour = PHASE_COLORS[p.kind as PhaseKind]
                const bad = problems.some((x) => x.phase === i)
                return (
                  <button key={p.uid} type="button" aria-pressed={i === phaseIndex} onClick={() => selectPhase(p.uid)}
                    style={{ flexGrow: Math.max(1, Number(p.weeks) || 1), borderTopColor: colour?.hex }}
                    className={cn('min-w-24 basis-0 rounded-md border border-t-4 px-2 py-1.5 text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                      i === phaseIndex ? 'bg-card' : 'bg-muted/40 text-muted-foreground hover:text-foreground', bad && 'border-bad')}>
                    <span className="block truncate text-sm font-medium">{p.name || `Phase ${i + 1}`}</span>
                    <span className="block text-xs">
                      {colour?.label ?? p.kind} · wk {starts[i]}{p.weeks > 1 ? `–${starts[i] + p.weeks - 1}` : ''}
                    </span>
                  </button>
                )
              })}
            </div>
          </section>

          {phase && (
            <section aria-label={`Phase: ${phase.name || `Phase ${phaseIndex + 1}`}`} className="flex flex-col gap-3 rounded-lg border bg-card p-3">
              <div className="flex flex-wrap items-end gap-2">
                <label className="flex min-w-40 flex-1 flex-col gap-1">
                  <span className="text-xs text-muted-foreground">Phase name</span>
                  <input value={phase.name} onChange={(e) => change((d) => updatePhase(d, phase.uid, { name: e.target.value }))} className={field} />
                </label>
                <label className="flex w-40 flex-col gap-1">
                  <span className="text-xs text-muted-foreground">Kind</span>
                  <select value={phase.kind} onChange={(e) => change((d) => updatePhase(d, phase.uid, { kind: e.target.value }))} className={field}>
                    {(kinds.length ? kinds : [{ id: phase.kind, label: phase.kind }]).map((k) => <option key={k.id} value={k.id}>{k.label}</option>)}
                  </select>
                </label>
                <NumberField label="Weeks" value={phase.weeks} min={1} max={limits.phaseWeeks} className="w-28"
                  invalid={problems.some((p) => p.phase === phaseIndex && p.field === 'weeks')}
                  onChange={(v) => change((d) => updatePhase(d, phase.uid, { weeks: v ?? 1 }))} />
                <span className="flex pb-0.5">
                  <Tip label="Earlier"><button type="button" aria-label="Move this phase earlier" disabled={phaseIndex === 0}
                    onClick={() => change((d) => nudgePhase(d, phase.uid, -1))} className={iconButton}><ChevronLeft className="size-4" /></button></Tip>
                  <Tip label="Later"><button type="button" aria-label="Move this phase later" disabled={phaseIndex === draft.phases.length - 1}
                    onClick={() => change((d) => nudgePhase(d, phase.uid, 1))} className={iconButton}><ChevronRight className="size-4" /></button></Tip>
                  <Tip label="Remove this phase"><button type="button" aria-label="Remove this phase" disabled={draft.phases.length <= 1}
                    onClick={() => { change((d) => removePhase(d, phase.uid)); selectPhase(draft.phases[phaseIndex === 0 ? 1 : phaseIndex - 1]?.uid ?? '') }}
                    className={iconButton}><Trash2 className="size-4" /></button></Tip>
                </span>
              </div>
              {problemsAt(problems, phaseIndex).filter((p) => p.week === null).map((p) => (
                <p key={p.message} role="alert" className="text-sm text-bad">{p.message}</p>
              ))}
              <WeekGrid phase={phase} phaseIndex={phaseIndex} sessions={sessions} actions={actions} problems={blank ? [] : problems}
                dragging={dragging} maxWeeks={limits.templateWeeks} />
              <div className="flex flex-wrap items-center justify-between gap-2">
                <p className="text-sm text-muted-foreground">
                  {repeatLine(phase)}
                  {lighter.length > 0 && ` Week${lighter.length === 1 ? '' : 's'} ${lighter.join(', ')} of the phase ${lighter.length === 1 ? 'is' : 'are'} lighter: every day a light day.`}
                </p>
                <Button variant="ghost" size="sm" disabled={phase.template.length >= limits.templateWeeks}
                  onClick={() => change((d) => addWeek(d, phase.uid, limits.templateWeeks))}><Plus className="size-4" /> Add week</Button>
              </div>
            </section>
          )}
        </main>

        <aside className="flex flex-col gap-6 lg:col-span-2 2xl:col-span-1">
          <section aria-label="Summary" className="flex flex-col gap-3">
            <h3 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">What it adds up to</h3>
            {blank && <p className="text-sm text-muted-foreground">Drag a session onto a day and the program is read here.</p>}
            {!blank && preview.isError && <FailedState size="compact" title="Could not read the draft" error={preview.error} onRetry={() => preview.refetch()} />}
            {shown?.track && (
              <>
                <ul className="flex flex-col gap-1 text-sm">
                  {shown.track.phases.map((p) => (
                    <li key={p.id} className="flex items-baseline justify-between gap-2">
                      <span className="truncate font-medium">{p.name}</span>
                      <span className="shrink-0 tabular-nums text-muted-foreground">
                        wk {p.firstWeek}{p.lastWeek > p.firstWeek ? `–${p.lastWeek}` : ''} · {p.sessionsPerWeek} a week · {p.minutesPerWeek} min
                      </span>
                    </li>
                  ))}
                </ul>
                {shown.track.equipment.length > 0 && (
                  <p className="text-sm text-muted-foreground">
                    Needs {shown.track.equipment.map((e) => EQUIPMENT_LABELS[e as keyof typeof EQUIPMENT_LABELS] ?? e).join(', ')}
                  </p>
                )}
                {shown.track.forecast.length > 0 && (
                  <div className="flex flex-col gap-2">
                    <h4 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Week by week</h4>
                    {shown.track.forecast.map((f) => (
                      <div key={`${f.session}-${f.exercise}`} className="text-sm">
                        <div className="font-medium">{f.exercise} <span className="font-normal text-muted-foreground">· {f.session}</span></div>
                        <ol className="text-muted-foreground">
                          {f.weeks.map((w) => (
                            <li key={w.week} className="tabular-nums">Week {w.week}: {w.text ?? 'as written'}{w.light ? ' · light' : ''}</li>
                          ))}
                        </ol>
                      </div>
                    ))}
                  </div>
                )}
              </>
            )}
            {shown && !shown.ok && <p className="text-sm text-muted-foreground">The summary follows once what is marked is complete.</p>}
          </section>

          <section aria-label="Saved programs" className="flex flex-col gap-2">
            <h3 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Saved programs</h3>
            {tracksQuery.data && tracksQuery.data.tracks.length === 0 && (
              <p className="text-sm text-muted-foreground">Nothing saved yet. A saved program opens in Program ▸ Preview, where it is started.</p>
            )}
            <ul className="flex flex-col gap-1">
              {(tracksQuery.data?.tracks ?? []).map((track) => (
                <li key={track.id} className="flex items-center gap-1 rounded-md border bg-card px-2 py-1.5"
                  aria-current={track.id === draft.id ? 'true' : undefined}>
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-sm font-medium">{track.name}</span>
                    <span className="block truncate text-xs text-muted-foreground">
                      {track.totalWeeks} weeks · {track.phases.length} {track.phases.length === 1 ? 'phase' : 'phases'}{track.id === draft.id ? ' · open' : ''}
                    </span>
                  </span>
                  <Button variant="outline" size="sm" onClick={() => setStarting(track)}>Preview</Button>
                  <Tip label="Edit"><button type="button" aria-label={`Edit ${track.name}`} className={iconButton}
                    onClick={() => replaceDraft(() => open(fromWire(track)))}><Pencil className="size-4" /></button></Tip>
                  <Tip label="Duplicate"><button type="button" aria-label={`Duplicate ${track.name}`} className={iconButton}
                    onClick={() => replaceDraft(() => open(duplicateOf(track)))}><Copy className="size-4" /></button></Tip>
                  <Tip label="Delete"><button type="button" aria-label={`Delete ${track.name}`} className={iconButton}
                    onClick={() => setDeleting(track)}><Trash2 className="size-4" /></button></Tip>
                </li>
              ))}
            </ul>
          </section>
        </aside>
      </div>
      <DragOverlay dropAnimation={null}>
        {dragging && <div className="rounded-md border bg-card px-3 py-2 text-sm shadow-xl ring-2 ring-primary/40">{dragging.title}</div>}
      </DragOverlay>
      {starting && tracksQuery.data && <StartDialog track={starting} packageId={tracksQuery.data.packageId} onClose={() => setStarting(null)} />}
      <ConfirmDialog
        open={replacing !== null}
        onOpenChange={(o) => { if (!o) setReplacing(null) }}
        title="Leave this program unsaved?"
        description="What you changed since the last save is lost."
        confirmLabel="Leave it"
        destructive
        onConfirm={() => { replacing?.(); setReplacing(null) }}
      />
      <ConfirmDialog
        open={deleting !== null}
        onOpenChange={(o) => { if (!o) setDeleting(null) }}
        title={`Delete “${deleting?.name ?? ''}”?`}
        description="The program leaves your saved ones. Its sessions stay."
        confirmLabel="Delete"
        destructive
        onConfirm={() => {
          const track = deleting
          setDeleting(null)
          if (!track) return
          remove.mutate(track.id, {
            onSuccess: () => { if (draft.id === track.id) reset() },
            onError: (e) => toast.failed(trackRefusal(e).message),
          })
        }}
      />
    </DndContext>
  )
}
