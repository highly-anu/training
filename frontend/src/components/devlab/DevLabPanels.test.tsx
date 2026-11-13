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
import { ReadinessPanel } from './ReadinessPanel'
import { HeatmapPanel } from './heatmap/HeatmapPanel'
import { WeekCalendar } from '@/components/program/WeekCalendar'
import portability from '@/mocks/fixtures/portability.json'

vi.mock('@/api/ontology', () => ({ useOntology: () => ({ data: undefined, isLoading: false }) }))
// The server's portability report as test_portability.py records it (the
// shipped packages, the scheduler's fixture and a copy colliding with it).
// A test may swap in another report (`served.report`).
const served = vi.hoisted(() => ({ report: null as unknown }))
vi.mock('@/api/devlab', async () => {
  const recorded = (await import('@/mocks/fixtures/portability.json')).default
  return { usePortability: () => ({ data: served.report ?? recorded, isLoading: false, error: null }) }
})

afterEach(() => {
  cleanup()
  served.report = null
})

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

describe('Builder readiness', () => {
  it('lays out the server\'s report', () => {
    mount(<ReadinessPanel />)
    expect(screen.getByText(portability.verdict)).toBeTruthy()
    for (const p of portability.packages) expect(screen.getByText(p.id)).toBeTruthy()
    const ready = portability.packages.filter((p) => p.ready).length
    expect(screen.getByText(new RegExp(`^${ready} of ${portability.packages.length} packages`))).toBeTruthy()
    expect(screen.getByText(/^Ids two packages declare — resolved silently/)).toBeTruthy()
    for (const g of portability.gaps) expect(screen.getByText(g.title)).toBeTruthy()
  })

  it('lists the foundation\'s steps in order, each with its gaps, and counts what is open', () => {
    mount(<ReadinessPanel />)
    for (const s of portability.steps) expect(screen.getByText(s.title)).toBeTruthy()
    const tracked = portability.gaps.filter((g) => g.status !== 'by_design')
    const open = tracked.filter((g) => g.status === 'open')
    const blocking = open.filter((g) => g.impact === 'blocks').length
    expect(screen.getByText(new RegExp(`${tracked.length - open.length} of ${tracked.length} gaps closed`))).toBeTruthy()
    expect(screen.getByText(new RegExp(`${blocking} open gaps? blocks? a built package`))).toBeTruthy()
    // 20.1 has no gap of its own: the roadmap's day closes it.
    expect(screen.getAllByText(`done ${portability.steps[0].done}`).length).toBeGreaterThan(0)
  })

  it('shows a closed gap with its day and the test that holds it', () => {
    const [first, ...rest] = portability.gaps
    served.report = {
      ...portability,
      gaps: [{ ...first, status: 'done', closed: '2026-11-20', evidence: ['test_package_gate.py::def test_gate'] }, ...rest],
    }
    mount(<ReadinessPanel />)
    expect(screen.getByText('done 2026-11-20')).toBeTruthy()
    expect(screen.getByText('test_package_gate.py::def test_gate')).toBeTruthy()
    expect(screen.queryByText(first.anchors[0])).toBeNull()
  })
})

describe('Builder readiness: a deployment without docs/', () => {
  it('shows the records it cannot read as unchecked, not missing', () => {
    const unread = new Set(['status', 'dossier'])
    served.report = {
      ...portability,
      unchecked: ['dossier', 'source_weeks', 'status'],
      packages: portability.packages.map((p) => ({
        ...p,
        files: p.files.map((f) => (f.id === 'source_weeks' ? { ...f, present: null } : f)),
        records: p.records.map((o) => (unread.has(o.id) ? { ...o, done: null } : o)),
      })),
    }
    mount(<ReadinessPanel />)
    expect(screen.getByText(/Not checkable here: Source dossier · source_weeks.yaml · Status/)).toBeTruthy()
    expect(screen.getAllByText(/\(\+1 not in this deployment\)/).length).toBe(portability.packages.length)
    expect(screen.getAllByLabelText('Source dossier: not checkable here').length).toBe(portability.packages.length)
    expect(screen.queryAllByLabelText('Source dossier: missing')).toHaveLength(0)
  })
})
