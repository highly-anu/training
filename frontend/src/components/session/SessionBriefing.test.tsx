// @vitest-environment jsdom
/**
 * The briefing before a session: the server's document laid out as one row an
 * exercise — today's numbers, a strip with one mark for every earlier time,
 * the suggestion — with the dated lines in the row's sheet, and nothing when
 * it adds nothing to the prescription.
 */
import { describe, it, expect, afterEach, vi } from 'vitest'
import { render, screen, cleanup, waitFor, fireEvent, within } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router-dom'
import { SessionBriefing } from '@/components/session/SessionBriefing'
import { briefingRows, markHeight, rowLabel, rowSeries, rowSeriesSummary, saysSomething, sessionPath, stripMarks } from '@/lib/briefing'
import type { BriefingItem, SessionBriefing as Doc } from '@/api/briefing'

const get = vi.fn()
vi.mock('@/api/client', () => ({ apiClient: { get: (...args: unknown[]) => get(...args) } }))

const occurrence = (date: string, dayText: string, total: number, status: string, key: string) => ({
  date, dayText, text: `10 × ${total / 10} · on the minute`, status, isDeload: false, sessionKey: key,
  values: { total_reps: total },
})
const swing = {
  id: 'module:swing', title: 'Nerd Math Two-Hand Swing',
  today: { text: '10 × 18 · on the minute', conditional: true, values: { total_reps: 180 },
           lines: [{ exerciseId: 'wk_kb_swing_two_hand', name: 'Swing', text: '10 × 18 · on the minute' }] },
  history: [occurrence('2026-11-05', '5 Nov', 120, 'clean', '2-Thursday-0'),
            occurrence('2026-11-09', '9 Nov', 140, 'clean', '3-Monday-0'),
            occurrence('2026-11-12', 'Thursday', 160, 'unconfirmed', '3-Thursday-0')],
  times: 6, metric: { id: 'total_reps', label: 'Total reps', unit: 'reps' },
  cycle: { step: 7, of: 32, text: 'Step 7 of 32 · stage 1 of 4' },
  suggestion: { kind: 'confirm_pending', text: "Thursday's session is not confirmed as clean." },
} as unknown as BriefingItem
const point = (date: string, dayText: string, total: number | undefined, status: string, key?: string) => ({
  date, dayText, text: `10 × ${(total ?? 140) / 10}`, status, isDeload: false, sessionKey: key ?? null,
  ...(total === undefined ? {} : { value: total }),
})
/** The swing as today's server sends it: one exercise carrying its whole run. */
const swingRun = { ...swing, suggestion: { kind: 'next_step', text: '2 more a round than Thursday.' }, exercises: [{
  exerciseId: 'wk_kb_swing_two_hand', name: 'Kettlebell Swing', times: 6, timesText: '6 sessions',
  today: { text: '10 × 18 · on the minute', value: 180 }, metric: swing.metric, history: swing.history,
  run: [point('2026-10-26', '26 Oct', 60, 'clean'), point('2026-10-29', '29 Oct', 80, 'missed'),
        point('2026-11-02', '2 Nov', 100, 'clean'), point('2026-11-05', '5 Nov', 120, 'clean', '2-Thursday-0'),
        point('2026-11-09', '9 Nov', undefined, 'logged', '3-Monday-0'),
        point('2026-11-12', 'Thursday', 160, 'unconfirmed', '3-Thursday-0')],
}] } as unknown as BriefingItem
const doc: Doc = { headline: 'Swing', items: [swingRun],
                   pending: [{ sessionKey: '3-Thursday-0', date: '2026-11-12', text: 'Thursday: done as written?' }] }

function mount() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(
    <QueryClientProvider client={client}>
      <MemoryRouter><SessionBriefing sessionKey="4-Monday-0" modality="power" /></MemoryRouter>
    </QueryClientProvider>)
}

afterEach(() => { cleanup(); get.mockReset() })

describe('SessionBriefing', () => {
  it('is one row an exercise: today, a mark for every earlier time, the suggestion', async () => {
    get.mockResolvedValue(doc)
    mount()
    await waitFor(() => expect(screen.getByText('Nerd Math Two-Hand Swing')).toBeTruthy())
    expect(get).toHaveBeenCalledWith('/sessions/briefing?key=4-Monday-0')
    expect(screen.queryByText('Kettlebell Swing')).toBeNull()        // one exercise: the item's name is the row's
    expect(screen.getByText('10 × 18 · on the minute')).toBeTruthy()
    expect(screen.getByText('Step 7 of 32')).toBeTruthy()            // the short label; the stages are the sheet's
    expect(screen.getByText('2 more a round than Thursday.')).toBeTruthy()
    // Every time is a mark — six, not the three listed — then today's.
    const marks = [...screen.getByTestId('briefing-strip').children].map((m) => m.getAttribute('data-status'))
    expect(marks).toEqual(['clean', 'missed', 'clean', 'clean', 'logged', 'unconfirmed', 'today'])
    // No dated line, chart, bar or banner on the block itself.
    expect(screen.queryByText('Thursday: done as written?')).toBeNull()
    expect(screen.queryByText('10 × 16')).toBeNull()
    expect(screen.queryByRole('img')).toBeNull()
    expect(screen.queryByRole('progressbar')).toBeNull()
    expect(screen.getByRole('button').getAttribute('aria-label')).toBe(
      'Nerd Math Two-Hand Swing. Today: 10 × 18 · on the minute. Step 7 of 32. 6 earlier sessions. Last, Thursday: 10 × 16, not confirmed. '
      + '2 more a round than Thursday. Shows every earlier session.')
  })

  it('opens a row into every earlier session, the chart and the session to confirm', async () => {
    get.mockResolvedValue(doc)
    mount()
    await waitFor(() => expect(screen.getByRole('button')).toBeTruthy())
    fireEvent.click(screen.getByRole('button'))
    const sheet = within(await screen.findByRole('dialog'))
    expect(sheet.getByText('Earlier sessions · 6')).toBeTruthy()
    expect(sheet.getAllByRole('listitem')).toHaveLength(6)
    expect(sheet.getAllByRole('listitem')[0].textContent).toContain('Thursday')      // newest first
    expect(sheet.getByText('Not confirmed')).toBeTruthy()                            // the status in words, not colour alone
    expect(sheet.getAllByText('Clean')).toHaveLength(3)
    expect(sheet.getByRole('link', { name: 'Confirm' }).getAttribute('href')).toBe('/program/3/Thursday')
    expect(sheet.getByRole('img').getAttribute('aria-label')).toContain('Total reps')
    expect(sheet.getByRole('progressbar').getAttribute('aria-valuenow')).toBe('7')
  })

  it('reads an item of several exercises as a row each, headed once', async () => {
    const run = (text: string) => [{ ...point('2026-11-08', '8 Nov', 25, 'clean'), text }]
    get.mockResolvedValue({ headline: null, pending: [], items: [{ ...swing, id: 'module:clean_press', title: 'Clean and Press',
      cycle: undefined, exercises: [
        { exerciseId: 'clean', name: 'KB Clean', today: { text: '10 × 1 · on the minute' }, history: [], run: run('5 × 5 · 20 kg'), timesText: '1 session' },
        { exerciseId: 'press', name: 'KB Press', today: { text: '10 × 1 · on the minute' }, history: [], run: [], timesText: 'First time' },
      ] }] })
    mount()
    await waitFor(() => expect(screen.getByText('KB Clean')).toBeTruthy())
    expect(screen.getAllByText('Clean and Press')).toHaveLength(1)
    expect(screen.getAllByRole('button')).toHaveLength(2)
    expect(screen.getByText('1 session')).toBeTruthy()
    expect(screen.getByText('First time')).toBeTruthy()
    // The item's one suggestion closes its last row.
    expect(within(screen.getAllByRole('button')[1]).getByText("Thursday's session is not confirmed as clean.")).toBeTruthy()
  })

  it('shows nothing when the briefing adds nothing to the prescription', async () => {
    get.mockResolvedValue({ headline: null, pending: [],
                            items: [{ ...swingRun, history: [], times: 0, cycle: undefined, suggestion: undefined }] })
    const { container } = mount()
    await waitFor(() => expect(get).toHaveBeenCalled())
    expect(container.innerHTML).toBe('')
  })

  it('says a failure, with a way to try again', async () => {
    get.mockRejectedValue(new Error('offline'))
    mount()
    await waitFor(() => expect(screen.getByText('Could not read your earlier sessions')).toBeTruthy())
    expect(screen.getByText('Try again')).toBeTruthy()
  })
})

describe('the briefing model', () => {
  const [row] = briefingRows(doc)

  it('makes a row of an exercise with its whole run', () => {
    expect([row.name, row.header]).toEqual(['Nerd Math Two-Hand Swing', undefined])
    expect(row.run.map((o) => o.value)).toEqual([60, 80, 100, 120, undefined, 160])
    expect([row.todayValue, row.caption]).toEqual([180, 'Step 7 of 32'])
    expect(rowLabel(row)).toContain('Last, Thursday: 10 × 16, not confirmed')
  })

  it('draws the newest marks that fit, each as tall as its place in the run', () => {
    expect(stripMarks(row, 2).map((o) => o.value)).toEqual([undefined, 160])
    expect(stripMarks(row).length).toBe(6)
    expect(stripMarks(row, 0)).toEqual([])
    expect(markHeight(60, [60, 120, 180])).toBeCloseTo(1 / 3)
    expect(markHeight(180, [60, 120, 180])).toBe(1)
    expect(markHeight(undefined, [60, 180])).toBe(0.6)       // no number
    expect(markHeight(10, [10, 10])).toBe(0.6)               // a run that never moves
  })

  it("charts the run then today as planned, in the row's sheet", () => {
    expect(rowSeries(row).map((p) => [p.value, p.planned])).toEqual(
      [[60, false], [80, false], [100, false], [120, false], [160, false], [180, true]])
    expect(rowSeriesSummary(row)).toContain('180')
    // Fewer than three points, or a run that never changes, is a list.
    expect(rowSeries({ ...row, run: [] })).toEqual([])
    expect(rowSeries({ ...row, todayValue: 100, run: row.run.map((o) => ({ ...o, value: 100 })) })).toEqual([])
  })

  it("reads an older server's history as the run", () => {
    // No `exercises`: the item is its own row.
    const [old] = briefingRows({ headline: null, pending: [], items: [swing] })
    expect([old.name, old.header, old.caption]).toEqual(['Nerd Math Two-Hand Swing', undefined, 'Step 7 of 32'])
    expect(old.run.map((o) => o.value)).toEqual([120, 140, 160])
    expect(old.todayValue).toBe(180)
    // `exercises` without `run`: each exercise's history.
    const [one] = briefingRows({ headline: null, pending: [], items: [{ ...swing, exercises: [
      { exerciseId: 'swing', name: 'Swing', today: { text: '10 × 18' }, history: swing.history }] }] })
    expect(one.run.map((o) => o.value)).toEqual([120, 140, 160])
    expect([one.todayValue, one.caption]).toEqual([180, 'Step 7 of 32'])
    // One session to confirm holds up every module: it is said once.
    const twice = briefingRows({ headline: null, pending: [], items: [swing, { ...swing, id: 'module:b' }] })
    expect(twice.map((r) => r.suggestion?.text)).toEqual(["Thursday's session is not confirmed as clean.", undefined])
    // Only that one: two lifts with the same step each say theirs.
    const step = { kind: 'next_load', text: '2.5 kg more.' }
    expect(briefingRows({ headline: null, pending: [], items: [{ ...swing, suggestion: step }, { ...swing, id: 'module:b', suggestion: step }] })
      .map((r) => r.suggestion?.text)).toEqual(['2.5 kg more.', '2.5 kg more.'])
  })

  it('knows when there is something to say and where a session lives', () => {
    expect(saysSomething(doc)).toBe(true)
    expect(saysSomething(undefined)).toBe(false)
    expect(sessionPath('3-Thursday-0')).toBe('/program/3/Thursday')
    expect(sessionPath('nonsense')).toBeNull()
  })
})
