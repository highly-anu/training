import { cn } from '@/lib/utils'

/**
 * Where a philosophy's analytics come from: its own analytics.yaml, or a
 * default synthesised from its frameworks. Same words on the Explore card and
 * the Program tab's methodology section.
 */
export function SpecSourceBadge({ source, file, className }: {
  source: 'declared' | 'default'; file?: string | null; className?: string
}) {
  const declared = source === 'declared'
  return (
    <span
      title={declared ? `Declared in ${file ?? 'analytics.yaml'}` : "Synthesised from the package's frameworks — it ships no analytics.yaml"}
      className={cn(
        'inline-block px-1.5 py-0.5 rounded text-[10px] font-mono border',
        declared
          ? 'border-emerald-500/30 bg-emerald-500/10 text-emerald-700 dark:text-emerald-300'
          : 'border-border bg-muted/40 text-muted-foreground',
        className,
      )}
    >
      {declared ? 'declared analytics' : 'default analytics'}
    </span>
  )
}
