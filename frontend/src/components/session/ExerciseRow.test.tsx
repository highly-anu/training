// @vitest-environment jsdom
/**
 * The session row must offer a logger for every slot type that has a currency,
 * not only sets × reps. OutcomeLogger was written for rounds, minutes and km
 * and then never mounted — ExerciseRow rendered a logger only when
 * `load.sets > 0`, so every rounds/duration/distance analytics primitive had
 * zero coverage by construction. This pins the dispatch.
 */
import { describe, it, expect, afterEach, vi } from 'vitest'
import { render, screen, cleanup, fireEvent } from '@testing-library/react'
import { useBioStore } from '@/store/bioStore'
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

  it('logs reps beside minutes for a kettlebell in a timed slot — cadence is reps per minute', () => {
    renderRow({
      exercise: { id: 'kb_jerk_single', name: 'KB Jerk', category: 'kettlebell', movement_patterns: ['vertical_push', 'ballistic'] },
      load: { duration_minutes: 6 },
      slot_type: 'time_domain',
    })
    expect(screen.getByLabelText('Min for kb_jerk_single')).toBeInTheDocument()
    expect(screen.getByLabelText('Reps for kb_jerk_single')).toBeInTheDocument()
    expect(screen.queryByLabelText('km for kb_jerk_single')).toBeNull()
  })

  it('logs a hold in seconds for an isometric in a skill-practice slot', () => {
    renderRow({
      exercise: { id: 'handstand_hold', name: 'Handstand Hold', category: 'bodyweight', movement_patterns: ['isometric'] },
      load: { duration_minutes: 10 },
      slot_type: 'skill_practice',
    })
    const input = screen.getByLabelText('Hold s for handstand_hold')
    fireEvent.change(input, { target: { value: '35' } })
    fireEvent.blur(input)
    const set0 = useBioStore.getState().sessionPerformanceLogs['1-Monday-0']?.exercises.handstand_hold?.sets[0]
    expect(set0?.durationSeconds).toBe(35)
    expect(set0?.completed).toBe(true)
  })

  it('logs seconds per set for an isometric practised in sets (Ido\'s ladders prescribe sets: 3)', () => {
    renderRow({
      exercise: { id: 'tuck_sit', name: 'Tuck Sit', category: 'skill', movement_patterns: ['isometric'] },
      load: { sets: 3, duration_minutes: 10 },
      slot_type: 'skill_practice',
    })
    fireEvent.click(screen.getByLabelText('Log set details'))
    expect(screen.getByText('Sec')).toBeInTheDocument()
    fireEvent.change(screen.getByLabelText('Seconds for set 1'), { target: { value: '20' } })
    const set0 = useBioStore.getState().sessionPerformanceLogs['1-Monday-0']?.exercises.tuck_sit?.sets[0]
    expect(set0?.durationSeconds).toBe(20)
  })

  it('logs seconds, not reps, per set of a static hold', () => {
    renderRow({
      exercise: { id: 'copenhagen', name: 'Copenhagen Plank', category: 'rehab', movement_patterns: ['isometric'] },
      load: { sets: 3, hold_seconds: 30 },
      slot_type: 'static_hold',
    })
    fireEvent.click(screen.getByLabelText('Log set details'))
    expect(screen.getByText('Sec')).toBeInTheDocument()
    fireEvent.change(screen.getByLabelText('Seconds for set 1'), { target: { value: '40' } })
    const set0 = useBioStore.getState().sessionPerformanceLogs['1-Monday-0']?.exercises.copenhagen?.sets[0]
    expect(set0?.durationSeconds).toBe(40)
    expect(set0?.repsActual).toBeUndefined()
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
