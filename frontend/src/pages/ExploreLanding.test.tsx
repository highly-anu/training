// @vitest-environment jsdom
/**
 * Explore's landing: an athlete's own methods lead under their own label,
 * under their own heading with no badge, and the heading counts the shipped philosophies alone.
 */
import { describe, it, expect, afterEach, vi } from 'vitest'
import { render, cleanup, screen, within } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Explore } from '@/pages/Explore'

const phil = (id: string, name: string, own?: boolean) => ({
  id, name, core_principles: [], scope: [], bias: ['max_strength'], avoid_with: [], required_equipment: [],
  intensity_model: 'x', progression_philosophy: 'x', sources: [], tracks: [], ...(own ? { own: true } : {}),
})

const RESPONSES: Record<string, unknown> = {
  '/philosophies': [phil('ss', 'Starting Strength'), phil('u1_stones', 'Stone days', true), phil('cf', 'CrossFit')],
  '/philosophies/glance': [], '/frameworks': [], '/modalities': [], '/archetypes': [], '/exercises': [],
  '/explore/links': null, '/similarity': null,
}

vi.mock('@/api/client', () => ({
  apiClient: { get: vi.fn((url: string) => Promise.resolve(RESPONSES[url] ?? null)) },
}))

afterEach(cleanup)

function wrap() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter initialEntries={['/explore']}><Explore /></MemoryRouter>
    </QueryClientProvider>,
  )
}

describe('Explore landing', () => {
  it("leads with the athlete's own methods, with no badge, and counts the shipped ones", async () => {
    wrap()
    const mine = await screen.findByRole('region', { name: 'Your methods' })
    expect(within(mine).getByText('Stone days')).toBeTruthy()
    expect(within(mine).queryByText('Yours')).toBeNull()
    expect(within(mine).queryByText('CrossFit')).toBeNull()
    const rest = screen.getByRole('region', { name: 'Philosophies' })
    expect(within(rest).getByText('CrossFit')).toBeTruthy()
    expect(screen.getByRole('heading', { name: '2 training philosophies.' })).toBeTruthy()
    // Its own group comes first on the page.
    expect(mine.compareDocumentPosition(rest) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy()
  })
})
