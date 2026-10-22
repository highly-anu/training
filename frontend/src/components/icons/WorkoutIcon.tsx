import { cn } from '@/lib/utils'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import type { ModalityId } from '@/api/types'
import { WORKOUT_ICONS } from './workoutIcons.generated'

interface WorkoutIconProps {
  /** The session's `icon` (src/session_icon.py): what its main exercise is. */
  icon?: string | null
  /** Tints the glyph: the icon says what is in the session, the colour what
   *  kind of training it is (docs/frontend-design.md §15.4). */
  modality?: ModalityId | string | null
  className?: string
}

/** A session's workout icon, the one both watches and the phone draw for it.
 *  Renders nothing for a session without one — its ModalityBadge says the rest. */
export function WorkoutIcon({ icon, modality, className }: WorkoutIconProps) {
  const glyph = icon ? WORKOUT_ICONS[icon] : undefined
  if (!glyph) return null
  const hex = modality ? MODALITY_COLORS[modality as ModalityId]?.hex : undefined
  return (
    <svg
      viewBox="0 0 100 100"
      role="img"
      aria-label={glyph.label}
      className={cn('size-5 shrink-0', !hex && 'text-muted-foreground', className)}
      style={hex ? { color: hex } : undefined}
    >
      <path fill="currentColor" d={glyph.d} />
    </svg>
  )
}
