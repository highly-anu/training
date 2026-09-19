import { describe, expect, it } from 'vitest'
import type { AthleteConstraints, Framework } from '@/api/types'
import { blockingReason, checkStyleCompatibility } from './styleCompatibility'

/**
 * The two Horsemen training styles, with the fields this gate reads copied from
 * data/packages/horsemen_gpp/frameworks/*.yaml. Selecting "GPP Circuits" used to
 * fail at Generate with FRAMEWORK_PHILOSOPHY_MISMATCH; these assert that both
 * styles are offered at the builder's defaults, and that a style is only
 * withheld when the athlete's constraints genuinely rule it out.
 */
const concurrentTraining = {
  id: 'concurrent_training',
  name: 'Concurrent Training (GPP / Balanced Fitness)',
  applicable_when: {
    training_level: ['intermediate', 'advanced', 'elite'],
    days_per_week_min: 4,
    days_per_week_max: 6,
  },
  expectations: {
    min_weeks: 12,
    ideal_weeks: 16,
    min_days_per_week: 4,
    ideal_days_per_week: 5,
    min_session_minutes: 60,
    ideal_session_minutes: 90,
    ideal_long_session_minutes: 120,
    supports_split_days: true,
  },
} as unknown as Framework

const gppCircuits = {
  id: 'gpp_circuits',
  name: 'GPP Circuits (Horsemen / SOF-style)',
  applicable_when: {
    training_level: ['novice', 'intermediate', 'advanced', 'elite'],
    days_per_week_min: 3,
    days_per_week_max: 5,
  },
  expectations: {
    min_weeks: 8,
    ideal_weeks: 12,
    min_days_per_week: 3,
    ideal_days_per_week: 4,
    min_session_minutes: 45,
    ideal_session_minutes: 60,
    supports_split_days: false,
  },
} as unknown as Framework

/** builderStore's defaultConstraints: 4 days, 60 weekday / 90 weekend. */
const defaults: Partial<AthleteConstraints> = {
  days_per_week: 4,
  session_time_minutes: 60,
  weekday_session_minutes: 60,
  weekend_session_minutes: 90,
  training_level: 'intermediate',
}

describe('checkStyleCompatibility', () => {
  it('offers both Horsemen styles at the builder defaults', () => {
    for (const fw of [concurrentTraining, gppCircuits]) {
      const result = checkStyleCompatibility(fw, defaults)
      expect(result.selectable, `${fw.id} should be selectable`).toBe(true)
      expect(result.issues).toHaveLength(0)
    }
  })

  it('withholds a style that needs more days than the athlete has', () => {
    const threeDays = { ...defaults, days_per_week: 3 }

    const concurrent = checkStyleCompatibility(concurrentTraining, threeDays)
    expect(concurrent.selectable).toBe(false)
    expect(blockingReason(concurrent)?.label).toBe('Needs 4+ days/week')
    expect(blockingReason(concurrent)?.constraintPatch).toEqual({ days_per_week: 4 })

    // GPP Circuits runs at three days, so it stays available.
    expect(checkStyleCompatibility(gppCircuits, threeDays).selectable).toBe(true)
  })

  it('withholds a style whose day cap the athlete exceeds', () => {
    const sixDays = { ...defaults, days_per_week: 6 }
    const result = checkStyleCompatibility(gppCircuits, sixDays)
    expect(result.selectable).toBe(false)
    expect(blockingReason(result)?.label).toBe('Max 5 days/week')
  })

  it('takes the stricter of applicable_when and expectations for the minimum', () => {
    // gpp_circuits once declared days_per_week_min 2 against min_days_per_week 3,
    // so two days passed the gate and then failed server-side validation.
    const mismatched = {
      ...gppCircuits,
      applicable_when: { ...gppCircuits.applicable_when, days_per_week_min: 2 },
    } as unknown as Framework
    const twoDays = { ...defaults, days_per_week: 2 }
    expect(checkStyleCompatibility(mismatched, twoDays).selectable).toBe(false)
  })

  it('uses the weighted effective session time, not the weekday figure alone', () => {
    // 30 weekday / 40 weekend averages to ~33 min, under both minimums.
    const short = {
      ...defaults,
      weekday_session_minutes: 30,
      weekend_session_minutes: 40,
    }
    expect(checkStyleCompatibility(concurrentTraining, short).selectable).toBe(false)
    expect(checkStyleCompatibility(gppCircuits, short).selectable).toBe(false)
  })

  it('warns about a level mismatch without withholding the style', () => {
    // The backend warns rather than errors here, so the gate must not disagree.
    const novice = { ...defaults, training_level: 'novice' as const }
    const result = checkStyleCompatibility(concurrentTraining, novice)
    expect(result.selectable).toBe(true)
    expect(result.issues.map((i) => i.severity)).toEqual(['warning'])
  })

  it('treats a framework with no constraints as always selectable', () => {
    const bare = { id: 'bare', name: 'Bare' } as unknown as Framework
    expect(checkStyleCompatibility(bare, defaults).selectable).toBe(true)
  })
})
