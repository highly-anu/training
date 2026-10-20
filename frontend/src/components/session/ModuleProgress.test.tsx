// @vitest-environment jsdom
/**
 * "Done as written" for a training-contract session: nothing for a session
 * without module progress; the two answers before one is given; the answer
 * once the log carries it.
 */
import { describe, it, expect, afterEach, vi } from 'vitest'
import { render, screen, cleanup, fireEvent, waitFor } from '@testing-library/react'
import { useBioStore } from '@/store/bioStore'
import { ModuleProgress } from '@/components/session/ModuleProgress'
import type { Session } from '@/api/types'

const post = vi.fn()
vi.mock('@/api/client', () => ({
  apiClient: {
    get: vi.fn().mockResolvedValue(null),
    post: (...args: unknown[]) => post(...args),
    put: vi.fn().mockResolvedValue(null),
    delete: vi.fn().mockResolvedValue(null),
  },
}))

const swing = { exercise: { id: 'wk_kb_swing_two_hand', name: 'Swing' }, load: { advances_module: true, target_rounds: 10 } }
const session = (exercises: unknown[]) => ({ modality: 'power', exercises }) as unknown as Session

afterEach(() => { cleanup(); post.mockReset(); useBioStore.setState({ sessionPerformanceLogs: {} }) })

describe('ModuleProgress', () => {
  it('shows nothing for a session no module progress rides on', () => {
    const { container } = render(<ModuleProgress session={session([{ exercise: { id: 'x' }, load: {} }])}
                                                  logKey="1-Monday" serverKey="1-Monday-0" />)
    expect(container.innerHTML).toBe('')
  })

  it('asks, sends the answer to the server key and shows what it wrote', async () => {
    post.mockResolvedValue({ exercises: { wk_kb_swing_two_hand: { sets: [], rounds: 10, clean: true, rpe: 6 } },
                             completedAt: '2026-10-21T05:00:00Z' })
    render(<ModuleProgress session={session([swing])} logKey="1-Monday" serverKey="1-Monday-0" />)
    fireEvent.change(screen.getByLabelText('RPE'), { target: { value: '6' } })
    fireEvent.click(screen.getByText('Clean, as written'))
    await waitFor(() => expect(screen.getByText(/RPE 6/)).toBeTruthy())
    expect(post).toHaveBeenCalledWith('/health/sessions/1-Monday-0/confirm', { clean: true, rpe: 6 })
    expect(useBioStore.getState().sessionPerformanceLogs['1-Monday'].exercises.wk_kb_swing_two_hand.clean).toBe(true)
  })

  it('reads a "not clean" answer back from the log', () => {
    useBioStore.setState({ sessionPerformanceLogs: { '1-Monday': {
      sessionKey: '1-Monday', notes: '', completedAt: 'x',
      exercises: { wk_kb_swing_two_hand: { sets: [], clean: false } } } } })
    render(<ModuleProgress session={session([swing])} logKey="1-Monday" serverKey="1-Monday-0" />)
    expect(screen.getByText(/Not clean/)).toBeTruthy()
  })
})
