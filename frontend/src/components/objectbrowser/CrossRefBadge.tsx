import { ExternalLink } from 'lucide-react'
import type { ModelType, NavigateToFn } from './types'

interface CrossRefBadgeProps {
  label: string
  type: ModelType
  id: string
  navigateTo: NavigateToFn
}

export function CrossRefBadge({ label, type, id, navigateTo }: CrossRefBadgeProps) {
  return (
    <button
      onClick={() => navigateTo(type, id)}
      className="inline-flex items-center gap-1 px-2 py-0.5 rounded text-xs border border-border bg-muted/50 hover:border-primary/50 hover:bg-primary/5 hover:text-primary transition-colors"
    >
      {label}
      <ExternalLink className="size-2.5 opacity-50" />
    </button>
  )
}
