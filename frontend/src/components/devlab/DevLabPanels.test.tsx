// @vitest-environment jsdom
/**
 * Every Dev Lab panel renders against real /programs/generate?trace=1 answers
 * (src/mocks/fixtures/traced-programs.json, recorded by test_devlab_trace.py,
 * which also fails when the server's trace no longer has the recording's
 * shape). The Schedule step once crashed the page for every program: since
 * tracks, each week's phase names its framework, a path whose trace records no
 * `alternatives_checked`, and the panel mapped over it unguarded.
 */
import { describe, it, expect, afterEach, vi } from 'vitest'
import { render, screen, cleanup } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import type { TracedProgram, WeekData } from '@/api/types'
import recording from '@/mocks/fixtures/traced-programs.json'
import { SchedulerPanel } from './SchedulerPanel'
import { SessionsPanel } from './SessionsPanel'
import { PipelineFlowPanel } from './PipelineFlowPanel'
import { ValidationPanel } from './ValidationPanel'
import { ModelInteractionPanel } from './ModelInteractionPanel'
import { HeatmapPanel } from './heatmap/HeatmapPanel'
import { WeekCalendar } from '@/components/program/WeekCalendar'

vi.mock('@/api/ontology', () => ({ useOntology: () => ({ data: undefined, isLoading: false }) }))

afterEach(cleanup)

function mount(node: ReactNode) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>{node}</MemoryRouter>
    </QueryClientProvider>,
  )
}

const scenarios = Object.entries(recording.scenarios).map(
  ([name, s]) => [name, s.response as unknown as TracedProgram] as const,
)

describe.each(scenarios)('%s', (_name, program) => {
  const weeks = program.generation_trace!.weeks

  it('renders every step', () => {
    mount(<ValidationPanel validation={program.validation} />)
    mount(<SchedulerPanel weeks={weeks} />)
    mount(<PipelineFlowPanel program={program} weeks={weeks} />)
    mount(<SessionsPanel weeks={weeks} />)
    mount(<WeekCalendar weekData={program.weeks[0] as WeekData} isCurrentWeek={false} />)
    mount(<ModelInteractionPanel result={program} />)
    mount(
      <HeatmapPanel
        program={program}
        constraints={{ ...program.constraints, numWeeks: program.weeks.length }}
      />,
    )
  })

  it("says the week's phase named the framework", () => {
    mount(<SchedulerPanel weeks={weeks} />)
    expect(screen.getAllByText("Named by the week's phase:")).toHaveLength(weeks.length)
  })
})
