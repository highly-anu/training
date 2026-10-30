// @vitest-environment jsdom
/**
 * Today's rest day can still take a session: "Add a session" opens the sheet
 * in add mode (an extra, counted once done).
 */
import { describe, it, expect, afterEach, vi } from 'vitest'
import { render, screen, cleanup, fireEvent } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { format } from 'date-fns'
import { TodaySession } from './TodaySession'
import type { GeneratedProgram } from '@/api/types'

vi.mock('@/api/client', () => ({ apiClient: { get: vi.fn(() => Promise.resolve([])), post: vi.fn() } }))

afterEach(cleanup)

const today = format(new Date(), 'EEEE')
const program = (sessions: unknown[]) => ({
  weeks: [{ week_number: 1, phase: 'base', schedule: { [today]: sessions } }],
  constraints: {},
}) as unknown as GeneratedProgram

function wrap(p: GeneratedProgram) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(<QueryClientProvider client={qc}><MemoryRouter><TodaySession program={p} weekIndex={0} /></MemoryRouter></QueryClientProvider>)
}

describe('TodaySession on a rest day', () => {
  it('offers to add a session, and opens the sheet in add mode', async () => {
    wrap(program([]))
    expect(screen.getByText('Rest Day')).toBeTruthy()
    fireEvent.click(screen.getByRole('button', { name: /Add a session/ }))
    expect(await screen.findByText(/an extra: it counts once you do it/)).toBeTruthy()
    expect(screen.getByRole('radio', { name: 'Mobility', checked: true })).toBeTruthy()
  })
})
