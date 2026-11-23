import { createElement } from 'react'
import { FlaskConical } from 'lucide-react'
import { WorkoutIcon } from '@/components/icons/WorkoutIcon'
import { WORKOUT_ICONS } from '@/components/icons/workoutIcons.generated'
import { modalityHex, modalityLabel } from '@/lib/modalityColors'
import { modalityIcon } from '@/lib/modalityIcons'
import { cn } from '@/lib/utils'

const SIZES = {
  sm: { icon: 'size-3.5', tile: 'size-6 rounded-md' },
  md: { icon: 'size-4', tile: 'size-8 rounded-lg' },
  lg: { icon: 'size-5', tile: 'size-10 rounded-xl' },
} as const

interface ModalityMarkProps {
  modality: string | null | undefined
  /** A session's workout icon (src/session_icon.py); without one, the modality's. */
  icon?: string | null
  /** A test session: a flask, uncoloured. */
  test?: boolean
  size?: keyof typeof SIZES
  /** On a neutral square: what leads a card or a header. Without it the icon sits before a name. */
  tile?: boolean
  className?: string
}

/**
 * What kind of training something is: one icon in the modality's colour, the
 * session's own workout icon when it has one (docs/frontend-design.md §8.1,
 * §15.4). The surface under it stays neutral — in Explore the modality's
 * colour is on this mark and nowhere else — and the icon carries the
 * modality's name, so the colour never speaks alone.
 */
export function ModalityMark({ modality, icon, test = false, size = 'sm', tile = false, className }: ModalityMarkProps) {
  const cls = cn(SIZES[size].icon, 'shrink-0', !tile && className)
  const glyph = test
    ? <FlaskConical className={cn(cls, 'text-muted-foreground')} aria-label="Test" />
    : icon && WORKOUT_ICONS[icon]
      ? <WorkoutIcon icon={icon} modality={modality} className={cls} />
      : createElement(modalityIcon(modality), {
        className: cls, style: { color: modalityHex(modality) }, 'aria-label': modalityLabel(modality),
      })
  if (!tile) return glyph
  return (
    <span className={cn('flex shrink-0 items-center justify-center bg-muted/60', SIZES[size].tile, className)}>
      {glyph}
    </span>
  )
}
