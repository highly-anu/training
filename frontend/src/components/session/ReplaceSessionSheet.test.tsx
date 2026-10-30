// @vitest-environment jsdom
/**
 * Adding a session: Search finds one from the library, and its full preview —
 * every exercise with its prescription — comes before anything is saved.
 */
import { describe, it, expect, afterEach, vi, beforeEach } from 'vitest'
import { render, screen, cleanup, fireEvent } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { ReplaceSessionSheet } from './ReplaceSessionSheet'
import { useProgramStore } from '@/store/programStore'
import type { GeneratedProgram, WeekData } from '@/api/types'

const FOUND = {
  modality: 'mobility', added: true,
  archetype: { id: 'btm_d08', name: 'Built to Move — Day 8: Find Your Balance', modality: 'mobility', duration_estimate_minutes: 30 },
  provenance: { package: 'kelly_starrett', borrowed: true, label: 'Kelly Starrett / Built to Move' },
  exercises: [{ exercise: { id: 'solec', name: 'SOLEC Test' }, load: { duration_minutes: 4 }, load_note: 'Eyes closed.' }],
}
const post = vi.fn(() => Promise.resolve(FOUND))
vi.mock('@/api/client', () => ({ apiClient: { get: vi.fn(() => Promise.resolve([])), post: (...a: unknown[]) => post(...(a as [])) } }))

const week = { week_number: 1, phase: 'base', schedule: { Friday: [] } } as unknown as WeekData
const program = { weeks: [week], constraints: {} } as unknown as GeneratedProgram

beforeEach(() => post.mockClear())
afterEach(cleanup)

function wrap() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(<QueryClientProvider client={qc}>
    <ReplaceSessionSheet open mode="add" onOpenChange={() => {}} weekIndex={0} weekData={week} day="Friday" program={program} />
  </QueryClientProvider>)
}

describe('ReplaceSessionSheet — add', () => {
  it('Search shows the found session in full before anything is saved', async () => {
    const add = vi.fn()
    useProgramStore.setState({ addSession: add } as never)
    wrap()
    fireEvent.click(screen.getByRole('button', { name: /^Search$/ }))
    expect(await screen.findByText('Built to Move — Day 8: Find Your Balance')).toBeTruthy()
    expect(screen.getByText('SOLEC Test')).toBeTruthy()
    expect(screen.getByText('Eyes closed.')).toBeTruthy()
    expect(screen.getByText(/via Kelly Starrett \/ Built to Move/)).toBeTruthy()
    expect(add).not.toHaveBeenCalled()
    expect(screen.getByRole('button', { name: 'Search again' })).toBeTruthy()
    fireEvent.click(screen.getByRole('button', { name: 'Add session' }))
    expect(add).toHaveBeenCalledWith(0, 'Friday', expect.objectContaining({ modality: 'mobility' }))
  })

  it('Back returns to the search, nothing saved', async () => {
    wrap()
    fireEvent.click(screen.getByRole('button', { name: /^Search$/ }))
    fireEvent.click(await screen.findByRole('button', { name: /Back/ }))
    expect(screen.getByRole('button', { name: /^Search$/ })).toBeTruthy()
  })
})
