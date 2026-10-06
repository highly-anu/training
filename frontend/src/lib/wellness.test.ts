import { describe, expect, it } from 'vitest'
import { wellnessSummary } from './wellness'

describe('wellnessSummary', () => {
  it('lists what the watch read', () => {
    expect(wellnessSummary({
      date: '2026-10-06', source: 'garmin_ciq', resting_hr: 46, body_battery_max: 95,
      recovery_time_h: 58, read_at: '2026-10-06T07:31:00',
    })).toBe('6 Oct, 07:31 · resting HR\u00a046 · Body Battery\u00a095 · recovery\u00a058\u00a0h')
  })

  it('keeps a recovery time of zero and skips what is missing', () => {
    expect(wellnessSummary({ date: '2026-10-06', source: 'garmin_ciq', recovery_time_h: 0 }))
      .toBe('6 Oct · recovery\u00a00\u00a0h')
  })
})
