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
import { SharedLink } from './SharedLink'

const getMock = vi.fn()
vi.mock('@/api/client', () => ({
  apiClient: { get: (...args: unknown[]) => getMock(...args), post: vi.fn(), put: vi.fn(), delete: vi.fn() },
}))

function mount(token: string) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter initialEntries={[`/s/${token}`]}>
        <Routes>
          <Route path="/login" element={<p>login</p>} />
          <Route path="/s/:token" element={<SharedLink />} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  )
}

beforeEach(() => {
  getMock.mockReset()
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

  it('names a method or a program until their pages land', async () => {
    getMock.mockResolvedValue(recorded.program)
    mount('tok_program')
    expect(await screen.findByRole('heading', { level: 1, name: recorded.program.title })).toBeInTheDocument()
    expect(screen.getByText(recorded.program.methods[0].name)).toBeInTheDocument()
  })
})
