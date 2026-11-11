// @vitest-environment jsdom
import { describe, it, expect, vi, beforeEach } from 'vitest'

interface Shown {
  action?: { label: string; onClick: () => void }
  onAutoClose?: () => void
  onDismiss?: () => void
}
const shown: { message: string; options: Shown }[] = []

vi.mock('sonner', () => {
  const show = (message: string, options: Shown) => { shown.push({ message, options }) }
  return { toast: Object.assign(show, { error: show }) }
})

import { toast } from './toast'
import { onAnnounce } from './announce'

beforeEach(() => { shown.length = 0 })

describe('toast.undo', () => {
  it('commits when the window closes without an undo', () => {
    const undo = vi.fn(), commit = vi.fn()
    toast.undo('Workout removed', { undo, commit })
    expect(shown[0].message).toBe('Workout removed')
    expect(shown[0].options.action?.label).toBe('Undo')
    shown[0].options.onAutoClose?.()
    expect(commit).toHaveBeenCalledTimes(1)
    expect(undo).not.toHaveBeenCalled()
  })

  it('an undo puts it back and the write never happens', () => {
    const undo = vi.fn(), commit = vi.fn()
    toast.undo('Workout removed', { undo, commit })
    shown[0].options.action?.onClick()
    // Sonner dismisses the toast after its action; that must not commit.
    shown[0].options.onDismiss?.()
    shown[0].options.onAutoClose?.()
    expect(undo).toHaveBeenCalledTimes(1)
    expect(commit).not.toHaveBeenCalled()
  })

  it('settles once, however it closes', () => {
    const commit = vi.fn()
    toast.undo('Workout removed', { undo: vi.fn(), commit })
    shown[0].options.onDismiss?.()
    shown[0].options.onAutoClose?.()
    window.dispatchEvent(new Event('pagehide'))
    expect(commit).toHaveBeenCalledTimes(1)
  })

  it('leaving the page inside the window commits', () => {
    const commit = vi.fn()
    toast.undo('Workout removed', { undo: vi.fn(), commit })
    window.dispatchEvent(new Event('pagehide'))
    expect(commit).toHaveBeenCalledTimes(1)
  })

  it('says the removal and the undo to a screen reader', () => {
    const said: string[] = []
    const off = onAnnounce((m) => said.push(m))
    toast.undo('Session removed', { undo: vi.fn() })
    shown[0].options.action?.onClick()
    off()
    expect(said).toEqual(['Session removed. Undo is available.', 'Restored.'])
  })
})

describe('toast.failed', () => {
  it('offers the retry it was given', () => {
    const retry = vi.fn()
    toast.failed('Could not save', retry)
    expect(shown[0].options.action?.label).toBe('Try again')
    shown[0].options.action?.onClick()
    expect(retry).toHaveBeenCalled()
  })
})
