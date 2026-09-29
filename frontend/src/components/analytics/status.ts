import type { AnalyticsStatus } from '@/api/types'
import type { StatusLevel } from '@/lib/statusColors'

/**
 * The engine's statuses folded onto the app's three status colours. Kept in
 * one place so a "behind" reads the same amber everywhere, and so a status the
 * engine adds later degrades to neutral rather than to a missing style.
 */
export function statusLevel(status: AnalyticsStatus | string): StatusLevel | 'neutral' {
  switch (status) {
    case 'ahead': case 'on_track': case 'met': case 'on_target': case 'stable_by_design':
      return 'green'
    case 'behind': case 'partial': case 'off_target': case 'no_target':
      return 'yellow'
    case 'stalled': case 'below': case 'off_plan': case 'error':
      return 'red'
    default:
      return 'neutral'
  }
}

export const STATUS_LABELS: Record<string, string> = {
  ahead: 'Ahead', on_track: 'On track', behind: 'Behind', stalled: 'Stalled',
  stable_by_design: 'Holding', insufficient_data: 'Not enough data',
  on_target: 'On target', off_target: 'Off target', no_target: 'No target',
  met: 'Met', partial: 'Partly met', below: 'Below', off_plan: 'Off plan',
  on_plan: 'On plan', not_started: 'Not started', error: 'Error', no_load_data: 'No load data',
  loading_as_expected: 'Loading as expected', very_fatigued: 'Very fatigued',
  fresh: 'Fresh', still_fatigued_in_recovery: 'Still fatigued in a recovery week',
}

export function statusLabel(status: string): string {
  return STATUS_LABELS[status] ?? status.replace(/_/g, ' ')
}

/** Why a primitive could not measure — the reason codes the engine emits, in words. */
export const COVERAGE_REASONS: Record<string, string> = {
  no_sets_logged: 'No sets logged yet. Log reps and kg on a completed session.',
  rounds_not_logged: 'Rounds are not being logged. Enter rounds on an AMRAP or EMOM session.',
  duration_not_logged: 'Minutes are not being captured. Match a workout or log the session duration.',
  distance_not_logged: 'Distance is not being captured. Match a workout or log kilometres.',
  hold_not_logged: 'Hold times are not being logged. The watch records them; on the web, log seconds per set.',
  timed_sets_not_logged: 'Reps per minute needs reps and seconds on the same set.',
  no_rpe_target: 'This program prescribes no RPE targets, so load-at-RPE cannot be measured.',
  rpe_not_logged: 'RPE is not being logged with sets.',
  no_sets_near_target: 'No logged sets were within ±1 of the target RPE.',
  no_heart_rate: 'No heart-rate data on the matched workouts.',
  no_gps_hr: 'Needs a matched run or ride with GPS and heart-rate samples.',
  no_exercises_in_scope: 'No exercises in this scope have been completed yet.',
  no_pr_logged: 'No PR logged for these standards. Add one on the Profile page.',
}
