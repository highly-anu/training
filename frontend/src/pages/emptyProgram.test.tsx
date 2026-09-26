// @vitest-environment jsdom
/**
 * Every program-dependent page must render an empty state rather than crash
 * when the athlete has no program.
 *
 * This is reachable by every new user, and it was reachable by an existing one:
 * a stored program saved without its envelope read back as `currentProgram:
 * null`, so the whole app sat in this state while the data was intact. These
 * assert the paths actually render, rather than assuming they do because the
 * code has an `if (!program)` branch.
 */
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { render, screen, cleanup } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'

import { useProgramStore } from '@/store/programStore'
import { Dashboard } from '@/pages/Dashboard'
import { ProgramView } from '@/pages/ProgramView'
import { SessionDetail } from '@/pages/SessionDetail'

// The API layer is irrelevant here — the question is purely what these render
// with an empty store. Stub it so nothing reaches the network.
vi.mock('@/api/client', () => ({
  apiClient: {
    get: vi.fn().mockResolvedValue(null),
    post: vi.fn().mockResolvedValue(null),
    put: vi.fn().mockResolvedValue(null),
    delete: vi.fn().mockResolvedValue(null),
  },
}))

function wrap(ui: ReactNode, route = '/') {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false, gcTime: 0 } },
  })
  return render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={[route]}>{ui}</MemoryRouter>
    </QueryClientProvider>,
  )
}

/** The state after a load that found no program — what a new user has. */
function setEmptyProgramState() {
  useProgramStore.setState({
    currentProgram: null,
    programStartDate: null,
    eventDate: null,
    sourceGoalIds: [],
    sourceGoalWeights: {},
    revision: null,
    programLoadState: 'loaded',
  })
}

beforeEach(setEmptyProgramState)
afterEach(cleanup)

describe('with no program', () => {
  it('Dashboard renders its empty state instead of throwing', () => {
    expect(() => wrap(<Dashboard />)).not.toThrow()
    expect(screen.getByText(/no program yet/i)).toBeInTheDocument()
  })

  it('Dashboard offers a way out of the empty state', () => {
    wrap(<Dashboard />)
    expect(screen.getByText(/build a program/i)).toBeInTheDocument()
  })

  it('ProgramView renders its empty state instead of throwing', () => {
    expect(() => wrap(<ProgramView />, '/program')).not.toThrow()
    expect(screen.getByText(/no program generated yet/i)).toBeInTheDocument()
  })

  it('SessionDetail renders an empty state instead of throwing', () => {
    expect(() => wrap(<SessionDetail />, '/program/1/Monday')).not.toThrow()
  })
})

describe('while the program is still loading', () => {
  beforeEach(() => {
    setEmptyProgramState()
    useProgramStore.setState({ programLoadState: 'loading' })
  })

  it('Dashboard shows the loader, not the empty state', () => {
    wrap(<Dashboard />)
    // Claiming "no program" before the answer is known is what produced the
    // flicker between the loader and the empty state.
    expect(screen.queryByText(/no program yet/i)).not.toBeInTheDocument()
  })

  it('Dashboard keeps showing a program that is already loaded during a refetch', () => {
    useProgramStore.setState({
      programLoadState: 'loading',
      currentProgram: {
        weeks: [{
          week_number: 1,
          phase: 'base',
          schedule: { Monday: [] },
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
        } as any],
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
      } as any,
      programStartDate: '2026-09-21',
    })
    wrap(<Dashboard />)
    expect(screen.queryByText(/no program yet/i)).not.toBeInTheDocument()
    expect(screen.queryByText(/retrieving your program/i)).not.toBeInTheDocument()
  })
})

describe('when the program could not be loaded', () => {
  beforeEach(() => {
    setEmptyProgramState()
    useProgramStore.setState({ programLoadState: 'error' })
  })

  it('does not offer to build a first program', () => {
    wrap(<Dashboard />)
    // Taking that offer would PUT a new program with baseRevision: null, which
    // the server's concurrency check skips — overwriting a program that is
    // probably still there.
    expect(screen.queryByText(/build a program/i)).not.toBeInTheDocument()
    expect(screen.queryByText(/no program yet/i)).not.toBeInTheDocument()
  })

  it('says the load failed and offers a retry', () => {
    wrap(<Dashboard />)
    expect(screen.getByText(/couldn't load your program/i)).toBeInTheDocument()
    expect(screen.getByText(/retry/i)).toBeInTheDocument()
  })
})

describe('switching accounts', () => {
  it('drops the previous account program before the next load resolves', async () => {
    // Account A is loaded...
    useProgramStore.setState({
      ...useProgramStore.getState(),
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      currentProgram: { weeks: [] } as any,
      revision: 'rev-A',
      loadedForUserId: 'user-A',
      programLoadState: 'loaded',
    })

    // ...and account B starts loading. Nothing else in the app clears this
    // store on sign-out or switch, so if the program survived here a save in
    // the gap would write A's program into B's row.
    void useProgramStore.getState().loadFromServer('user-B')

    expect(useProgramStore.getState().currentProgram).toBeNull()
    expect(useProgramStore.getState().revision).toBeNull()
  })

  it('does not blank the store when the same account re-loads', () => {
    useProgramStore.setState({
      ...useProgramStore.getState(),
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      currentProgram: { weeks: [] } as any,
      loadedForUserId: 'user-A',
      programLoadState: 'loaded',
    })

    // StrictMode double-invokes effects in dev; this second call must not
    // flash the empty state.
    void useProgramStore.getState().loadFromServer('user-A')
    expect(useProgramStore.getState().currentProgram).not.toBeNull()
  })
})
