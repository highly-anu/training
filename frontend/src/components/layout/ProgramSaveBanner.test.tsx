// @vitest-environment jsdom
/**
 * A program change that never reached the server must not be silent.
 *
 * Every mutation persists fire-and-forget; saveUserProgram's boolean was
 * discarded and `lastProgramSaveError` was read by nothing, so a transient 5xx
 * left the browser showing a program the server never received, which then
 * vanished on reload with no explanation.
 */
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { render, screen, cleanup, waitFor } from '@testing-library/react'
import { useProgramStore } from '@/store/programStore'
import { ProgramSaveBanner } from './ProgramSaveBanner'

const putMock = vi.fn()
vi.mock('@/api/client', () => ({
  apiClient: {
    get: vi.fn().mockResolvedValue(null),
    post: vi.fn().mockResolvedValue(null),
    put: (...args: unknown[]) => putMock(...args),
    delete: vi.fn().mockResolvedValue(null),
  },
}))

beforeEach(() => {
  putMock.mockReset()
  useProgramStore.setState({ programSaveError: null, currentProgram: null, revision: null })
})
afterEach(cleanup)

describe('ProgramSaveBanner', () => {
  it('shows nothing when the last save succeeded', () => {
    render(<ProgramSaveBanner />)
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
  })

  it('warns that the change is only on screen when a save fails', () => {
    useProgramStore.setState({ programSaveError: 'Network Error' })
    render(<ProgramSaveBanner />)
    expect(screen.getByRole('alert')).toBeInTheDocument()
    expect(screen.getByText(/not on the server/i)).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /retry/i })).toBeInTheDocument()
  })

  it('treats a stale revision as a conflict, offering reload rather than retry', () => {
    useProgramStore.setState({ programSaveError: 'stale_revision' })
    render(<ProgramSaveBanner />)
    expect(screen.getByText(/changed somewhere else/i)).toBeInTheDocument()
    // Scoped to the button: the message text also says "reload".
    expect(screen.getByRole('button', { name: /reload/i })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /retry/i })).not.toBeInTheDocument()
  })
})

describe('the store records save outcomes', () => {
  it('records a failure so the banner can surface it', async () => {
    putMock.mockRejectedValue(new Error('Network Error'))
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    useProgramStore.getState().setCurrentProgram({ weeks: [] } as any)
    await waitFor(() => expect(useProgramStore.getState().programSaveError).toBeTruthy(),
                  { timeout: 5000 })
  })

  it('clears the error once a save succeeds again', async () => {
    useProgramStore.setState({ programSaveError: 'Network Error' })
    putMock.mockResolvedValue({ revision: 'rev-2' })
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    useProgramStore.getState().setCurrentProgram({ weeks: [] } as any)
    await waitFor(() => expect(useProgramStore.getState().programSaveError).toBeNull())
  })
})
