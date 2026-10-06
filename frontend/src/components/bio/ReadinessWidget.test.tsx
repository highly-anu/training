// @vitest-environment jsdom
/**
 * Readiness names where its resting HR came from. Since the Connect IQ watch
 * posts daily wellness, the server takes resting HR from one series — the
 * watch's or Apple Health's — and says which in `sources`; the widget must
 * show it, or a score that moved because the source changed looks like the
 * athlete changed.
 */
import { describe, it, expect, afterEach, vi } from 'vitest'
import { render, screen, cleanup } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReadinessResult } from '@/lib/readiness'
import { ReadinessWidget } from './ReadinessWidget'

const readiness = vi.fn<() => Promise<ReadinessResult>>()
vi.mock('@/api/health', () => ({ fetchReadiness: () => readiness() }))

function mount() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter><ReadinessWidget /></MemoryRouter>
    </QueryClientProvider>,
  )
}

const base: ReadinessResult = {
  score: 72, status: 'green', flags: [],
  components: { rhr: 30, hrv: 20, sleep: 10, fatigue: 8, tsb: 4 },
}

afterEach(cleanup)

describe('ReadinessWidget', () => {
  it('says the resting HR came from the watch', async () => {
    readiness.mockResolvedValue({ ...base, sources: { rhr: 'garmin_ciq', hrv: 'daily_bio', sleep: 'daily_bio' } })
    mount()
    expect(await screen.findByText(
      'Resting HR from your Garmin watch; HRV and sleep from Apple Health and check-ins.')).toBeInTheDocument()
  })

  it('shows no footnote for a server that does not report sources', async () => {
    readiness.mockResolvedValue(base)
    mount()
    expect(await screen.findByText('72')).toBeInTheDocument()
    expect(screen.queryByText(/Resting HR from/)).not.toBeInTheDocument()
  })
})
