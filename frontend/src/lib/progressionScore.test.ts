import { describe, expect, it } from 'vitest'
import { bandRange, scoreBand } from './progressionScore'
import type { ProgressionReview } from '@/api/types'

const base: ProgressionReview = {
  period_key: '2026-W42', period_type: 'weekly', generated_at: null, overall_score: 52,
  readiness_trend: 'stable', avg_readiness: null, compliance_pct: 50,
  exercise_findings: [], flags: [], recommendations: [], adjustments: [],
}
const bands = [
  { id: 'on_track' as const, label: 'On Track', min: 70 },
  { id: 'mixed' as const, label: 'Mixed', min: 45 },
  { id: 'off_track' as const, label: 'Off Track', min: 0 },
]

describe('progression score band', () => {
  it('takes the server status', () => {
    const r = { ...base, overall_score: 100, score_status: { id: 'on_track' as const, label: 'On Track', reason: 'x', bands } }
    expect(scoreBand(r)).toEqual({ id: 'on_track', label: 'On Track', level: 'green' })
  })
  it('falls back to the thresholds, never "Behind"', () => {
    expect(scoreBand(base)?.label).toBe('Mixed')
    expect(scoreBand({ ...base, overall_score: 30 })?.label).toBe('Off Track')
    expect(scoreBand({ ...base, overall_score: null })).toBeNull()
  })
  it('words each band range', () => {
    expect([0, 1, 2].map((i) => bandRange(bands, i))).toEqual(['70 and up', '45–69', 'below 45'])
  })
})
