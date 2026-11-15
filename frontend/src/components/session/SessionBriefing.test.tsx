// @vitest-environment jsdom
/**
 * The briefing before a session: the server's document laid out — today's
 * numbers, the suggestion, the cycle, the earlier occurrences with their
 * status in words, a session to confirm first — and nothing when it adds
 * nothing to the prescription.
 */
import { describe, it, expect, afterEach, vi } from 'vitest'
import { render, screen, cleanup, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router-dom'
import { SessionBriefing } from '@/components/session/SessionBriefing'
import { briefingSeries, briefingSeriesSummary, saysSomething, sessionPath } from '@/lib/briefing'
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
const doc: Doc = { headline: 'Swing', items: [swing],
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
  it('lays out the item, its history and the session to confirm first', async () => {
    get.mockResolvedValue(doc)
    mount()
    await waitFor(() => expect(screen.getByText('Nerd Math Two-Hand Swing')).toBeTruthy())
    expect(get).toHaveBeenCalledWith('/sessions/briefing?key=4-Monday-0')
    expect(screen.getByText('10 × 18 · on the minute')).toBeTruthy()
    expect(screen.getByText('Step 7 of 32 · stage 1 of 4')).toBeTruthy()
    expect(screen.getByText("Thursday's session is not confirmed as clean.")).toBeTruthy()
    expect(screen.getByText('Not confirmed')).toBeTruthy()            // the status in words, not colour alone
    expect(screen.getAllByText('Clean')).toHaveLength(2)
    expect(screen.getByRole('link', { name: 'Confirm' }).getAttribute('href')).toBe('/program/3/Thursday')
    expect(screen.getByRole('img').getAttribute('aria-label')).toContain('Total reps')
    expect(screen.getByRole('progressbar').getAttribute('aria-valuenow')).toBe('7')
  })

  it('shows nothing when the briefing adds nothing to the prescription', async () => {
    get.mockResolvedValue({ headline: null, pending: [],
                            items: [{ ...swing, history: [], times: 0, cycle: undefined, suggestion: undefined }] })
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
  it('draws the metric across the occurrences, then today as planned', () => {
    expect(briefingSeries(swing).map((p) => [p.value, p.planned])).toEqual(
      [[120, false], [140, false], [160, false], [180, true]])
    expect(briefingSeriesSummary(swing)).toContain('180')
  })

  it('draws nothing from fewer than three points or without a metric', () => {
    expect(briefingSeries({ ...swing, history: [] })).toEqual([])
    expect(briefingSeries({ ...swing, metric: undefined })).toEqual([])
    const flat = swing.history.map((h) => ({ ...h, values: { total_reps: 180 } }))
    expect(briefingSeries({ ...swing, history: flat })).toEqual([])   // a run that never changes
  })

  it('knows when there is something to say and where a session lives', () => {
    expect(saysSomething(doc)).toBe(true)
    expect(saysSomething(undefined)).toBe(false)
    expect(sessionPath('3-Thursday-0')).toBe('/program/3/Thursday')
    expect(sessionPath('nonsense')).toBeNull()
  })
})
