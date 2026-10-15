/**
 * A link into an earlier program (Log ▸ Linking) must keep its uid and leave
 * this program's completion marks alone: its legacy key, "1-Wednesday-0",
 * names a different session here.
 */
import { describe, it, expect, beforeEach, vi } from 'vitest'

const saveMatch = vi.fn()
const saveSessionLog = vi.fn()
vi.mock('@/api/health', () => ({
  saveMatch: (...a: unknown[]) => saveMatch(...a),
  saveSessionLog: (...a: unknown[]) => saveSessionLog(...a),
}))

import { useBioStore } from '@/store/bioStore'
import { useProfileStore } from '@/store/profileStore'

beforeEach(() => {
  saveMatch.mockReset()
  saveSessionLog.mockReset()
  useBioStore.setState({ workoutMatches: [], pendingMatches: [], sessionPerformanceLogs: {} })
})

describe('confirmMatch', () => {
  it('keeps the uid and skips completion for an earlier program', () => {
    const setSessionLog = vi.spyOn(useProfileStore.getState(), 'setSessionLog')
    useBioStore.getState().confirmMatch('ride', '1-Wednesday-0', { sessionUid: 'old:w0-Wednesday-0', markComplete: false })
    expect(saveMatch.mock.calls[0][0]).toMatchObject({ sessionKey: '1-Wednesday-0', sessionUid: 'old:w0-Wednesday-0' })
    expect(useBioStore.getState().workoutMatches[0].sessionUid).toBe('old:w0-Wednesday-0')
    expect(useBioStore.getState().sessionPerformanceLogs).toEqual({})
    expect(saveSessionLog).not.toHaveBeenCalled()
    expect(setSessionLog).not.toHaveBeenCalled()
  })

  it('marks the session complete for the current program, uid included', () => {
    const setSessionLog = vi.spyOn(useProfileStore.getState(), 'setSessionLog')
    useBioStore.getState().confirmMatch('lift', '1-Wednesday-0', { sessionUid: 'cur:w0-Wednesday-0' })
    expect(useBioStore.getState().workoutMatches[0].sessionUid).toBe('cur:w0-Wednesday-0')
    expect(useBioStore.getState().sessionPerformanceLogs['1-Wednesday-0'].completedAt).not.toBe('')
    expect(setSessionLog).toHaveBeenCalledWith('1-Wednesday', [true])
  })
})
