import { describe, it, expect } from 'vitest'
import { loadPhase, reloadFailed, errorMessage } from './loadPhase'

describe('loadPhase', () => {
  it('content on screen is never replaced by a reload or its failure', () => {
    expect(loadPhase(true, true, null)).toBe('content')
    expect(loadPhase(true, false, new Error('offline'))).toBe('content')
  })

  it('before the first answer: loading, then failed, then empty', () => {
    expect(loadPhase(false, true, null)).toBe('loading')
    expect(loadPhase(false, true, new Error('x'))).toBe('loading')
    expect(loadPhase(false, false, new Error('x'))).toBe('failed')
    expect(loadPhase(false, false, null)).toBe('empty')
  })

  it('a failed reload is said beside the content', () => {
    expect(reloadFailed(true, new Error('x'))).toBe(true)
    expect(reloadFailed(false, new Error('x'))).toBe(false)
    expect(reloadFailed(true, null)).toBe(false)
  })

  it('reads a message from whatever was thrown', () => {
    expect(errorMessage(new Error('offline'))).toBe('offline')
    expect(errorMessage('plain words')).toBe('plain words')
    expect(errorMessage(null)).toBeUndefined()
  })
})
