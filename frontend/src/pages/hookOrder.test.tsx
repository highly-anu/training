// @vitest-environment jsdom
/**
 * Pages must not change their hook count between renders.
 *
 * SessionDetail called six hooks *after* its `if (!program)` early return, and
 * WorkoutDetail one after `if (!workout)`. Both guards flip on the most common
 * transition each page has — program arriving from the server, the workout
 * query resolving — so the very next render called more hooks than the last
 * and React threw "Rendered more hooks than during the previous render".
 */
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { render, cleanup, act } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { useProgramStore } from '@/store/programStore'
import { SessionDetail } from '@/pages/SessionDetail'

vi.mock('@/api/client', () => ({
  apiClient: {
    get: vi.fn().mockResolvedValue(null),
    post: vi.fn().mockResolvedValue(null),
    put: vi.fn().mockResolvedValue(null),
    delete: vi.fn().mockResolvedValue(null),
  },
}))

function wrap(ui: ReactNode, route: string) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter initialEntries={[route]}>{ui}</MemoryRouter>
    </QueryClientProvider>,
  )
}

const oneWeekProgram = {
  weeks: [{
    week_number: 1,
    phase: 'base',
    schedule: { Monday: [] },
  }],
  goal: { id: 'x', name: 'X' },
// eslint-disable-next-line @typescript-eslint/no-explicit-any
} as any

beforeEach(() => {
  useProgramStore.setState({
    currentProgram: null,
    programStartDate: null,
    programLoadState: 'loaded',
    revision: null,
  })
})
afterEach(cleanup)

describe('SessionDetail hook order', () => {
  it('survives the program arriving after an empty first render', async () => {
    const errors: string[] = []
    const spy = vi.spyOn(console, 'error').mockImplementation((...a) => {
      errors.push(a.map(String).join(' '))
    })

    // Render ONCE and keep the same mounted instance. Re-rendering through a
    // fresh provider would remount it, which resets hook state and hides the
    // very mismatch this is testing.
    wrap(<SessionDetail />, '/program/1/Monday')

    // The program arrives. The component re-renders in place via its store
    // subscription — and before the fix this render called six more hooks
    // than the previous one.
    await act(async () => {
      useProgramStore.setState({
        currentProgram: oneWeekProgram,
        programStartDate: '2026-09-21',
      })
    })

    const hookErrors = errors.filter((e) => /Rendered more hooks|order of Hooks/i.test(e))
    expect(hookErrors).toEqual([])
    spy.mockRestore()
  })
})
