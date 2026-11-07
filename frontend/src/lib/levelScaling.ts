import type { ExerciseAssignment, Track } from '@/api/types'
import { formatLoad } from './formatLoad'
import { TRAINING_LEVELS, TRAINING_LEVEL_LABELS } from './gen/clientVocab'

/**
 * The words for a prescription done at the athlete's share of what is written
 * (src/level_scaling.py, docs/logic/levels.md). The server scales and says
 * what was written (`load.rx`) and which movement a scale stands for
 * (`scaled_from_name`); this only words it, as the phone's LoadFormat does.
 */

/** "Scaled for Novice · Rx 21-15-9 reps · 43kg", or null when nothing scaled. */
export function scaledLoadText(assignment: ExerciseAssignment): string | null {
  const { load } = assignment
  if (!load?.rx || !load.level_scaled) return null
  const written = formatLoad({ ...load, ...load.rx })
  const level = TRAINING_LEVEL_LABELS[load.level_scaled.level] ?? load.level_scaled.level
  const weight = load.rx.weight_kg != null && !written.includes(`${load.rx.weight_kg}kg`) ? ` · ${load.rx.weight_kg}kg` : ''
  return `Scaled for ${level}` + (written ? ` · Rx ${written}${weight}` : weight ? ` · Rx${weight.slice(2)}` : '')
}

/** "In place of Pull-Up (Overhand)", or null for the written movement. */
export function scaledFromText(assignment: ExerciseAssignment): string | null {
  if (!assignment.scaled_from) return null
  return `In place of ${assignment.scaled_from_name ?? assignment.scaled_from}`
}

/** "Written for Elite · scaled for Novice": a track done below the level its
 *  sessions are written for; null at or above it, or for a track not scaled. */
export function scaledFor(track: Pick<Track, 'authored_level'>, level: string | undefined): string | null {
  const authored = track.authored_level
  if (!authored || !level) return null
  const rank = (lv: string) => (TRAINING_LEVELS as readonly string[]).indexOf(lv)
  if (rank(level) < 0 || rank(level) >= rank(authored)) return null
  const label = (lv: string) => TRAINING_LEVEL_LABELS[lv] ?? lv
  return `Written for ${label(authored)} · scaled for ${label(level)}`
}
