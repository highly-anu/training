import { describe, expect, it } from 'vitest'
import { readinessSourceNote } from './readiness'

describe('readinessSourceNote', () => {
  it('says nothing for an older server or an empty score', () => {
    expect(readinessSourceNote(undefined)).toBeNull()
    expect(readinessSourceNote({ rhr: null, hrv: null, sleep: null })).toBeNull()
  })

  it('names one source once', () => {
    expect(readinessSourceNote({ rhr: 'daily_bio', hrv: 'daily_bio', sleep: 'daily_bio' }))
      .toBe('Resting HR, HRV and sleep from Apple Health and check-ins.')
  })

  it('names the watch when it supplies resting HR', () => {
    expect(readinessSourceNote({ rhr: 'garmin_ciq', hrv: 'daily_bio', sleep: 'daily_bio' }))
      .toBe("Resting HR from your Garmin watch's heart-rate low; HRV and sleep from Apple Health and check-ins.")
  })

  it('leaves out what was not scored', () => {
    expect(readinessSourceNote({ rhr: 'garmin_ciq', hrv: null, sleep: null }))
      .toBe("Resting HR from your Garmin watch's heart-rate low.")
  })
})
