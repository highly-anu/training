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

describe('ProgramOverview phase changes', () => {
  const item = (id: string, name: string, modality: string, sessions: number, status: 'new' | 'continued' | null) =>
    ({ id, name, modality, sessions, status })

  function withSummary(): GeneratedProgram {
    const p = program()
    p.phase_summary = [
      { phase_id: 'foundations', name: 'Foundations', kind: 'base', week_start: 1, week_end: 1, weeks: 1,
        deload_weeks: 0, sessions_per_week: { power: 2 }, minutes_per_week: { first: 90, last: 90, mean: 90 },
        intensity: {}, archetypes: [item('swing_day', 'Swing Day', 'power', 2, null)],
        exercises: [item('kb_swing', 'Swing', 'power', 2, null)], lifts: [],
        dropped: { archetypes: [], exercises: [] }, changes: [] },
      { phase_id: 'ladder', name: 'The Ladder', kind: 'build', week_start: 2, week_end: 2, weeks: 1,
        deload_weeks: 0, sessions_per_week: { power: 1, max_strength: 1 },
        minutes_per_week: { first: 120, last: 120, mean: 120 }, intensity: {},
        archetypes: [item('swing_day', 'Swing Day', 'power', 1, 'continued'),
                     item('double_press', 'Double Press', 'max_strength', 1, 'new')],
        exercises: [item('kb_press', 'Double KB Press', 'max_strength', 1, 'new')],
        lifts: [{ id: 'kb_press', name: 'Double KB Press', first_kg: 24, last_kg: 28 }],
        dropped: { archetypes: [], exercises: [{ id: 'kb_swing', name: 'Swing', modality: 'power' }] },
        changes: ['Max strength enters, 1×/week'] },
    ]
    return p
  }

  it("lays out the server's changes, the new sessions and the lifts", () => {
    mount(withSummary())
    expect(screen.getByText('Max strength enters, 1×/week')).toBeInTheDocument()
    expect(screen.getByText('+ Double Press')).toBeInTheDocument()
    expect(screen.getByText(/24 kg/)).toBeInTheDocument()
    expect(screen.getByText('How the phases change')).toBeInTheDocument()
  })

  it('reads the matrix by session or by exercise', () => {
    mount(withSummary())
    const table = screen.getByRole('table')
    expect(table.textContent).toMatch(/Swing Day/)
    fireEvent.click(screen.getByRole('tab', { name: 'Exercises' }))
    expect(screen.getByRole('table').textContent).toMatch(/Double KB Press/)
  })

  it('shows nothing extra without a summary', () => {
    mount(program())
    expect(screen.queryByText('How the phases change')).toBeNull()
  })
})
