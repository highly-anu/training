// @vitest-environment jsdom
/**
 * Settings is where configuration lives; Profile keeps the athlete. The OAuth
 * callbacks land on `/settings?tab=connections`, and the old Profile tab must
 * carry them there without losing the provider's outcome.
 */
import { describe, it, expect, afterEach, vi } from 'vitest'
import { render, cleanup, screen } from '@testing-library/react'
import { MemoryRouter, Routes, Route, useLocation } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { Settings } from '@/pages/Settings'
import { ProfileBenchmarks } from '@/pages/ProfileBenchmarks'

vi.mock('@/api/client', () => ({
  apiClient: {
    get: vi.fn().mockResolvedValue(null),
    post: vi.fn().mockResolvedValue(null),
    put: vi.fn().mockResolvedValue(null),
    delete: vi.fn().mockResolvedValue(null),
  },
}))

function LocationProbe() {
  const location = useLocation()
  return <div data-testid="location">{location.pathname}{location.search}</div>
}

function wrap(ui: ReactNode, route: string) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter initialEntries={[route]}>
        <Routes>
          <Route path="/settings" element={<>{ui}<LocationProbe /></>} />
          <Route path="/profile" element={<><ProfileBenchmarks /><LocationProbe /></>} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  )
}

afterEach(cleanup)

describe('Settings', () => {
  it('opens on Connections and switches by ?tab=', () => {
    wrap(<Settings />, '/settings')
    expect(screen.getByRole('tab', { name: /connections/i })).toHaveAttribute('aria-selected', 'true')
    cleanup()
    wrap(<Settings />, '/settings?tab=account')
    expect(screen.getByRole('tab', { name: /account/i })).toHaveAttribute('aria-selected', 'true')
    expect(screen.getByText('Account.')).toBeTruthy()
    cleanup()
    wrap(<Settings />, '/settings?tab=appearance')
    expect(screen.getByRole('radiogroup', { name: /theme/i })).toBeTruthy()
  })

  it('falls back to Connections for an unknown tab', () => {
    wrap(<Settings />, '/settings?tab=nope')
    expect(screen.getByRole('tab', { name: /connections/i })).toHaveAttribute('aria-selected', 'true')
  })

  it('sends the old Profile ▸ Connections link to Settings with its query', () => {
    // A provider outcome (`garmin=connected`) is consumed by ConnectionsSettings
    // on arrival, so a neutral parameter proves the query travelled.
    wrap(<Settings />, '/profile?tab=connections&from=oauth')
    expect(screen.getByTestId('location').textContent).toBe('/settings?tab=connections&from=oauth')
  })

  it('keeps Profile on its own tabs otherwise', () => {
    wrap(<Settings />, '/profile?tab=equipment')
    expect(screen.getByTestId('location').textContent).toBe('/profile?tab=equipment')
  })
})
