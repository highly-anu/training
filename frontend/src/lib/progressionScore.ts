import type { ProgressionReview, ScoreStatus } from '@/api/types'
import type { StatusLevel } from '@/lib/statusColors'

const LEVEL: Record<ScoreStatus['id'], StatusLevel> = { on_track: 'green', mixed: 'yellow', off_track: 'red' }

/**
 * The review score's band for the dashboard widget and Analytics ▸ Progress
 * alike: the server's status when it sent one (src/analytics/review.py), the
 * thresholds it uses otherwise. The widget used to call the low band
 * "Behind" while the phone said "Off Track".
 */
export function scoreBand(review: ProgressionReview | undefined | null):
  { id: ScoreStatus['id']; label: string; level: StatusLevel } | null {
  if (!review) return null
  const s = review.score_status
  if (s) return { id: s.id, label: s.label, level: LEVEL[s.id] }
  const score = review.overall_score
  if (score == null) return null
  if (score >= 70) return { id: 'on_track', label: 'On Track', level: 'green' }
  if (score >= 45) return { id: 'mixed', label: 'Mixed', level: 'yellow' }
  return { id: 'off_track', label: 'Off Track', level: 'red' }
}

/** "70 and up", "45–69", "below 45" — each band's range from the next one up. */
export function bandRange(bands: ScoreStatus['bands'], index: number): string {
  const b = bands[index]
  if (index === 0) return `${b.min} and up`
  const upper = bands[index - 1].min - 1
  return b.min === 0 ? `below ${upper + 1}` : `${b.min}–${upper}`
}
