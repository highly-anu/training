// @vitest-environment jsdom
/**
 * Explore ▸ a philosophy: a hero, then one section at a time — Overview,
 * Program, Sessions, Method — with the section and the open session owned by
 * the caller (the URL). The document is the server's
 * (mocks/fixtures/philosophy-describe.json, written by test_explore_philosophy.py).
 */
import { useState } from 'react'
import { describe, it, expect, afterEach, beforeEach, vi } from 'vitest'
import { render, screen, cleanup, fireEvent, within } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import fixture from '@/mocks/fixtures/philosophy-describe.json'
import { TipProvider } from '@/components/shared/Tip'

const RESPONSES = vi.hoisted(() => ({} as Record<string, unknown>))
vi.mock('@/api/client', () => ({
  apiClient: { get: vi.fn((url: string) => Promise.resolve(RESPONSES[url] ?? null)), patch: vi.fn() },
}))

import { PhilosophyPage } from './PhilosophyPage'
import type { PhilosophyView } from './views'

const phil = {
  id: 'p', name: 'P', core_principles: [], scope: [], bias: ['max_strength'], avoid_with: [], required_equipment: [],
  intensity_model: 'x', progression_philosophy: 'x', sources: [], tracks: [],
}

beforeEach(() => {
  for (const key of Object.keys(RESPONSES)) delete RESPONSES[key]
  Object.assign(RESPONSES, {
    '/philosophies/p/describe': fixture, '/philosophies': [phil], '/frameworks': [], '/modalities': [],
    '/archetypes': [], '/exercises': [],
    '/methods': { available: false, reason: 'not_enabled', methods: [], builds: [], limits: {} },
  })
  vi.stubGlobal('matchMedia', (query: string) => ({
    matches: true, media: query, addEventListener: () => {}, removeEventListener: () => {},
  }))
})
afterEach(() => { cleanup(); vi.unstubAllGlobals() })

/** The page with the state its caller keeps in the URL. */
function Harness({ start = 'overview', session = null }: { start?: PhilosophyView; session?: string | null }) {
  const [view, setView] = useState<PhilosophyView>(start)
  const [sessionId, setSessionId] = useState<string | null>(session)
  return (
    <PhilosophyPage id="p" view={view} onView={setView} sessionId={sessionId}
      onSession={(id) => { setView('sessions'); setSessionId(id) }}
      onSelect={() => {}} onCompare={() => {}} onBack={() => {}} />
  )
}

function mount(props: Parameters<typeof Harness>[0] = {}) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })
  render(
    <QueryClientProvider client={client}>
      <MemoryRouter><TipProvider><Harness {...props} /></TipProvider></MemoryRouter>
    </QueryClientProvider>,
  )
}

const tab = (name: RegExp) => screen.getByRole('tab', { name })

describe('PhilosophyPage', () => {
  it('opens on the overview: what it is, then the week, what it builds and what it needs', async () => {
    mount()
    expect(await screen.findByRole('heading', { name: 'P', level: 2 })).toBeTruthy()
    expect(screen.getByText('What it is.')).toBeTruthy()
    expect(screen.getAllByRole('tab').map((t) => t.textContent)).toEqual(['Overview', 'Program', 'Sessions7', 'Method'])
    expect(tab(/Overview/).getAttribute('aria-selected')).toBe('true')
    const week = within(screen.getByRole('region', { name: 'The week' }))
    expect(week.getByText('Max Strength')).toBeTruthy()
    expect(screen.getByRole('region', { name: 'What it builds' })).toBeTruthy()
    expect(within(screen.getByRole('region', { name: 'What you need' })).getByText('Barbell')).toBeTruthy()
    // One section at a time: the tracks and the sessions wait behind their tabs.
    expect(screen.queryByRole('searchbox')).toBeNull()
    expect(screen.queryByRole('group', { name: /Templated/ })).toBeNull()
  })

  it('shows the tracks and phases under Program', async () => {
    mount({ start: 'program' })
    expect(await screen.findByRole('group', { name: 'Templated, 1 of 2' })).toBeTruthy()
    expect(screen.getByRole('group', { name: 'Contract, 2 of 2' })).toBeTruthy()
  })

  it('opens shortened words with More… and hides them again with Less', async () => {
    mount({ start: 'program' })
    await screen.findByRole('group', { name: 'Templated, 1 of 2' })
    const more = screen.getAllByRole('button', { name: 'More…' })[0]
    expect(more.getAttribute('aria-expanded')).toBe('false')
    fireEvent.click(more)
    expect(screen.getAllByRole('button', { name: 'Less' })[0].getAttribute('aria-expanded')).toBe('true')
    expect(screen.queryByText(/About this track|More about it/)).toBeNull()
  })

  it('moves to the section a tab names', async () => {
    mount()
    await screen.findByRole('heading', { name: 'P', level: 2 })
    fireEvent.click(tab(/Sessions/))
    expect(await screen.findByRole('searchbox', { name: 'Search sessions' })).toBeTruthy()
    expect(tab(/Sessions/).getAttribute('aria-selected')).toBe('true')
  })

  it('opens the session the caller names in the browser', async () => {
    mount({ start: 'sessions', session: 'h2' })
    const open = within(await screen.findByRole('article'))
    expect(open.getByRole('heading', { name: 'H2' })).toBeTruthy()
    expect(open.getByRole('button', { name: /Open as an archetype/ })).toBeTruthy()
  })

  it("leads from a week's module to its session", async () => {
    mount({ start: 'program' })
    const track = within(await screen.findByRole('group', { name: 'Contract, 2 of 2' }))
    // A track waiting at the edge is brought in by a click anywhere on it.
    fireEvent.click(track.getByRole('heading', { level: 3 }))
    expect(screen.getByRole('button', { name: 'Next track' })).toHaveProperty('disabled', true)
    // Its phase opens from the timeline as from its card.
    fireEvent.click(track.getByRole('button', { name: /^C.*, weeks? \d/ }))
    fireEvent.click(track.getByRole('button', { name: /See the session/ }))
    const open = within(await screen.findByRole('article'))
    expect(open.getByRole('heading', { name: 'C1' })).toBeTruthy()
    expect(tab(/Sessions/).getAttribute('aria-selected')).toBe('true')
  })

  it('shows the rules under Method, each with what it rests on', async () => {
    mount({ start: 'method' })
    expect(await screen.findByText('Lift heavy twice a week.')).toBeTruthy()
    fireEvent.click(screen.getByRole('button', { name: /sources/ }))
    expect(await screen.findByText(/The Book/)).toBeTruthy()
  })

  it('offers no editing for a shipped philosophy', async () => {
    mount()
    await screen.findByRole('heading', { name: 'P', level: 2 })
    expect(screen.queryByRole('button', { name: 'Change this method' })).toBeNull()
  })

  it("keeps an own method's editing behind one menu, and edits its words in place", async () => {
    RESPONSES['/philosophies/p/describe'] = { ...fixture, own: true }
    RESPONSES['/methods'] = { available: true, reason: null, methods: [], builds: [], limits: {} }
    mount()
    const menu = await screen.findByRole('button', { name: 'Change this method' })
    expect(screen.queryByText('Yours')).toBeNull()
    fireEvent.keyDown(menu, { key: 'Enter' })
    expect(await screen.findByRole('menuitem', { name: /Rename/ })).toBeTruthy()
    expect(screen.getByRole('menuitem', { name: /Revise/ }).getAttribute('href')).toBe('/program/new/method?revise=p')
    fireEvent.click(screen.getByRole('menuitem', { name: /Edit description/ }))
    expect(await screen.findByRole('button', { name: 'Done editing' })).toBeTruthy()
    expect(screen.getByRole('button', { name: 'Edit summary' })).toBeTruthy()
    fireEvent.click(tab(/Sessions/))
    const open = within(await screen.findByRole('article'))
    expect(open.getByRole('button', { name: 'Edit session name' })).toBeTruthy()
  })
})
