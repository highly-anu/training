// @vitest-environment jsdom
/**
 * The method builder's screens against the answers the server recorded
 * (mocks/fixtures/methods.json, written by test_package_builder.py): the
 * group in the program builder's first step, the describe form, a build
 * running, built and failed.
 */
import { describe, it, expect, afterEach, beforeEach, vi } from 'vitest'
import { render, screen, cleanup, fireEvent, waitFor, within } from '@testing-library/react'
import { MemoryRouter, Route, Routes, useLocation } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import recorded from '@/mocks/fixtures/methods.json'
import type { Philosophy } from '@/api/types'

const api = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn(), delete: vi.fn(), put: vi.fn() }))
vi.mock('@/api/client', () => ({ apiClient: api }))

import { YourMethods } from './YourMethods'
import { DescribeMethod } from './DescribeMethod'
import { MethodBuildProgress } from './MethodBuildProgress'
import { useMethodDraft } from '@/store/methodDraftStore'
import { useBuilderStore } from '@/store/builderStore'

const METHOD = recorded.methods.methods[0]
// The card's button, by the method's name (which may hold a bracket).
const named = (name: string) => (text: string) => text.startsWith(name)

// jsdom has none, and the switch measures itself.
globalThis.ResizeObserver ??= class { observe() {} unobserve() {} disconnect() {} } as unknown as typeof ResizeObserver
const phil = { id: METHOD.id, name: METHOD.name, bias: [], core_principles: [], tracks: [] } as unknown as Philosophy

function answer(routes: Record<string, unknown>) {
  api.get.mockImplementation((path: string) => {
    const hit = Object.keys(routes).find((k) => path === k || path.startsWith(`${k}/`) || path.startsWith(`${k}?`))
    return hit ? Promise.resolve(routes[hit]) : Promise.resolve([])
  })
}

function Where() {
  const location = useLocation()
  return <p data-testid="where">{location.pathname + location.search}</p>
}

function mount(ui: React.ReactNode, at = '/program/new') {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  const spy = vi.spyOn(client, 'invalidateQueries')
  render(
    <QueryClientProvider client={client}>
      <MemoryRouter initialEntries={[at]}>
        <Routes><Route path="*" element={<>{ui}<Where /></>} /></Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  )
  return { client, invalidated: () => spy.mock.calls.map((c) => JSON.stringify(c[0]?.queryKey)) }
}

beforeEach(() => { vi.clearAllMocks(); useMethodDraft.getState().clear() })
afterEach(cleanup)

describe('Your methods, in the program builder', () => {
  it('lists the athlete\'s methods and the way to describe another', async () => {
    answer({ '/methods': recorded.methods })
    const onSelect = vi.fn()
    mount(<YourMethods philosophies={[phil]} selectedId={null} onSelect={onSelect} onDeleted={() => {}} />)
    fireEvent.click(await screen.findByRole('button', { name: named(METHOD.name) }))
    expect(onSelect).toHaveBeenCalledWith(phil)
    expect(screen.getByText('Yours')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: /Describe your own method/ })).toHaveAttribute('href', '/program/new/method')
    expect(screen.getByRole('link', { name: `Revise ${METHOD.name}` }))
      .toHaveAttribute('href', `/program/new/method?revise=${METHOD.id}`)
  })

  it('shows the build that is running in place of the card', async () => {
    answer({ '/methods': recorded.methodsWhileRunning })
    mount(<YourMethods philosophies={[]} selectedId={null} onSelect={() => {}} onDeleted={() => {}} />)
    expect(await screen.findByRole('link', { name: /Writing the method/ })).toHaveAttribute('href', '/program/new/method/build-1')
    expect(screen.queryByRole('link', { name: /Describe your own method/ })).not.toBeInTheDocument()
  })

  it('is absent for an account the builder is not on for', async () => {
    answer({ '/methods': { ...recorded.methods, available: false, reason: 'not_enabled', methods: [], builds: [] } })
    mount(<YourMethods philosophies={[]} selectedId={null} onSelect={() => {}} onDeleted={() => {}} />)
    await waitFor(() => expect(api.get).toHaveBeenCalled())
    expect(screen.queryByText('Your methods')).not.toBeInTheDocument()
  })

  it('keeps the methods and says why another cannot be built', async () => {
    answer({ '/methods': recorded.unavailable })
    mount(<YourMethods philosophies={[phil]} selectedId={null} onSelect={() => {}} onDeleted={() => {}} />)
    expect(await screen.findByText('Methods cannot be built right now.')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: named(METHOD.name) })).toBeInTheDocument()
  })

  it('deletes after asking, and tells the step', async () => {
    answer({ '/methods': recorded.methods })
    api.delete.mockResolvedValue({ removed: true })
    const onDeleted = vi.fn()
    const { invalidated } = mount(<YourMethods philosophies={[phil]} selectedId={METHOD.id} onSelect={() => {}} onDeleted={onDeleted} />)
    fireEvent.click(await screen.findByRole('button', { name: `Delete ${METHOD.name}` }))
    expect(api.delete).not.toHaveBeenCalled()
    fireEvent.click(await screen.findByRole('button', { name: 'Delete' }))
    await waitFor(() => expect(onDeleted).toHaveBeenCalledWith(METHOD.id))
    expect(api.delete).toHaveBeenCalledWith(`/methods/${METHOD.id}`)
    expect(invalidated()).toContain('["philosophies"]')
  })

  it('does not offer to delete the method the program runs on', async () => {
    answer({ '/methods': { ...recorded.methods, methods: [{ ...METHOD, inUse: true }] } })
    mount(<YourMethods philosophies={[phil]} selectedId={null} onSelect={() => {}} onDeleted={() => {}} />)
    fireEvent.click(await screen.findByRole('button', { name: `Delete ${METHOD.name}` }))
    expect(screen.queryByRole('alertdialog')).not.toBeInTheDocument()
    expect(screen.getByText(/your program runs on it/)).toBeInTheDocument()
  })
})

describe('Describe your own method', () => {
  const words = 'Three strength days a week and two easy runs, twelve weeks.'

  it('sends the description with the athlete\'s answers and goes to the build', async () => {
    answer({ '/methods': recorded.methods })
    api.post.mockResolvedValue(recorded.running)
    useBuilderStore.setState({ constraints: { ...useBuilderStore.getState().constraints, days_per_week: 5, session_time_minutes: 45 } })
    mount(<DescribeMethod revises={null} />, '/program/new/method')
    fireEvent.change(await screen.findByLabelText('Describe how you want to train'), { target: { value: words } })
    fireEvent.click(screen.getByRole('switch', { name: 'Look it up on the web' }))
    fireEvent.click(screen.getByRole('button', { name: /Build the method/ }))
    await waitFor(() => expect(screen.getByTestId('where')).toHaveTextContent('/program/new/method/build-1'))
    const [path, body] = api.post.mock.calls[0]
    expect(path).toBe('/methods/builds')
    expect(body).toMatchObject({ description: words, webSearch: true, answers: { days: 5, minutes: 45, level: 'intermediate' } })
    expect(body.answers.equipment).toEqual([])
    expect(useMethodDraft.getState().description).toBe(words)
  })

  it('does not send a description too short to mean anything', async () => {
    answer({ '/methods': recorded.methods })
    mount(<DescribeMethod revises={null} />)
    fireEvent.change(await screen.findByLabelText('Describe how you want to train'), { target: { value: 'Get fit.' } })
    fireEvent.click(screen.getByRole('button', { name: /Build the method/ }))
    expect(await screen.findByRole('alert')).toHaveTextContent(/at least 20 characters/)
    expect(api.post).not.toHaveBeenCalled()
  })

  it('goes to the build already running when that is why it was refused', async () => {
    answer({ '/methods': recorded.methods })
    api.post.mockRejectedValue(Object.assign(new Error('A method is already being built.'), {
      status: 409, body: { error: 'build_running', build: recorded.running.build } }))
    mount(<DescribeMethod revises={null} />)
    fireEvent.change(await screen.findByLabelText('Describe how you want to train'), { target: { value: words } })
    fireEvent.click(screen.getByRole('button', { name: /Build the method/ }))
    await waitFor(() => expect(screen.getByTestId('where')).toHaveTextContent('/program/new/method/build-1'))
  })

  it('says so when today\'s builds are used, and sends nothing', async () => {
    answer({ '/methods': { ...recorded.methods, limits: { ...recorded.methods.limits, remaining: 0 } } })
    mount(<DescribeMethod revises={null} />)
    expect(await screen.findByRole('alert')).toHaveTextContent("You have used today's builds. Try again tomorrow.")
    expect(screen.getByRole('button', { name: /Build the method/ })).toBeDisabled()
  })

  it('revises one of the athlete\'s methods with a note', async () => {
    answer({ '/methods': recorded.methods })
    api.post.mockResolvedValue(recorded.running)
    mount(<DescribeMethod revises={METHOD.id} />)
    fireEvent.change(await screen.findByLabelText(`What should change in ${METHOD.name}?`), { target: { value: 'Three walks instead of two.' } })
    fireEvent.click(screen.getByRole('button', { name: /Build the revision/ }))
    await waitFor(() => expect(api.post).toHaveBeenCalled())
    expect(api.post.mock.calls[0][1]).toMatchObject({ revise: { packageId: METHOD.id, note: 'Three walks instead of two.' } })
    expect(api.post.mock.calls[0][1]).not.toHaveProperty('description')
  })

  it('says a method to revise is gone', async () => {
    answer({ '/methods': recorded.methods })
    mount(<DescribeMethod revises="u0_gone" />)
    expect(await screen.findByText('That method is no longer among yours')).toBeInTheDocument()
  })
})

describe('A build', () => {
  it('says what it is doing while it runs', async () => {
    answer({ '/methods/builds': recorded.running })
    mount(<MethodBuildProgress buildId="build-1" />)
    expect(await screen.findByText('4 files written')).toBeInTheDocument()
    expect(screen.getByRole('status')).toHaveTextContent('Writing the method')
    expect(screen.getByText('4 files written')).toBeInTheDocument()
    expect(screen.getByText(/You can leave this page/)).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Stop building' })).toBeInTheDocument()
  })

  it('stops only after asking', async () => {
    answer({ '/methods/builds': recorded.running })
    const stopped = { build: { ...recorded.running.build, status: 'cancelled', error: { code: 'cancelled', message: 'Cancelled.' } } }
    api.post.mockImplementation(() => { answer({ '/methods/builds': stopped }); return Promise.resolve(stopped) })
    mount(<MethodBuildProgress buildId="build-1" />)
    fireEvent.click(await screen.findByRole('button', { name: 'Stop building' }))
    expect(api.post).not.toHaveBeenCalled()
    const dialog = await screen.findByRole('alertdialog')
    fireEvent.click(within(dialog).getByRole('button', { name: 'Stop building' }))
    await waitFor(() => expect(api.post).toHaveBeenCalledWith('/methods/builds/build-1/cancel'))
    expect(await screen.findByText('The build was stopped')).toBeInTheDocument()
  })

  it('shows the method once built, reads the lists again and builds a program from it', async () => {
    answer({ '/methods/builds': recorded.done, '/philosophies': [phil], '/frameworks': [] })
    useMethodDraft.getState().keep({ description: 'kept', pastedText: '', webSearch: false })
    const { invalidated } = mount(<MethodBuildProgress buildId="build-1" />, '/program/new/method/build-1')
    expect(await screen.findByRole('heading', { name: METHOD.name })).toBeInTheDocument()
    expect(screen.getByText(recorded.done.build.result!.summary)).toBeInTheDocument()
    await waitFor(() => expect(invalidated()).toEqual(expect.arrayContaining(['["philosophies"]', '["explore"]', '["modalities"]', '["equipment"]', '["methods"]'])))
    expect(useMethodDraft.getState().description).toBe('')
    expect(screen.getByRole('link', { name: 'Read the method' })).toHaveAttribute('href', `/explore?topic=philosophies&id=${METHOD.id}`)
    const build = screen.getByRole('button', { name: 'Build a program' })
    await waitFor(() => expect(build).not.toBeDisabled())
    fireEvent.click(build)
    await waitFor(() => expect(screen.getByTestId('where')).toHaveTextContent('/program/new'))
    expect(useBuilderStore.getState().selectedPhilosophyIds).toEqual([METHOD.id])
  })

  it('says why a method was not built, with what the checks still found', async () => {
    answer({ '/methods/builds': recorded.failed })
    mount(<MethodBuildProgress buildId="build-failed" />)
    expect(await screen.findByRole('alert')).toHaveTextContent(recorded.failed.build.error!.message)
    fireEvent.click(screen.getByRole('button', { name: 'What the checks still found' }))
    expect(await screen.findByText(recorded.failed.build.error!.problems![0].message)).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Try again' })).toHaveAttribute('href', '/program/new/method')
  })

  it('says a build that is not the athlete\'s could not be loaded', async () => {
    api.get.mockRejectedValue(Object.assign(new Error('Request failed with status code 404'), { status: 404 }))
    mount(<MethodBuildProgress buildId="nope" />)
    expect(await screen.findByText('Could not load this build')).toBeInTheDocument()
  })
})
