// @vitest-environment jsdom
/**
 * A shared link's page: <web>/s/<token> (docs/roadmap.md item 25).
 *
 * It is the web's first page outside sign-in: whoever has the link reads it.
 * The documents are the server's own answers (test_sharing.py --write).
 */
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { render, screen, cleanup, fireEvent, waitFor, within } from '@testing-library/react'
import { MemoryRouter, Routes, Route } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import recorded from '@/mocks/fixtures/shares.json'
import { useAuthStore } from '@/store/authStore'
import { useBuilderStore } from '@/store/builderStore'
import { saveRefusal } from '@/lib/shareRefusal'
import { SharedLink } from './SharedLink'

const getMock = vi.fn()
const postMock = vi.fn()
vi.mock('@/api/client', () => ({
  apiClient: { get: (...args: unknown[]) => getMock(...args), post: (...args: unknown[]) => postMock(...args), put: vi.fn(), delete: vi.fn() },
}))

function mount(token: string) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter initialEntries={[`/s/${token}`]}>
        <Routes>
          <Route path="/login" element={<p>login</p>} />
          <Route path="/program/new" element={<p>the builder</p>} />
          <Route path="/s/:token" element={<SharedLink />} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  )
}

beforeEach(() => {
  getMock.mockReset()
  postMock.mockReset()
  // Nobody is signed in: the page must not ask for it.
  useAuthStore.setState({ user: null, isLoading: false })
})
afterEach(cleanup)

describe('/s/:token', () => {
  it('shows a shared session to someone who is not signed in', async () => {
    getMock.mockResolvedValue(recorded.session)
    mount('tok_session')
    expect(await screen.findByRole('heading', { level: 1, name: recorded.session.title })).toBeInTheDocument()
    expect(getMock).toHaveBeenCalledWith('/shares/tok_session')
    expect(screen.queryByText('login')).toBeNull()
    const first = recorded.session.session.session.exercises[0].exercise.name
    expect(screen.getAllByText(first).length).toBeGreaterThan(0)
    expect(screen.getByText(`From ${recorded.session.session.method.name}`)).toBeInTheDocument()
  })

  it('offers the app, by the link\'s own token', async () => {
    getMock.mockResolvedValue(recorded.session)
    mount('tok_session')
    const open = await screen.findByRole('link', { name: /Open in the app/ })
    expect(open).toHaveAttribute('href', 'trainingcompanion://share?token=tok_session')
  })

  it('opens a movement in place, to the exercise the link carries', async () => {
    getMock.mockResolvedValue(recorded.session)
    mount('tok_session')
    const ea = recorded.session.session.session.exercises[0]
    const row = (await screen.findAllByRole('button', { expanded: false }))
      .find((b) => within(b).queryByText(ea.exercise.name))!
    fireEvent.click(row)
    expect(row).toHaveAttribute('aria-expanded', 'true')
    // The exercise's own heading: nothing was fetched for it.
    expect(await screen.findByRole('heading', { level: 2, name: ea.exercise.name })).toBeInTheDocument()
    expect(getMock).toHaveBeenCalledTimes(1)
    fireEvent.click(row)
    await waitFor(() => expect(row).toHaveAttribute('aria-expanded', 'false'))
  })

  it('says a revoked link is no longer shared', async () => {
    getMock.mockRejectedValue(Object.assign(new Error('This link is no longer shared.'), { status: 404 }))
    mount('gone')
    expect(await screen.findByText('This link is no longer shared')).toBeInTheDocument()
    expect(screen.queryByRole('link', { name: /Open in the app/ })).toBeNull()
  })

  it('offers a retry when the server could not be reached', async () => {
    getMock.mockRejectedValue(Object.assign(new Error('Network Error'), { status: undefined }))
    mount('tok_session')
    expect(await screen.findByText('The link could not be opened')).toBeInTheDocument()
  })

  it('shows a method as Explore lays one out, and asks a signed-out reader to sign in to save', async () => {
    getMock.mockResolvedValue({ ...recorded.method, availability: undefined })
    mount('tok_method')
    expect(await screen.findByRole('heading', { level: 1, name: recorded.method.title })).toBeInTheDocument()
    expect(screen.getByRole('heading', { level: 2, name: recorded.method.method.describe.name })).toBeInTheDocument()
    for (const m of recorded.method.methods) expect(screen.getAllByText(m.name).length).toBeGreaterThan(0)
    expect(screen.getByRole('link', { name: 'Sign in to save' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Save to your methods' })).toBeNull()
  })

  it('saves a method to a signed-in reader, and asks again for what they have', async () => {
    useAuthStore.setState({ user: { id: 'ben' } as never, isLoading: false })
    getMock.mockResolvedValue(recorded.method)
    postMock.mockResolvedValue({ ok: true, installed: recorded.method.availability.methods.map((m) => ({ id: m.id, name: m.name })) })
    mount('tok_method')
    expect((await screen.findAllByText('Not saved yet')).length).toBe(recorded.method.availability.methods.length)
    fireEvent.click(screen.getByRole('button', { name: 'Save to your methods' }))
    await waitFor(() => expect(postMock).toHaveBeenCalledWith('/shares/tok_method/save', { replace: false }))
    expect(await screen.findByRole('status')).toHaveTextContent('to your methods')
    // The page's document is read again: it now says what the reader has.
    await waitFor(() => expect(getMock.mock.calls.filter(([url]) => url === '/shares/tok_method').length).toBeGreaterThan(1))
  })

  it('never overwrites a version the reader changed without being told to', async () => {
    useAuthStore.setState({ user: { id: 'ben' } as never, isLoading: false })
    getMock.mockResolvedValue(recorded.method)
    postMock.mockRejectedValueOnce(Object.assign(new Error('You already have another version of this method.'),
      { status: 409, body: { error: 'different', methods: [{ id: 'x', name: 'Blocks' }] } }))
    postMock.mockResolvedValue({ ok: true, installed: [{ id: 'x', name: 'Blocks' }] })
    mount('tok_method')
    fireEvent.click(await screen.findByRole('button', { name: 'Save to your methods' }))
    fireEvent.click(await screen.findByRole('button', { name: 'Replace my version' }))
    await waitFor(() => expect(postMock).toHaveBeenLastCalledWith('/shares/tok_method/save', { replace: true }))
  })

  it('says why a save was refused', () => {
    expect(saveRefusal({ message: 'x', body: { busy: true } })).toMatch(/busy/)
    expect(saveRefusal({ message: 'x', body: { error: 'too_many_packages' } })).toMatch(/Remove one/)
    expect(saveRefusal({ message: 'x', body: { error: 'not_installable', olderEngine: true, name: 'Blocks' } }))
      .toBe('Blocks was written for an earlier version of the app and no longer passes its checks. Ask for a new link.')
    expect(saveRefusal({ message: 'x', body: { error: 'not_installable', name: 'Blocks', problems: [{ message: 'no track' }] } }))
      .toBe("Blocks did not pass the app's checks: no track")
    expect(saveRefusal({ message: 'Network Error' })).toBe('Network Error')
  })

  it('shows a program as its shape and the methods it needs, and builds only once they are saved', async () => {
    useAuthStore.setState({ user: { id: 'carl' } as never, isLoading: false })
    getMock.mockResolvedValue(recorded.program)
    mount('tok_program')
    expect(await screen.findByRole('heading', { level: 1, name: recorded.program.title })).toBeInTheDocument()
    expect(screen.getByText(`${recorded.program.program.weeks} weeks`)).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Save the methods it needs' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Build it for me/ })).toBeNull()
  })

  it('builds a ready program from its recipe, in the program builder', async () => {
    useAuthStore.setState({ user: { id: 'carl' } as never, isLoading: false })
    const a = recorded.program.availability
    getMock.mockResolvedValue({ ...recorded.program,
      availability: { ...a, ready: true, toSave: 0, methods: a.methods.map((m) => ({ ...m, state: 'have' })) } })
    mount('tok_program')
    fireEvent.click(await screen.findByRole('button', { name: /Build it for me/ }))
    expect(await screen.findByText('the builder')).toBeInTheDocument()
    const b = useBuilderStore.getState()
    expect(b.step).toBe(2)
    expect(b.sourceMode).toBe('philosophy')
    expect(b.selectedPhilosophyIds).toEqual([recorded.program.recipe.philosophy_id])
    expect(b.selectedTrackId).toBe(recorded.program.recipe.track_id)
    expect(b.numWeeks).toBe(recorded.program.recipe.num_weeks)
  })
})
