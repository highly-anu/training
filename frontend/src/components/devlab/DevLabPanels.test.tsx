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
import modelMap from '@/mocks/fixtures/model-map.json'
import impacts from '@/mocks/fixtures/constraint-impact.json'
import { ImpactResult } from './ImpactPanel'
import type { ConstraintImpact } from '@/api/types'

vi.mock('@/api/ontology', () => ({ useOntology: () => ({ data: undefined, isLoading: false }) }))
// The server's portability report as test_portability.py records it (the
// shipped packages, the scheduler's fixture and a copy colliding with it).
// A test may swap in another report (`served.report`).
const served = vi.hoisted(() => ({ report: null as unknown }))
vi.mock('@/api/devlab', async () => {
  const recorded = (await import('@/mocks/fixtures/portability.json')).default
  // The model map as test_model_map.py records it.
  const map = (await import('@/mocks/fixtures/model-map.json')).default
  return {
    usePortability: () => ({ data: served.report ?? recorded, isLoading: false, error: null }),
    useModelMap: () => ({ data: map, isLoading: false, error: null }),
  }
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
    const mode = program.generation_trace!.philosophy_mode
    if (mode === 'composition') {
      expect(screen.getAllByText(/Several tracks on one week/)).toHaveLength(weeks.length)
    } else if (mode === 'training_contract') {
      expect(screen.getAllByText(/Placed by the training contract/)).toHaveLength(weeks.length)
    } else if (weeks.every((w) => w.scheduler.week_template)) {
      expect(screen.getAllByText(/Written by the source's week/)).toHaveLength(weeks.length)
    } else {
      expect(screen.getAllByText("Named by the week's phase:")).toHaveLength(weeks.length)
    }
  })

  // What each engine decided (roadmap 20.9), laid out by the Schedule step.
  it('lays out what the engine decided', () => {
    mount(<SchedulerPanel weeks={weeks} />)
    const week = weeks[0]
    const decided = [week.scheduler, ...Object.values(week.lane_weeks ?? {}).map((l) => l.scheduler)]
    for (const scheduler of decided) {
      const contract = scheduler?.contract_week
      if (contract) {
        for (const m of contract.modules) expect(screen.getAllByText(m.id).length).toBeGreaterThan(0)
        expect(screen.getByText(`Placement — the best of ${contract.placement.considered} looked at`)).toBeTruthy()
        expect(screen.getByText(/Same modality on days back to back/)).toBeTruthy()
      }
      const template = scheduler?.template
      if (template) {
        const picked = Object.values(template.days).flatMap((d) => d.asked).filter((p) => p.picked)
        for (const p of picked) expect(screen.getAllByText(p.picked!).length).toBeGreaterThan(0)
        if (template.dropped.length) expect(screen.getByText(template.dropped.join(', '))).toBeTruthy()
      }
    }
    for (const key of Object.keys(week.lane_weeks ?? {})) expect(screen.getByText(key)).toBeTruthy()
    for (const t of week.tests?.skipped ?? []) {
      expect(screen.getAllByText((t.archetypes ?? []).join(', ')).length).toBeGreaterThan(0)
    }
  })

  it('the flow follows the engine that built the week', () => {
    mount(<PipelineFlowPanel program={program} weeks={weeks} />)
    const week = weeks[0]
    const first = Object.values(week.sessions).flat()[0]
    const lane = first?.lane_key ? week.lane_weeks?.[first.lane_key] : undefined
    const engine = week.engine === 'composition' ? lane?.engine : week.engine
    if (engine === 'training_contract') {
      expect(screen.getByText('③ ④ CONTRACT — MODULES AND PLACEMENT')).toBeTruthy()
      expect(screen.queryByText('No allocation trace.')).toBeNull()
    } else if (engine === 'week_templates') {
      expect(screen.getByText('③ ④ WEEK TEMPLATE — THE DAY AND ITS POOLS')).toBeTruthy()
      expect(screen.queryByText('No allocation trace.')).toBeNull()
    } else {
      expect(screen.getByText('③ ALLOCATION')).toBeTruthy()
    }
  })

  it('walks the days in the order of the week', () => {
    mount(<PipelineFlowPanel program={program} weeks={weeks} />)
    const order = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
    const shown = screen.getAllByRole('button').map((b) => b.textContent ?? '').filter((t) => order.includes(t))
    expect(shown).toEqual([...shown].sort((a, b) => order.indexOf(a) - order.indexOf(b)))
    expect(shown.length).toBeGreaterThan(0)
  })
})

// Two real POST /dev/constraint-impact answers (test_constraint_impact.py --write).
describe('Impact', () => {
  const heldBack = impacts.held_back as unknown as ConstraintImpact
  const refused = impacts.refused as unknown as ConstraintImpact

  it('counts what the constraints change, by cause, and lists the direct changes', () => {
    mount(<ImpactResult impact={heldBack} />)
    expect(screen.getAllByText(String(heldBack.sessions!.changed)).length).toBeGreaterThan(0)
    for (const cause of heldBack.lifted ?? []) {
      expect(screen.getAllByText(heldBack.lifts![cause]).length).toBeGreaterThan(0)
    }
    const direct = (heldBack.changes ?? []).filter((c) => !c.knock_on)
    expect(screen.getAllByRole('listitem').length).toBeGreaterThanOrEqual(direct.length)
    for (const r of heldBack.restore?.equipment ?? []) {
      expect(screen.getAllByText(new RegExp(` · ${r.changes}$`, 'm')).length).toBeGreaterThan(0)
    }
  })

  it('says what alone would let a refused request generate', () => {
    mount(<ImpactResult impact={refused} />)
    expect(screen.getByText('The request is refused')).toBeTruthy()
    for (const u of refused.unblocked_by ?? []) expect(screen.getByText(u.text)).toBeTruthy()
  })
})

describe('Model Interactions', () => {
  it('reads the map one engine at a time, starting with the one most tracks run on', () => {
    mount(<ModelInteractionPanel />)
    const busiest = Object.entries(modelMap.usage).sort(([, a], [, b]) => b.tracks - a.tracks)[0][0]
    const tab = screen.getByRole('tab', { selected: true })
    expect(tab.textContent).toContain(modelMap.engines[busiest as keyof typeof modelMap.engines])
    const own = modelMap.edges.filter((e) => e.engine === busiest)
    const shared = modelMap.edges.filter((e) => e.engine === null)
    for (const e of [...own, ...shared]) expect(screen.getAllByText(e.title).length).toBeGreaterThan(0)
    // Another engine's interactions are not on this path.
    for (const e of modelMap.edges.filter((x) => x.engine && x.engine !== busiest)) {
      expect(screen.queryByText(e.title)).toBeNull()
    }
    // The engine's own interaction is the one opened, with the code that holds it.
    for (const a of own[0].anchors) expect(screen.getByText(a)).toBeTruthy()
  })

  it('says how much each engine is used', () => {
    mount(<ModelInteractionPanel />)
    const busiest = Object.entries(modelMap.usage).sort(([, a], [, b]) => b.tracks - a.tracks)[0]
    expect(screen.getByText(new RegExp(`^${busiest[1].tracks} tracks run on it: ${busiest[1].packages.join(', ')}\\.$`))).toBeTruthy()
  })

  it('lists what can be written where', () => {
    mount(<ModelInteractionPanel />)
    for (const row of modelMap.authoring) expect(screen.getByText(row.type)).toBeTruthy()
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
