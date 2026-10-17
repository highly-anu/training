import { cn } from '@/lib/utils'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import type { ModalityId } from '@/api/types'
import { STANDARD_LEVELS, levelName, type StandardLevel } from '@/lib/standards'

/** The modality a standard measures, as its colour (docs/frontend-design.md §8.1). */
function modalityColor(domain: string | null | undefined) {
  return domain ? MODALITY_COLORS[domain as ModalityId] : undefined
}

interface StandardLadderProps {
  /** Server-formatted thresholds per level (`standardsText`). */
  thresholds: Partial<Record<StandardLevel, string>>
  /** 0 = below entry … 4 = elite, from the server; undefined = no result yet. */
  levelIndex?: number | null
  /** The modality the standard measures; the filled rungs take its colour. */
  domain?: string | null
}

/**
 * Where a result sits on a standard. The rungs fill, up to the level reached,
 * in the colour of the modality the standard measures; the level itself is
 * read from position and its word — never from a colour of its own, so a level
 * can't be mistaken for a pass/fail status (§8.8). The level is computed by the
 * server; this only draws it.
 */
export function StandardLadder({ thresholds, levelIndex, domain }: StandardLadderProps) {
  const fill = modalityColor(domain)?.hex
  const reached = levelIndex ?? 0
  return (
    <div className="space-y-1">
      <div className="flex gap-1" role="img"
        aria-label={levelIndex == null ? 'No result yet' : `${levelName(STANDARD_LEVELS[reached - 1])} of four levels`}>
        {STANDARD_LEVELS.map((lvl, i) => (
          <div key={lvl} className="flex-1">
            <div
              className={cn('h-2 rounded-sm transition-colors', i < reached ? (fill ? '' : 'bg-primary') : 'bg-muted')}
              style={i < reached && fill ? { backgroundColor: fill } : undefined}
            />
          </div>
        ))}
      </div>
      <div className="flex gap-1 text-[10px] leading-tight">
        {STANDARD_LEVELS.map((lvl, i) => (
          <div key={lvl} className={cn('flex-1 min-w-0', i === 3 && 'text-right', i > 0 && i < 3 && 'text-center')}>
            <span className="block truncate text-muted-foreground/70">{lvl}</span>
            <span className={cn('block truncate tabular-nums', i < reached ? 'text-foreground' : 'text-muted-foreground')}>
              {thresholds[lvl] ?? '—'}
            </span>
          </div>
        ))}
      </div>
    </div>
  )
}

/** The level reached, as a small badge in the standard's modality colour. */
export function StandardLevelBadge({ level, domain, className }: {
  level: string | null | undefined; domain?: string | null; className?: string
}) {
  const c = modalityColor(domain)
  return (
    <span className={cn(
      'inline-flex items-center rounded px-1.5 py-0.5 text-[10px] font-medium whitespace-nowrap',
      level ? (c ? `${c.bg} ${c.text}` : 'bg-primary/15 text-foreground') : 'bg-muted text-muted-foreground',
      className,
    )}>
      {levelName(level)}
    </span>
  )
}
