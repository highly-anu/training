// @vitest-environment jsdom
/**
 * Today says when a session tests the phase's standards, and what to beat:
 * each standard's best and the number for the next level, in the server's
 * words; once the session is logged, each result comes back on the card to
 * save. On a day without a test there is no card at all.
 */
import { describe, it, expect, afterEach, vi } from 'vitest'
import { render, screen, cleanup } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { format } from 'date-fns'
import type { GeneratedProgram } from '@/api/types'
import { TestDayCard } from './TestDayCard'

const today = format(new Date(), 'EEEE')
let suggestions: unknown[] = []

vi.mock('@/api/standards', () => ({
  useStandards: () => ({ data: [
    { id: 'kb_pentathlon_clean_reps', name: 'KB Pentathlon — Clean', domain: 'strength_endurance',
      standardsText: { entry: '60 reps' } },
    { id: 'kb_pentathlon_jerk_reps', name: 'KB Pentathlon — Jerk', domain: 'strength_endurance',
      standardsText: { entry: '60 reps' } },
  ] }),
  useStandardResults: () => ({ data: { standards: {
    kb_pentathlon_clean_reps: {
      current: { valueText: '72 reps', level: 'entry', next: 'intermediate', nextText: '90 reps' },
      best: { value: 72, valueText: '72 reps', level: 'entry' },
    },
  } } }),
  useStandardSuggestions: () => ({ data: suggestions }),
  useDecideSuggestion: () => ({ mutate: vi.fn(), isPending: false, isError: false }),
}))

function program(withTest: boolean): GeneratedProgram {
  const session = {
    modality: 'strength_endurance', archetype: { id: 'kb_pentathlon_test', name: 'KB Pentathlon (IKMF) — Test' },
    exercises: [],
    ...(withTest ? { test: { archetype: 'kb_pentathlon_test',
                             standards: ['kb_pentathlon_clean_reps', 'kb_pentathlon_jerk_reps'],
                             instead_of: { name: 'KB Pentathlon Timed Sets' } } } : {}),
  }
  return { weeks: [{ week_number: 8, schedule: { [today]: [session] } }] } as unknown as GeneratedProgram
}

function mount(p: GeneratedProgram) {
  const qc = new QueryClient()
  return render(<QueryClientProvider client={qc}><MemoryRouter><TestDayCard program={p} weekIndex={0} /></MemoryRouter></QueryClientProvider>)
}

afterEach(() => { cleanup(); suggestions = [] })

describe('TestDayCard', () => {
  it('shows each standard with its best and the number for the next level', () => {
    mount(program(true))
    expect(screen.getByText('Test today')).toBeTruthy()
    expect(screen.getByText(/In place of KB Pentathlon Timed Sets/)).toBeTruthy()
    expect(screen.getByText('72 reps')).toBeTruthy()
    expect(screen.getByText(/90 reps for intermediate/)).toBeTruthy()
    expect(screen.getByText(/First result · 60 reps for entry/)).toBeTruthy()
  })

  it('shows a logged result to save under its standard', () => {
    suggestions = [{
      id: 7, benchmarkId: 'kb_pentathlon_jerk_reps', name: 'KB Pentathlon — Jerk', domain: 'strength_endurance',
      value: 81, valueText: '81 reps', level: 'entry', levelIndex: 1, inputText: null, current: null,
      bestText: null, isBest: true, origin: 'test_slot', status: 'pending', sessionKey: `8-${today}`,
      sessionName: 'KB Pentathlon (IKMF) — Test', loggedOn: null,
    }, {
      id: 8, benchmarkId: 'kb_pentathlon_clean_reps', name: 'KB Pentathlon — Clean', domain: 'strength_endurance',
      value: 70, valueText: '70 reps', origin: 'test_slot', status: 'pending', sessionKey: `7-${today}`,
    }]
    mount(program(true))
    expect(screen.getByText('81 reps')).toBeTruthy()
    expect(screen.getAllByText('Save result')).toHaveLength(1)
    expect(screen.queryByText('70 reps')).toBeNull()   // last week's test, not today's
  })

  it('is absent on a day without a test', () => {
    const { container } = mount(program(false))
    expect(container.textContent).toBe('')
  })
})
