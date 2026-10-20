// @vitest-environment jsdom
/**
 * The program preview: a generated program is a draft until the athlete
 * starts it, edits to the draft never reach the active program, an
 * infeasible answer is never saved, and the profile offers a regenerate only
 * when the server says the change moves something.
 *
 * Before: the builder saved in the generate mutation (an infeasible answer
 * PUT `weeks: []` over the active program), a regenerate spliced an empty
 * tail over the remaining weeks, and adding equipment no session uses asked
 * to rebuild the plan.
 */
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { render, screen, cleanup, waitFor, act } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { useProgramStore } from '@/store/programStore'
import { useProfileStore } from '@/store/profileStore'
import { usePreviewStore } from '@/store/previewStore'
import { applyRegeneratedTail, commitProgram, impactParams, isInfeasible } from '@/api/programs'
import { heldBackSummary } from '@/lib/heldBack'
import { spliceRegenerated } from '@/lib/programSource'
import { RegenerateFromWeekBanner } from '@/components/program/RegenerateFromWeekBanner'
import type { GeneratedProgram, Session, WeekData } from '@/api/types'

const put = vi.fn()
const post = vi.fn()
const patch = vi.fn()
vi.mock('@/api/client', () => ({
  apiClient: {
    get: vi.fn().mockResolvedValue(null),
    post: (...args: unknown[]) => post(...args),
    put: (...args: unknown[]) => put(...args),
    patch: (...args: unknown[]) => patch(...args),
    delete: vi.fn().mockResolvedValue(null),
  },
}))

const session = (id: string): Session => ({
  modality: 'max_strength',
  archetype: { id, name: id } as Session['archetype'],
  exercises: [{ exercise: { id: 'back_squat', name: 'Back Squat' }, load: {}, slot_role: 'main' } as unknown as Session['exercises'][number]],
})
const week = (n: number, id = 'a'): WeekData => ({
  week_number: n, week_in_phase: n, phase: 'base', is_deload: false, schedule: { Monday: [session(id)] },
} as WeekData)
const program = (weeks: WeekData[], extra: Partial<GeneratedProgram> = {}): GeneratedProgram => ({
  goal: { id: '_phil_starting_strength', name: 'SS', primary_sources: ['starting_strength'] },
  constraints: { equipment: ['barbell', 'rack', 'plates'], training_level: 'novice', injury_flags: [], days_per_week: 3 },
  validation: { feasible: true, errors: [], warnings: [], info: [] },
  weeks,
  ...extra,
} as unknown as GeneratedProgram)
const refused = program([], { validation: { feasible: false, errors: [{ code: 'X', message: 'no' }], warnings: [], info: [] } })

beforeEach(() => {
  put.mockReset().mockResolvedValue({ revision: 'r2' })
  post.mockReset()
  patch.mockReset()
  usePreviewStore.getState().clear()
  useProgramStore.setState({ currentProgram: null, revision: 'r1', programStartDate: null, sourceGoalIds: [],
                             sourceGoalWeights: {}, programSaveError: null })
})
afterEach(cleanup)

describe('a draft is not the program', () => {
  it('a swap edits the draft and never the active program', () => {
    const active = program([week(1, 'active')])
    useProgramStore.setState({ currentProgram: active })
    usePreviewStore.getState().open('new', { constraints: active.constraints, philosophyId: 'starting_strength' },
                                    program([week(1)]))
    usePreviewStore.getState().replaceExercise(0, 'Monday', 0, 0,
      { exercise: { id: 'front_squat', name: 'Front Squat' }, load: {} } as unknown as Session['exercises'][number])
    const draft = usePreviewStore.getState().draft!
    expect(draft.weeks[0].schedule.Monday[0].exercises[0].exercise.id).toBe('front_squat')
    expect(usePreviewStore.getState().edits).toBe(1)
    expect(useProgramStore.getState().currentProgram).toBe(active)
    expect(put).not.toHaveBeenCalled()
  })

  it('a re-preview drops the edits and the stale change list', () => {
    usePreviewStore.getState().open('regenerate', { constraints: {} as GeneratedProgram['constraints'] }, program([week(1)]),
                                    { startIdx: 2, changes: [{ week_index: 0 } as never] })
    usePreviewStore.getState().replaceSession(0, 'Monday', 0, session('b'))
    usePreviewStore.getState().setDraft({ constraints: {} as GeneratedProgram['constraints'] }, program([week(1)]))
    expect(usePreviewStore.getState().edits).toBe(0)
    expect(usePreviewStore.getState().regenerate).toEqual({ startIdx: 2, changes: [] })
  })

  it('starting an infeasible draft saves nothing', () => {
    expect(isInfeasible(refused)).toBe(true)
    expect(commitProgram(new QueryClient(), refused, { philosophyId: 'starting_strength' })).toBe(false)
    expect(useProgramStore.getState().currentProgram).toBeNull()
    expect(put).not.toHaveBeenCalled()
  })

  it('starting a draft makes it the program and saves it under the loaded revision', async () => {
    const draft = program([week(1)])
    expect(commitProgram(new QueryClient(), draft, { philosophyId: 'starting_strength' })).toBe(true)
    expect(useProgramStore.getState().currentProgram).toBe(draft)
    await waitFor(() => expect(put).toHaveBeenCalledTimes(1))
    expect(put.mock.calls[0][1].baseRevision).toBe('r1')
    expect(put.mock.calls[0][1].keepDaysBehind, 'a rebuild of the same block keeps the days behind').toBe(true)
  })

  it('Held back asks about the draft itself, not the builder defaults', () => {
    const draft = program([{ ...week(1), week_in_phase: 3, phase_id: 'specific', track_id: 'main' } as WeekData,
                           ...Array.from({ length: 19 }, (_, i) => week(i + 2))])
    const p = impactParams({ philosophyId: 'uphill_athlete', eventDate: '2027-03-01',
                             constraints: { training_phase: 'base' } as GeneratedProgram['constraints'] }, draft)
    expect(p.eventDate).toBeUndefined()
    expect(p.numWeeks).toBe(12)
    expect(p.startPhaseId).toBe('specific')
    expect(p.trackId).toBe('main')
    expect(p.constraints.periodization_week).toBe(3)
  })

  it('the server counts what was held back; the client only when it has not', () => {
    const p = program([week(1)])
    expect(heldBackSummary({ ...p, held_back: { slots: 7, sessions: 3 } })).toEqual({ slots: 7, sessions: 3 })
    expect(heldBackSummary(p)).toEqual({ slots: 0, sessions: 0 })
  })
})

describe('applyRegeneratedTail', () => {
  const current = program([week(1), week(2), week(3), week(4)])
  it('refuses an infeasible tail instead of dropping the remaining weeks', () => {
    expect(applyRegeneratedTail(current, refused, { numWeeks: 2 }, '2026-10-05')).toBeNull()
  })
  it('splices as the regenerate always did', () => {
    const tail = program([week(3, 'new'), week(4, 'new')])
    const out = applyRegeneratedTail(current, tail, { numWeeks: 2, keepBefore: '2026-10-20' }, '2026-10-05')!
    expect(out.weeks).toEqual(spliceRegenerated(current.weeks, tail.weeks, 2, '2026-10-05', '2026-10-20'))
    expect(out.phase_summary).toBeUndefined()
  })
})

describe('the profile offers a regenerate only when it changes the program', () => {
  function renderBanner() {
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
    return render(
      <QueryClientProvider client={client}>
        <MemoryRouter><RegenerateFromWeekBanner /></MemoryRouter>
      </QueryClientProvider>
    )
  }

  beforeEach(() => {
    vi.useFakeTimers({ shouldAdvanceTime: true })
    useProgramStore.setState({
      currentProgram: program([week(1), week(2), week(3)]),
      programStartDate: new Date().toISOString().slice(0, 10),
      sourceGoalIds: ['starting_strength'],
    })
    useProfileStore.setState({ trainingLevel: 'novice', injuryFlags: [], customInjuryFlags: [], weeklySchedule: null,
                               equipment: ['barbell', 'rack', 'plates', 'kettlebell'] })
  })
  afterEach(() => vi.useRealTimers())

  it('adopts a change that moves nothing, and never shows the offer', async () => {
    post.mockResolvedValue({ affected: false, comparable: true, sessions: { total: 9, changed: 0 }, changes: [] })
    patch.mockResolvedValue({ saved: true, revision: 'r2',
                              constraints: { ...program([]).constraints, equipment: ['barbell', 'rack', 'plates', 'kettlebell'] } })
    renderBanner()
    expect(screen.getByText(/Checking whether this changes your program/)).toBeTruthy()
    await act(async () => { vi.advanceTimersByTime(1600) })
    await waitFor(() => expect(patch).toHaveBeenCalled())
    const [url, body] = post.mock.calls[0]
    expect(url).toBe('/programs/constraint-change')
    expect(body.constraints.equipment).toContain('kettlebell')
    expect(body.baseline_constraints.equipment).not.toContain('kettlebell')
    expect(patch.mock.calls[0][0]).toBe('/user/program/constraints')
    expect(patch.mock.calls[0][1].baseRevision).toBe('r1')
    await waitFor(() => expect(screen.getByText(/doesn.t change with these settings/)).toBeTruthy())
    expect(screen.queryByText(/Apply from week/)).toBeNull()
    expect(useProgramStore.getState().revision).toBe('r2')
  })

  it('a failed adopt says so and offers it again, never drops the difference', async () => {
    post.mockResolvedValue({ affected: false, comparable: true, sessions: { total: 9, changed: 0 }, changes: [] })
    patch.mockRejectedValueOnce(Object.assign(new Error('boom'), { status: 503 }))
    renderBanner()
    await act(async () => { vi.advanceTimersByTime(1600) })
    const retry = await screen.findByText('Try again')
    expect(screen.getByText(/recording them on it failed/)).toBeTruthy()
    patch.mockResolvedValue({ saved: true, revision: 'r2',
                              constraints: { ...program([]).constraints, equipment: ['barbell', 'rack', 'plates', 'kettlebell'] } })
    await act(async () => { retry.click() })
    await waitFor(() => expect(screen.getByText(/doesn.t change with these settings/)).toBeTruthy())
    expect(patch).toHaveBeenCalledTimes(2)
  })

  it('says how many sessions a change moves, and offers the preview', async () => {
    post.mockResolvedValue({
      affected: true, comparable: true, sessions: { total: 9, changed: 3 }, first_week_number: 2,
      changes: [], program: program([week(1, 'n'), week(2, 'n'), week(3, 'n')]),
    })
    useProfileStore.setState({ equipment: ['kettlebell'] })
    renderBanner()
    await act(async () => { vi.advanceTimersByTime(1600) })
    await waitFor(() => expect(screen.getByText('These settings change 3 sessions from week 2')).toBeTruthy())
    expect(screen.getByText(/Preview changes/)).toBeTruthy()
    expect(patch).not.toHaveBeenCalled()
  })

  it('says what it rebuilt once Apply has removed the difference', async () => {
    post.mockResolvedValue({
      affected: true, comparable: true, sessions: { total: 9, changed: 3 }, first_week_number: 1,
      changes: [], program: program([week(1, 'n'), week(2, 'n'), week(3, 'n')]),
    })
    useProfileStore.setState({ equipment: ['kettlebell'] })
    renderBanner()
    await act(async () => { vi.advanceTimersByTime(1600) })
    const apply = await screen.findByText('Apply from week 1')
    // The saved program now carries the profile's settings, as the server's would.
    put.mockImplementation(async () => {
      const cp = useProgramStore.getState().currentProgram!
      useProgramStore.setState({ currentProgram: { ...cp, constraints: { ...cp.constraints, equipment: ['kettlebell'] } } })
      return { revision: 'r2' }
    })
    await act(async () => { apply.click() })
    await waitFor(() => expect(screen.getByText(/Rebuilt 3 weeks with these settings/)).toBeTruthy())
    expect(put).toHaveBeenCalled()
  })
})
