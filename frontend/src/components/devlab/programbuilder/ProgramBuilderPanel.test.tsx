// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter, Route, Routes, useLocation } from 'react-router-dom'
import type { ReactNode } from 'react'
import sessionsFixture from '@/mocks/fixtures/manual-sessions.json'
import tracksFixture from '@/mocks/fixtures/manual-tracks.json'
import { useProgramBuilderStore } from '@/store/programBuilderStore'
import { usePreviewStore } from '@/store/previewStore'
import { placeSession } from '@/lib/programBuilder'
import { TipProvider } from '@/components/shared/Tip'
import { ProgramBuilderPanel } from './ProgramBuilderPanel'

const api = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn(), put: vi.fn(), patch: vi.fn(), delete: vi.fn() }))
vi.mock('@/api/client', () => ({ apiClient: api }))

const [first, second] = sessionsFixture.list.sessions
const saved = tracksFixture.list.tracks[0]

function Where() {
  const at = useLocation()
  return <p data-testid="where">{at.pathname}{at.search}</p>
}

function mount(node: ReactNode) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(
    <QueryClientProvider client={client}>
      <MemoryRouter initialEntries={['/dev?tab=program']}>
        <TipProvider>
          <Routes>
            <Route path="/dev" element={node} />
            <Route path="*" element={<Where />} />
          </Routes>
        </TipProvider>
      </MemoryRouter>
    </QueryClientProvider>,
  )
}

beforeEach(() => {
  useProgramBuilderStore.getState().reset()
  usePreviewStore.getState().clear()
  api.get.mockImplementation((url: string) => Promise.resolve(
    url === '/manual/sessions' ? sessionsFixture.list : url === '/manual/tracks' ? tracksFixture.list : {}))
  api.post.mockImplementation((url: string) => Promise.resolve(
    url === '/manual/tracks/preview' ? tracksFixture.preview
      : url === '/programs/generate' ? { validation: { feasible: true }, weeks: [{ schedule: {} }] }
        : { track: saved }))
  api.put.mockResolvedValue({ track: saved })
  api.delete.mockResolvedValue({ removed: true })
})
afterEach(() => { cleanup(); vi.clearAllMocks() })

const cell = (day: string, week = 1) => screen.getByRole('group', { name: `${day}, week ${week}` })

describe('Dev Lab ▸ Program builder', () => {
  it('lists the saved sessions to lay out', async () => {
    mount(<ProgramBuilderPanel />)
    const shelf = await screen.findByRole('region', { name: 'Your sessions' })
    expect(within(shelf).getByText(first.name)).toBeTruthy()
    expect(within(shelf).getByText(second.name)).toBeTruthy()
  })

  it('draws the draft: a day of two sessions is one session of both, a light day says so', async () => {
    const store = useProgramBuilderStore.getState()
    const p = store.draft.phases[0].uid
    store.edit((d) => placeSession(placeSession(d, p, { week: 0, day: 0 }, first.id), p, { week: 0, day: 0 }, second.id))
    mount(<ProgramBuilderPanel />)
    await screen.findByRole('region', { name: 'Your sessions' })
    const monday = cell('Monday')
    expect(within(monday).getByText(first.name)).toBeTruthy()
    expect(within(monday).getByText(/One session of both/)).toBeTruthy()
    expect(within(monday).queryByRole('button', { name: /Add a session to/ })).toBeNull()
    fireEvent.click(within(monday).getByRole('button', { name: 'Light day, week 1, Monday' }))
    expect(within(monday).getByText('Light')).toBeTruthy()
    expect(within(cell('Tuesday')).getByText('Rest')).toBeTruthy()
  })

  it('duplicates and adds weeks, and says how they repeat', async () => {
    const store = useProgramBuilderStore.getState()
    store.edit((d) => placeSession(d, d.phases[0].uid, { week: 0, day: 2 }, first.id))
    mount(<ProgramBuilderPanel />)
    await screen.findByRole('region', { name: 'Your sessions' })
    expect(screen.getByText(/This week repeats for the 4 weeks of the phase/)).toBeTruthy()
    fireEvent.click(screen.getByRole('button', { name: 'Duplicate week 1' }))
    expect(within(cell('Wednesday', 2)).getByText(first.name)).toBeTruthy()
    expect(screen.getByText(/These 2 weeks repeat, in order, for the 4 weeks/)).toBeTruthy()
    fireEvent.change(screen.getByLabelText('A lighter week'), { target: { value: '4' } })
    expect(screen.getByText(/Week 4 of the phase is lighter/)).toBeTruthy()
  })

  it('adds a phase that starts from the one before, and switches to it', async () => {
    const store = useProgramBuilderStore.getState()
    store.edit((d) => placeSession(d, d.phases[0].uid, { week: 0, day: 0 }, first.id))
    mount(<ProgramBuilderPanel />)
    await screen.findByRole('region', { name: 'Your sessions' })
    fireEvent.click(screen.getByRole('button', { name: /Add phase/ }))
    const phases = within(screen.getByRole('group', { name: 'Choose a phase' })).getAllByRole('button')
    expect(phases).toHaveLength(2)
    expect(phases[1].textContent).toContain('wk 5–8')
    fireEvent.click(phases[1])
    expect(screen.getByRole('region', { name: 'Phase: Phase 2' })).toBeTruthy()
    expect(within(cell('Monday')).getByText(first.name)).toBeTruthy()
  })

  it('shows the server\'s reading and a problem at the day it names', async () => {
    api.post.mockImplementation((url: string) => Promise.resolve(url === '/manual/tracks/preview'
      ? { ok: false, track: null, problems: [{ phase: 0, week: 0, day: 2, field: null, message: 'This session is no longer among your saved ones.' }] }
      : {}))
    const store = useProgramBuilderStore.getState()
    store.edit((d) => placeSession(d, d.phases[0].uid, { week: 0, day: 2 }, 'gone'))
    mount(<ProgramBuilderPanel />)
    await screen.findByRole('region', { name: 'Your sessions' })
    expect(await within(cell('Wednesday')).findByText('This session is no longer among your saved ones.')).toBeTruthy()
  })

  it('saves the wire shape', async () => {
    const store = useProgramBuilderStore.getState()
    store.edit((d) => ({ ...placeSession(d, d.phases[0].uid, { week: 0, day: 0 }, first.id), name: 'Block' }))
    mount(<ProgramBuilderPanel />)
    await screen.findByRole('region', { name: 'Your sessions' })
    await within(screen.getByRole('region', { name: 'Summary' })).findByText('Week by week')
    fireEvent.click(screen.getByRole('button', { name: 'Save program' }))
    await waitFor(() => expect(api.post.mock.calls.some(([url]) => url === '/manual/tracks')).toBe(true))
    const [, body] = api.post.mock.calls.find(([url]) => url === '/manual/tracks')!
    expect(body.track.name).toBe('Block')
    expect(body.track.phases[0].template[0][0]).toEqual({ sessions: [first.id] })
    expect(JSON.stringify(body)).not.toContain('uid')
    await screen.findByRole('button', { name: 'Save changes' })
  })

  it('opens a saved program in the preview with the server\'s constraints, and says where to come back to', async () => {
    mount(<ProgramBuilderPanel />)
    const list = await screen.findByRole('region', { name: 'Saved programs' })
    fireEvent.click(await within(list).findByRole('button', { name: 'Preview' }))
    fireEvent.click(await screen.findByRole('button', { name: 'Preview program' }))
    await waitFor(() => expect(screen.getByTestId('where').textContent).toContain('/program/preview?back='))
    expect(decodeURIComponent(screen.getByTestId('where').textContent ?? '')).toContain(`/dev?tab=program&track=${saved.id}`)
    const [, body] = api.post.mock.calls.find(([url]) => url === '/programs/generate')!
    expect(body).toMatchObject({ philosophy_id: tracksFixture.list.packageId, track_id: saved.id, num_weeks: saved.totalWeeks })
    expect(body.constraints).toMatchObject(saved.startWith)
    expect(body.constraints.preferred_days).toBeUndefined()
    expect(usePreviewStore.getState().draft).toBeTruthy()
  })

  it('opens a saved program to edit', async () => {
    mount(<ProgramBuilderPanel />)
    const list = await screen.findByRole('region', { name: 'Saved programs' })
    fireEvent.click(await within(list).findByRole('button', { name: `Edit ${saved.name}` }))
    expect((screen.getByPlaceholderText('Strength block') as HTMLInputElement).value).toBe(saved.name)
    expect(within(screen.getByRole('group', { name: 'Choose a phase' })).getAllByRole('button')).toHaveLength(saved.phases.length)
  })
})
