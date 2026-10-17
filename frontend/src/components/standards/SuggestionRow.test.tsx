// @vitest-environment jsdom
/**
 * A suggested result is saved only by the athlete: Save confirms it as
 * suggested, Correct sends what they typed instead, "Not a test" dismisses
 * it. The row reads in the server's words, against the result it follows.
 */
import { describe, it, expect, afterEach, vi } from 'vitest'
import { render, screen, cleanup, fireEvent } from '@testing-library/react'
import type { StandardSuggestion } from '@/api/types'
import { SuggestionRow } from './SuggestionRow'

const mutate = vi.fn()
vi.mock('@/api/standards', () => ({
  useDecideSuggestion: () => ({ mutate, isPending: false, isError: false }),
  useStandardSuggestions: () => ({ data: [] }),
}))

const fran = {
  id: 3, benchmarkId: 'wod_fran_minutes', name: 'Fran', domain: 'mixed_modal_conditioning',
  value: 4.9667, valueText: '4:58', level: 'advanced', levelIndex: 3, next: 'elite', nextText: '3:00',
  inputText: null, current: { valueText: '5:12' }, bestText: '5:12', isBest: true, origin: 'test_slot',
  status: 'pending', source: 'session', loggedOn: '2026-10-13', sessionUid: 'v:w3-Monday-0',
  sessionKey: '4-Monday', sessionName: 'Fran', exerciseId: 'thruster', resultId: null,
} as unknown as StandardSuggestion

afterEach(() => { cleanup(); mutate.mockReset() })

describe('SuggestionRow', () => {
  it('reads in the server\'s words', () => {
    render(<SuggestionRow suggestion={fran} />)
    expect(screen.getByText('4:58')).toBeTruthy()
    expect(screen.getByText(/new best/)).toBeTruthy()
    expect(screen.getByText(/Tue 13 Oct/)).toBeTruthy()
  })

  it('saves as suggested', () => {
    render(<SuggestionRow suggestion={fran} />)
    fireEvent.click(screen.getByText('Save result'))
    expect(mutate.mock.calls[0][0]).toEqual({ id: 3, action: 'confirm', text: undefined })
  })

  it('saves what the athlete corrected it to', () => {
    render(<SuggestionRow suggestion={fran} />)
    fireEvent.click(screen.getByText('Correct'))
    const input = screen.getByLabelText('Correct Fran')
    fireEvent.change(input, { target: { value: '4:55' } })
    fireEvent.keyDown(input, { key: 'Enter' })
    expect(mutate.mock.calls[0][0]).toEqual({ id: 3, action: 'confirm', text: '4:55' })
  })

  it('"Not a test" dismisses it', () => {
    render(<SuggestionRow suggestion={fran} />)
    fireEvent.click(screen.getByText('Not a test'))
    expect(mutate.mock.calls[0][0]).toEqual({ id: 3, action: 'dismiss' })
  })
})
