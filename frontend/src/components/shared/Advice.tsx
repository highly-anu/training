import type { TrainingLevel } from '@/api/types'
import { cn } from '@/lib/utils'

const LEVEL: Record<TrainingLevel, string> = {
  novice: 'Novice', intermediate: 'Intermediate', advanced: 'Advanced', elite: 'Elite',
}

/** The method's advice for a category or module: one text, or a sentence per
 *  level (Ido's versions), each after its level's name. The server sends the
 *  per-level form apart (`adviceByLevel`); Explore has no athlete to pick one. */
export function Advice({ advice, byLevel, className }: {
  advice: string | null
  byLevel?: Array<{ level: TrainingLevel; text: string }> | null
  className?: string
}) {
  if (!advice && !byLevel?.length) return null
  return (
    <div className={cn('space-y-1 italic text-muted-foreground', className)}>
      {advice && <p>{advice}</p>}
      {byLevel?.map((a) => (
        <p key={a.level}><span className="not-italic font-medium text-foreground/80">{LEVEL[a.level] ?? a.level}:</span> {a.text}</p>
      ))}
    </div>
  )
}
