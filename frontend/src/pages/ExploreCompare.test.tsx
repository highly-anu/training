// @vitest-environment jsdom
/**
 * Explore ▸ Philosophies ▸ Compare: the landing picks two or three, the URL
 * carries them (?compare=), the page lays out the server's comparison, and
 * the For you rows run one philosophy after another. The document and the
 * for-me answers are recorded from the server (data/philosophy_compare_fixture.json, test_explore_compare.py --write).
 */
import { describe, it, expect, afterEach, beforeEach, vi } from 'vitest'
import { render, cleanup, screen, fireEvent, waitFor, within } from '@testing-library/react'
import { MemoryRouter, useLocation } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Explore } from '@/pages/Explore'
import { useAuthStore } from '@/store/authStore'
import recorded from '../../../data/philosophy_compare_fixture.json'
import type { PhilosophyCompare, PhilosophyForMe } from '@/api/types'

const DOC = recorded.compare as unknown as PhilosophyCompare
const FOR_ME = recorded.forMe as unknown as Record<string, PhilosophyForMe>
const PHILOSOPHIES = DOC.philosophies.map((g) => ({ id: g.id, name: g.name, bias: g.bias, tracks: [] }))

const RESPONSES: Record<string, unknown> = {
  '/philosophies': PHILOSOPHIES, '/frameworks': [], '/modalities': [], '/archetypes': [], '/exercises': [],
  '/explore/links': null, '/philosophies/glance': DOC.philosophies, '/similarity': {},
  '/philosophies/compare': DOC,
}

const pending: Array<{ url: string; resolve: () => void }> = []
const post = vi.fn((url: string) => new Promise((resolve) => {
  const id = url.split('/')[2]
  pending.push({ url, resolve: () => resolve(FOR_ME[id]) })
}))

vi.mock('@/api/client', () => ({
  apiClient: {
    get: vi.fn((url: string) => Promise.resolve(RESPONSES[url] ?? null)),
    post: (url: string) => post(url),
  },
}))

function Where() {
  const l = useLocation()
  return <span data-testid="where">{l.pathname + l.search}</span>
}
const location = () => decodeURIComponent(screen.getByTestId('where').textContent ?? '')

function wrap(route: string) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter initialEntries={[route]}><Explore /><Where /></MemoryRouter>
    </QueryClientProvider>,
  )
}

beforeEach(() => {
  pending.length = 0
  post.mockClear()
  useAuthStore.setState({ user: { id: 'local-dev-user', email: 'dev@local' } as never })
})
afterEach(cleanup)

const [UPHILL, GYM, HORSEMEN] = DOC.philosophies

describe('Explore ▸ Compare', () => {
  it('the landing picks two, then opens them side by side', async () => {
    wrap('/explore')
    fireEvent.click(await screen.findByRole('button', { name: /Compare/ }))
    const compare = screen.getByRole('button', { name: /^Compare\s*$/ })
    expect((compare as HTMLButtonElement).disabled).toBe(true)

    fireEvent.click(screen.getByRole('button', { name: new RegExp(UPHILL.name.slice(0, 12)) }))
    fireEvent.click(screen.getByRole('button', { name: new RegExp(GYM.name.slice(0, 8)) }))
    fireEvent.click(screen.getByRole('button', { name: /^Compare 2$/ }))
    expect(location()).toBe(`/explore?topic=philosophies&compare=${UPHILL.id},${GYM.id}`)
  })

  it('a fourth cannot be picked', async () => {
    wrap('/explore')
    fireEvent.click(await screen.findByRole('button', { name: /Compare/ }))
    for (const g of DOC.philosophies) {
      fireEvent.click(screen.getByRole('button', { name: new RegExp(g.name.slice(0, 8)) }))
    }
    expect(screen.getByRole('button', { name: /^Compare 3$/ })).toBeTruthy()
  })

  it('lays out the columns, and Only differences hides the rows that read alike', async () => {
    wrap(`/explore?topic=philosophies&compare=${DOC.ids.join(',')}`)
    expect(await screen.findByText('At a glance')).toBeTruthy()
    for (const g of DOC.philosophies) expect(screen.getAllByText(g.name).length).toBeGreaterThan(0)
    expect(DOC.same.daysPerWeek).toBe(true)
    expect(screen.getByText('Days a week')).toBeTruthy()
    fireEvent.click(screen.getByRole('switch', { name: 'Only differences' }))
    expect(screen.queryByText('Days a week')).toBeNull()
    expect(screen.getByText('Weeks')).toBeTruthy()
  })

  it('removing a column replaces the URL', async () => {
    wrap(`/explore?topic=philosophies&compare=${DOC.ids.join(',')}`)
    fireEvent.click(await screen.findByRole('button', { name: `Remove ${GYM.name}` }))
    expect(location()).toBe(`/explore?topic=philosophies&compare=${UPHILL.id},${HORSEMEN.id}`)
  })

  it('For you runs on request, one column after another, and says why one cannot run', async () => {
    wrap(`/explore?topic=philosophies&compare=${DOC.ids.join(',')}`)
    fireEvent.click(await screen.findByRole('button', { name: /See what each gives you/ }))

    await waitFor(() => expect(post).toHaveBeenCalledTimes(1))
    expect(post.mock.calls[0][0]).toBe(`/philosophies/${UPHILL.id}/for-me`)
    pending[0].resolve()
    await waitFor(() => expect(post).toHaveBeenCalledTimes(2))
    expect(post.mock.calls[1][0]).toBe(`/philosophies/${GYM.id}/for-me`)
    pending[1].resolve()
    await waitFor(() => expect(post).toHaveBeenCalledTimes(3))
    pending[2].resolve()

    const row = (await screen.findByText('Runs for you')).parentElement!
    expect(FOR_ME[UPHILL.id].feasible).toBe(false)
    expect(await within(row).findAllByText('Not as you are')).toHaveLength(2)
    expect(within(row).getByText(new RegExp(`Yes — ${FOR_ME[HORSEMEN.id].trackName}`))).toBeTruthy()
    expect(screen.getAllByText(/Lacks .*Barbell/).length).toBeGreaterThan(0)
  })
})
