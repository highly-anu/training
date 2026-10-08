import { describe, expect, it } from 'vitest'
import { wellnessSummary } from './wellness'

describe('wellnessSummary', () => {
  it('lists what the watch read', () => {
    expect(wellnessSummary({
      date: '2026-10-08', source: 'garmin_ciq', resting_hr: 46, resting_hr_7d_avg: 47, hr_min: 47,
      body_battery_max: 75, recovery_time_h: 82, read_at: '2026-10-08T07:20:00',
    })).toBe('8 Oct, 07:20 · HR low\u00a047 · 7-day resting HR\u00a047 · Body Battery\u00a075 · recovery\u00a082\u00a0h')
  })

  it('never shows the profile resting HR, which is the zone setting', () => {
    expect(wellnessSummary({ date: '2026-10-08', source: 'garmin_ciq', resting_hr: 46 })).toBe('8 Oct')
  })

  it('keeps a recovery time of zero and skips what is missing', () => {
    expect(wellnessSummary({ date: '2026-10-06', source: 'garmin_ciq', recovery_time_h: 0 }))
      .toBe('6 Oct · recovery\u00a00\u00a0h')
  })
})
