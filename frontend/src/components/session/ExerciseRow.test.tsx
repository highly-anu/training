// @vitest-environment jsdom
/**
 * The session row must offer a logger for every slot type that has a currency,
 * not only sets × reps. OutcomeLogger was written for rounds, minutes and km
 * and then never mounted — ExerciseRow rendered a logger only when
 * `load.sets > 0`, so every rounds/duration/distance analytics primitive had
 * zero coverage by construction. This pins the dispatch.
 */
import { describe, it, expect, afterEach, vi } from 'vitest'
import { render, screen, cleanup } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { ExerciseRow } from '@/components/session/ExerciseRow'
import type { ExerciseAssignment } from '@/api/types'

vi.mock('@/api/client', () => ({
  apiClient: {
    get: vi.fn().mockResolvedValue(null),
    post: vi.fn().mockResolvedValue(null),
    put: vi.fn().mockResolvedValue(null),
    delete: vi.fn().mockResolvedValue(null),
  },
}))

function renderRow(assignment: Record<string, unknown>) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })
  return render(
    <QueryClientProvider client={qc}>
      <ExerciseRow assignment={assignment as unknown as ExerciseAssignment} index={0} sessionKey="1-Monday-0" />
    </QueryClientProvider>,
  )
}

afterEach(cleanup)

describe('ExerciseRow logger dispatch', () => {
  it('offers minutes and km for a time_domain slot', () => {
    renderRow({
      exercise: { id: 'zone2_run', name: 'Zone 2 Run', category: 'aerobic' },
      load: { time_minutes: 45 },
      slot_type: 'time_domain',
    })
    expect(screen.getByLabelText('Min for zone2_run')).toBeInTheDocument()
    expect(screen.getByLabelText('km for zone2_run')).toBeInTheDocument()
  })

  it('offers rounds for an amrap slot', () => {
    renderRow({
      exercise: { id: 'cindy', name: 'Cindy', category: 'conditioning' },
      load: { time_minutes: 20 },
      slot_type: 'amrap',
    })
    expect(screen.getByLabelText('Rounds for cindy')).toBeInTheDocument()
  })

  it('keeps the set logger, and no outcome inputs, for sets × reps', () => {
    renderRow({
      exercise: { id: 'squat', name: 'Squat', category: 'barbell' },
      load: { sets: 3, reps: 5 },
      slot_type: 'sets_reps',
    })
    expect(screen.queryByLabelText('Log outcome')).toBeNull()
  })

  it('logs nothing for a slot with no currency', () => {
    renderRow({
      exercise: { id: 'cat_cow', name: 'Cat Cow', category: 'mobility' },
      load: {},
      slot_type: 'mobility_flow',
    })
    expect(screen.queryByLabelText('Log outcome')).toBeNull()
  })
})
