// @vitest-environment jsdom
/**
 * Log ▸ Linking's three actions reach the store: a suggestion's Link confirms
 * it, a link's check unlinks it, and select-then-pick links across days —
 * the path that works without a pointer.
 */
import { describe, it, expect, afterEach, beforeEach, vi } from 'vitest'
import { render, screen, cleanup, fireEvent } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { LinkingTab } from '@/components/log/LinkingTab'
import { buildLinkingDays } from '@/lib/linking'
import { useBioStore } from '@/store/bioStore'
import type { GeneratedProgram, ImportedWorkout } from '@/api/types'

vi.mock('@/api/client', () => ({
  apiClient: {
    get: vi.fn().mockResolvedValue(null),
    post: vi.fn().mockResolvedValue(null),
    put: vi.fn().mockResolvedValue(null),
    delete: vi.fn().mockResolvedValue(null),
  },
}))

const program = {
  weeks: [{
    week_number: 1,
    schedule: {
      Monday: [{ modality: 'aerobic_base', archetype: { name: 'Zone 2', duration_estimate_minutes: 45 }, exercises: [] }],
      Wednesday: [{ modality: 'max_strength', archetype: { name: 'Heavy Day', duration_estimate_minutes: 60 }, exercises: [] }],
    },
  }],
} as unknown as GeneratedProgram

const workout = (id: string, date: string, modality: string, minutes: number, activityType: string): ImportedWorkout => ({
  id, source: 'garmin', date, startTime: `${date}T07:00:00Z`, endTime: `${date}T08:00:00Z`,
  durationMinutes: minutes, activityType,
  inferredModalityId: modality as ImportedWorkout['inferredModalityId'], heartRate: {}, rawData: {},
})

const run = workout('run', '2026-10-05', 'aerobic_base', 44, 'Running')
const lift = workout('lift', '2026-10-06', 'max_strength', 58, 'Strength')

function renderTab(matches = useBioStore.getState().workoutMatches) {
  const days = buildLinkingDays({
    workouts: [run, lift], matches, pending: [], program,
    programStartDate: '2026-10-05', today: '2026-10-07',
  })
  return render(<MemoryRouter><LinkingTab days={days} hasProgram onImport={() => {}} /></MemoryRouter>)
}

let confirmMatch: ReturnType<typeof vi.fn<(workoutId: string, sessionKey: string) => void>>
let rejectMatch: ReturnType<typeof vi.fn<(workoutId: string) => void>>

beforeEach(() => {
  confirmMatch = vi.fn<(workoutId: string, sessionKey: string) => void>()
  rejectMatch = vi.fn<(workoutId: string) => void>()
  useBioStore.setState({ workoutMatches: [], pendingMatches: [], sessionPerformanceLogs: {}, confirmMatch, rejectMatch })
})
afterEach(cleanup)

describe('LinkingTab', () => {
  it('links a same-day suggestion', () => {
    renderTab()
    fireEvent.click(screen.getByRole('button', { name: 'Link Running to Zone 2' }))
    expect(confirmMatch).toHaveBeenCalledWith('run', '1-Monday-0')
  })

  it('links across days by selecting the workout, then the session', () => {
    renderTab()
    fireEvent.click(screen.getByRole('button', { name: 'Select Strength to link' }))
    fireEvent.click(screen.getByRole('button', { name: 'Link to Heavy Day' }))
    expect(confirmMatch).toHaveBeenCalledWith('lift', '1-Wednesday-0')
  })

  it('unlinks a link', () => {
    renderTab([{ importedWorkoutId: 'lift', sessionKey: '1-Wednesday-0', matchConfidence: 'manual', matchedAt: '' }])
    fireEvent.click(screen.getByRole('button', { name: /All days/ }))
    // The cross-day link sits on both Tuesday's and Wednesday's card.
    const unlink = screen.getAllByRole('button', { name: 'Unlink Strength from Heavy Day' })
    expect(unlink).toHaveLength(2)
    fireEvent.click(unlink[0])
    expect(rejectMatch).toHaveBeenCalledWith('lift')
  })
})
