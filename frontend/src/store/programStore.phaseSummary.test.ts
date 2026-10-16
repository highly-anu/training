/**
 * A save answers with the phase summary of the weeks it saved, and the store
 * shows it — but only while that copy is still the one on screen. Before this,
 * a move, a swap or a spliced regenerate left the Overview showing the summary
 * of the weeks as they were (or, after a partial regenerate, of the tail alone).
 */
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { useProgramStore } from '@/store/programStore'
import type { GeneratedProgram, PhaseSummary } from '@/api/types'

const putMock = vi.fn()
vi.mock('@/api/client', () => ({
  apiClient: {
    get: vi.fn().mockResolvedValue(null),
    post: vi.fn().mockResolvedValue(null),
    put: (...args: unknown[]) => putMock(...args),
    delete: vi.fn().mockResolvedValue(null),
  },
}))

const summary = [{ phase_id: 'base', name: 'Base', changes: [] }] as unknown as PhaseSummary[]
const program = (n: number) => ({ weeks: Array.from({ length: n }, () => ({})) }) as unknown as GeneratedProgram

beforeEach(() => {
  putMock.mockReset()
  useProgramStore.setState({ currentProgram: null, revision: 'r1', programSaveError: null })
})

describe('programStore phase summary', () => {
  it('applies the summary the save answers with', async () => {
    putMock.mockResolvedValue({ saved: true, revision: 'r2', phaseSummary: summary })
    useProgramStore.getState().setCurrentProgram(program(2))
    await vi.waitFor(() => expect(useProgramStore.getState().currentProgram?.phase_summary).toEqual(summary))
    expect(putMock.mock.calls[0][1]).not.toHaveProperty('phaseSummary')
  })

  it('leaves a newer copy alone', async () => {
    let resolve: (v: unknown) => void = () => {}
    putMock.mockReturnValue(new Promise((r) => { resolve = r }))
    useProgramStore.getState().setCurrentProgram(program(2))
    const newer = program(3)
    useProgramStore.setState({ currentProgram: newer })
    resolve({ saved: true, revision: 'r2', phaseSummary: summary })
    await vi.waitFor(() => expect(useProgramStore.getState().revision).toBe('r2'))
    expect(useProgramStore.getState().currentProgram).toBe(newer)
  })
})
