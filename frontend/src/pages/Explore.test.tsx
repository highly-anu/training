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
  movements: [{ id: 'squat', name: 'Squat', exerciseCount: 2, filterGroups: [], rollup: 'squat' }],
  equipment: {
    vocabulary: ['barbell', 'kettlebell', 'open_space'],
    exercises: { goblet: ['kettlebell'], back_squat: ['barbell'] },
    archetypes: { kb_day: ['kettlebell'], bb_day: ['barbell'] },
  },
  links: {
    philosophyFramework: [], frameworkModality: [],
    modalityArchetype: [{ modality: 'power', archetype: 'kb_day', package: 'wk' },
                        { modality: 'max_strength', archetype: 'bb_day', package: 'ss' }],
    archetypeExercise: [{ archetype: 'kb_day', exercise: 'goblet', slots: ['main'], via: 'listed' },
                        { archetype: 'bb_day', exercise: 'back_squat', slots: ['main'], via: 'listed' }],
    exerciseMovement: [{ exercise: 'goblet', movement: 'squat' }, { exercise: 'back_squat', movement: 'squat' }],
    exerciseProgression: [], exerciseConcepts: [],
  },
}

const GOBLET = {
  id: 'goblet', name: 'Goblet squat', category: 'kettlebell', modality: [], equipment: [], effort: 'medium',
  bilateral: true, movement_patterns: ['squat'], requires: [], unlocks: [], contraindicated_with: [],
  progressions: {}, sources: [], _package: 'wk',
}

const BACK_SQUAT = { ...GOBLET, id: 'back_squat', name: 'Back squat', category: 'barbell', _package: 'ss' }

const RESPONSES: Record<string, unknown> = {
  '/explore/links': LINKS,
  '/exercises': [GOBLET, BACK_SQUAT],
  '/philosophies': [], '/frameworks': [],
  '/modalities': [{ id: 'power', name: 'Power' }, { id: 'max_strength', name: 'Max Strength' }],
  '/archetypes': [],
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

  it('equipment: lists what it enables, a pick narrows the rest, ↗ opens the detail', async () => {
    wrap('/explore?topic=equipment&eq=kettlebell,barbell')
    const exercises = async () => (await screen.findAllByRole('button', { pressed: false }))
      .map((b) => b.textContent ?? '')
    expect(await screen.findByRole('button', { name: /Goblet squat/, pressed: false })).toBeTruthy()
    expect(screen.getByRole('button', { name: /Back squat/, pressed: false })).toBeTruthy()

    // Pick Power: the barbell squat is not in it.
    fireEvent.click(screen.getByRole('button', { name: /^Power/, pressed: false }))
    expect(location()).toBe('/explore?topic=equipment&eq=kettlebell%2Cbarbell&m=power')
    expect((await exercises()).some((t) => t.startsWith('Back squat'))).toBe(false)

    fireEvent.click(screen.getByRole('button', { name: 'Open Goblet squat' }))
    expect(location()).toBe('/explore?topic=exercises&id=goblet')
  })

  it('lists the movements under Movements', async () => {
    wrap('/explore?topic=movements')
    expect(await screen.findByText('1 movements.')).toBeTruthy()
    fireEvent.click(screen.getByRole('button', { name: /Squat/ }))
    expect(location()).toBe('/explore?topic=movements&id=squat')
  })
})
