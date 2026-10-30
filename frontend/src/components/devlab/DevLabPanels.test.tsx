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
import portability from '@/mocks/fixtures/portability.json'

vi.mock('@/api/ontology', () => ({ useOntology: () => ({ data: undefined, isLoading: false }) }))
// The server's portability report as test_portability.py records it (the
// shipped packages, the scheduler's fixture and a copy colliding with it).
vi.mock('@/api/devlab', async () => {
  const report = (await import('@/mocks/fixtures/portability.json')).default
  return { usePortability: () => ({ data: report, isLoading: false, error: null }) }
})

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

  it('says what placed each week', () => {
    mount(<SchedulerPanel weeks={weeks} />)
    if (program.generation_trace!.philosophy_mode === 'training_contract') {
      expect(screen.getAllByText(/Placed by the training contract/)).toHaveLength(weeks.length)
    } else if (weeks.every((w) => w.scheduler.week_template)) {
      expect(screen.getAllByText(/Written by the source's week/)).toHaveLength(weeks.length)
    } else {
      expect(screen.getAllByText("Named by the week's phase:")).toHaveLength(weeks.length)
    }
  })
})

describe('Model Interactions: portability', () => {
  it('lays out the server\'s report', () => {
    mount(<ModelInteractionPanel />)
    expect(screen.getByText(portability.verdict)).toBeTruthy()
    for (const p of portability.packages) expect(screen.getByText(p.id)).toBeTruthy()
    const ready = portability.packages.filter((p) => p.ready).length
    expect(screen.getByText(new RegExp(`^${ready} of ${portability.packages.length} packages`))).toBeTruthy()
    expect(screen.getByText(/resolved silently/)).toBeTruthy()
    for (const g of portability.gaps) expect(screen.getByText(g.title)).toBeTruthy()
  })
})
