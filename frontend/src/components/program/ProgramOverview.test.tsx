// @vitest-environment jsdom
/**
 * A phase card shows its own philosophy's words and nobody else's.
 *
 * The overview used to look phase text up in one map keyed by phase kind,
 * written from Uphill Athlete and Gym Jones, so a Wildman program's base phase
 * described Uphill's base period and its build phase named Gym Jones. The
 * text now comes from the stored goal's phase_sequence, matched by phase id.
 */
import { describe, it, expect, afterEach, vi } from 'vitest'
import { render, screen, cleanup, fireEvent } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { GeneratedProgram, WeekData } from '@/api/types'
import { buildPhaseCalendar } from '@/hooks/usePhaseCalendar'
import { ProgramOverview } from './ProgramOverview'

vi.mock('@/api/philosophies', () => ({
  usePhilosophies: () => ({ data: [{ id: 'wildman_kettlebell', name: 'Mark Wildman Kettlebell', tracks: [] }] }),
}))

const week = (n: number, phaseId: string, kind: WeekData['phase'], name: string): WeekData =>
  ({ week_number: n, week_in_phase: n, phase: kind, phase_id: phaseId, phase_name: name,
     track_id: 'general_practice', is_deload: false, schedule: {} }) as WeekData

function program(): GeneratedProgram {
  return {
    goal: {
      id: '_phil_wildman_kettlebell', name: 'Mark Wildman Kettlebell', description: '',
      priorities: {}, primary_sources: ['wildman_kettlebell'],
      track: { id: 'general_practice', name: 'General Practice', philosophy_id: 'wildman_kettlebell' },
      phase_sequence: [
        { phase_id: 'foundations', phase: 'base', name: 'Foundations', weeks: 1,
          focus: 'Deadlift, swing and get-up groove',
          description: 'The bottom of the complexity ladder.', adaptations: ['Hinge mechanics'],
          intensity: 'Anti-glycolic' },
        { phase_id: 'ladder', phase: 'build', name: 'The Ladder', weeks: 1,
          focus: 'Clean, press, snatch and jerk', description: 'Move up the ladder.' },
      ],
      minimum_prerequisites: {}, incompatible_with: [],
      framework_selection: { default_framework: 'kb_general_practice', alternatives: [] },
    },
    constraints: {},
    validation: { feasible: true, errors: [], warnings: [], info: [] },
    weeks: [week(1, 'foundations', 'base', 'Foundations'), week(2, 'ladder', 'build', 'The Ladder')],
    volume_summary: [],
  } as unknown as GeneratedProgram
}

function mount(p: GeneratedProgram) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  const { segments } = buildPhaseCalendar(p.weeks, p.goal)
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter><ProgramOverview program={p} segments={segments} /></MemoryRouter>
    </QueryClientProvider>,
  )
}

afterEach(cleanup)

describe('ProgramOverview phase cards', () => {
  it("shows the program's own phases and their text, never another philosophy's", () => {
    const { container } = mount(program())
    expect(screen.getAllByText('Foundations').length).toBeGreaterThan(0)
    expect(screen.getAllByText('The Ladder').length).toBeGreaterThan(0)
    for (const button of screen.getAllByText(/Details/)) fireEvent.click(button)
    expect(screen.getByText('The bottom of the complexity ladder.')).toBeInTheDocument()
    expect(screen.getByText('Move up the ladder.')).toBeInTheDocument()
    expect(screen.getByText('Anti-glycolic')).toBeInTheDocument()
    expect(container.textContent).not.toMatch(/Uphill|Gym Jones|Lydiard|CrossFit|Filly/)
  })

  it('shows no borrowed text for a program stored before phases had their own', () => {
    const old = program()
    old.weeks = old.weeks.map(({ phase_id: _id, phase_name: _n, ...w }) => w as WeekData)
    old.goal.phase_sequence = [{ phase: 'base', weeks: 1 }, { phase: 'build', weeks: 1 }]
    const { container } = mount(old)
    for (const button of screen.getAllByText(/Details/)) fireEvent.click(button)
    expect(screen.getAllByText(/No description is stored/).length).toBe(2)
    expect(container.textContent).not.toMatch(/Uphill|Gym Jones|Lydiard|CrossFit|Filly/)
  })
})
