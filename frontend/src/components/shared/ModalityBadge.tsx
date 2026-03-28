import { cn } from '@/lib/utils'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import type { ModalityId } from '@/api/types'

interface ModalityBadgeProps {
  modality: ModalityId
  className?: string
  size?: 'sm' | 'md'
}

export function ModalityBadge({ modality, className, size = 'md' }: ModalityBadgeProps) {
  const colors = MODALITY_COLORS[modality]
  if (!colors) return null

  return (
    <span
      className={cn(
        'inline-flex items-center rounded-full border font-medium',
        colors.bg,
        colors.text,
        colors.border,
        size === 'sm' ? 'px-1.5 py-0.5 text-[10px]' : 'px-2 py-0.5 text-xs',
        className
      )}
    >
      {colors.label}
    </span>
  )
}
