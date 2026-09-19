import type { ExerciseLoad } from '@/api/types'

/**
 * TypeScript port of Python's _fmt_load() from src/output.py.
 * Formats an ExerciseLoad object into a human-readable string.
 */
export function formatLoad(load: ExerciseLoad): string {
  if (!load || Object.keys(load).length === 0) return ''

  const parts: string[] = []

  // Sets × reps @ weight
  if (load.sets && load.reps) {
    const repsStr = typeof load.reps === 'number' ? String(load.reps) : load.reps
    if (load.weight_kg) {
      parts.push(`${load.sets}×${repsStr} @ ${load.weight_kg}kg`)
    } else if (load.target_rpe) {
      parts.push(`${load.sets}×${repsStr} @ RPE ${load.target_rpe}`)
    } else {
      parts.push(`${load.sets}×${repsStr}`)
    }
  } else if (load.sets && !load.reps) {
    parts.push(`${load.sets} sets`)
  }

  // Duration
  if (load.duration_minutes) {
    parts.push(`${load.duration_minutes} min`)
  }

  // Zone target (aerobic work)
  if (load.zone_target) {
    parts.push(load.zone_target)
  }

  // Distance
  if (load.distance_km) {
    parts.push(`${load.distance_km} km`)
  } else if (load.distance_m) {
    parts.push(`${load.distance_m} m`)
  }

  // Rounds / AMRAP / structured intervals
  if (load.target_rounds && load.work_sec) {
    // e.g. "8 × 20s/10s" (Tabata) or "10 × 60s" (EMOM strength)
    const span = load.rest_sec ? `${load.work_sec}s/${load.rest_sec}s` : `${load.work_sec}s`
    parts.push(`${load.target_rounds} × ${span}`)
  } else if (load.target_rounds && load.reps_per_round) {
    parts.push(`${load.target_rounds} rounds × ${load.reps_per_round} reps`)
  } else if (load.target_rounds) {
    parts.push(`${load.target_rounds} rounds`)
  } else if (load.reps_per_round) {
    parts.push(`${load.reps_per_round} reps / round`)
  }

  // Pack weight (rucks, loaded carries)
  if (load.pack_load_kg) {
    parts.push(`${load.pack_load_kg} kg pack`)
  }

  // Time domain
  if (load.time_minutes && !load.duration_minutes) {
    parts.push(`${load.time_minutes} min`)
  }

  // Format label (e.g. AMRAP, EMOM) — redundant once an interval span is shown.
  if (load.format && !load.work_sec) {
    parts.push(load.format)
  }

  // Isometric hold
  if (load.hold_seconds) {
    parts.push(`${load.hold_seconds}s hold`)
  }

  // Intensity label
  if (load.intensity && !load.zone_target) {
    parts.push(load.intensity)
  }

  // Focus note
  if (load.focus) {
    parts.push(`— ${load.focus}`)
  }

  return parts.join(' · ')
}
