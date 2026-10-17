// @vitest-environment jsdom
/**
 * Today says when a session tests the phase's standards, and what to beat:
 * each standard's best and the number for the next level, in the server's
 * words. On a day without a test there is no card at all.
 */
import { describe, it, expect, afterEach, vi } from 'vitest'
import { render, screen, cleanup } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { format } from 'date-fns'
import type { GeneratedProgram } from '@/api/types'
import { TestDayCard } from './TestDayCard'

const today = format(new Date(), 'EEEE')

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

afterEach(cleanup)

describe('TestDayCard', () => {
  it('shows each standard with its best and the number for the next level', () => {
    mount(program(true))
    expect(screen.getByText('Test today')).toBeTruthy()
    expect(screen.getByText(/In place of KB Pentathlon Timed Sets/)).toBeTruthy()
    expect(screen.getByText('72 reps')).toBeTruthy()
    expect(screen.getByText(/90 reps for intermediate/)).toBeTruthy()
    expect(screen.getByText(/First result · 60 reps for entry/)).toBeTruthy()
  })

  it('is absent on a day without a test', () => {
    const { container } = mount(program(false))
    expect(container.textContent).toBe('')
  })
})
