// @vitest-environment jsdom
/**
 * Explore's selection is the URL: a deep link opens a detail, and a lineage
 * pill pushes the next one, so Back walks the trail.
 */
import { describe, it, expect, afterEach, vi } from 'vitest'
import { render, cleanup, screen, fireEvent } from '@testing-library/react'
import { MemoryRouter, useLocation } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Explore } from '@/pages/Explore'
import type { ExploreLinks } from '@/api/types'

const LINKS: ExploreLinks = {
  movements: [{ id: 'squat', name: 'Squat', exerciseCount: 1, filterGroups: [], rollup: 'squat' }],
  links: {
    philosophyFramework: [], frameworkModality: [], modalityArchetype: [],
    archetypeExercise: [],
    exerciseMovement: [{ exercise: 'goblet', movement: 'squat' }],
    exerciseProgression: [], exerciseConcepts: [],
  },
}

const GOBLET = {
  id: 'goblet', name: 'Goblet squat', category: 'kettlebell', modality: [], equipment: [], effort: 'medium',
  bilateral: true, movement_patterns: ['squat'], requires: [], unlocks: [], contraindicated_with: [],
  progressions: {}, sources: [], _package: 'wk',
}

const RESPONSES: Record<string, unknown> = {
  '/explore/links': LINKS,
  '/exercises': [GOBLET],
  '/philosophies': [], '/frameworks': [], '/modalities': [], '/archetypes': [],
}

vi.mock('@/api/client', () => ({
  apiClient: { get: vi.fn((url: string) => Promise.resolve(RESPONSES[url] ?? null)) },
}))

function Where() {
  const l = useLocation()
  return <span data-testid="where">{l.pathname + l.search}</span>
}
const location = () => screen.getByTestId('where').textContent

function wrap(route: string) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter initialEntries={[route]}><Explore /><Where /></MemoryRouter>
    </QueryClientProvider>,
  )
}

afterEach(cleanup)

describe('Explore', () => {
  it('opens a movement from the URL and follows its lineage to an exercise', async () => {
    wrap('/explore?topic=movements&id=squat')
    expect(await screen.findByRole('heading', { name: 'Squat' })).toBeTruthy()
    expect(screen.getByText('Leads into it')).toBeTruthy()

    fireEvent.click(await screen.findByRole('button', { name: /Goblet squat/ }))
    expect(location()).toBe('/explore?topic=exercises&id=goblet')
    expect(await screen.findByRole('heading', { name: 'Goblet squat' })).toBeTruthy()
    // …and the exercise leads back down to its movement.
    expect(await screen.findByRole('button', { name: /^Squat$/ })).toBeTruthy()
  })

  it('lists the movements under Movements', async () => {
    wrap('/explore?topic=movements')
    expect(await screen.findByText('1 movements.')).toBeTruthy()
    fireEvent.click(screen.getByRole('button', { name: /Squat/ }))
    expect(location()).toBe('/explore?topic=movements&id=squat')
  })
})
