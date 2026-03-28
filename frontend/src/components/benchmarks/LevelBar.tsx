import { cn } from '@/lib/utils'

const LEVELS = ['entry', 'intermediate', 'advanced', 'elite'] as const
const LEVEL_LABELS = ['I', 'II', 'III', 'IV']
type Level = typeof LEVELS[number]

interface LevelBarProps {
  standards: Record<Level, number>
  userValue?: number
  unit: string
  lowerIsBetter?: boolean
}

function getLevelIndex(value: number, standards: Record<Level, number>, lowerIsBetter: boolean): number {
  if (lowerIsBetter) {
    if (value <= standards.elite) return 4
    if (value <= standards.advanced) return 3
    if (value <= standards.intermediate) return 2
    if (value <= standards.entry) return 1
    return 0
  } else {
    if (value >= standards.elite) return 4
    if (value >= standards.advanced) return 3
    if (value >= standards.intermediate) return 2
    if (value >= standards.entry) return 1
    return 0
  }
}

export function LevelBar({ standards, userValue, unit, lowerIsBetter = false }: LevelBarProps) {
  const userLevel = userValue !== undefined ? getLevelIndex(userValue, standards, lowerIsBetter) : undefined

  return (
    <div className="space-y-1.5">
      {/* Level bars */}
      <div className="flex gap-1">
        {LEVELS.map((level, i) => (
          <div key={level} className="flex-1 text-center">
            <div
              className={cn(
                'h-2 rounded-sm transition-colors',
                userLevel !== undefined && i < userLevel
                  ? 'bg-primary'
                  : 'bg-muted'
              )}
            />
            <span className="text-[9px] text-muted-foreground mt-0.5 block font-mono">
              {LEVEL_LABELS[i]}
            </span>
          </div>
        ))}
      </div>

      {/* Standard values */}
      <div className="flex justify-between text-[10px] text-muted-foreground">
        {LEVELS.map((level) => (
          <span key={level}>{standards[level]}{unit}</span>
        ))}
      </div>
    </div>
  )
}
