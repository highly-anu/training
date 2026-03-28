import { cn } from '@/lib/utils'

const STEPS = [
  { n: 1, label: 'Goal' },
  { n: 2, label: 'Tune' },
  { n: 3, label: 'Constraints' },
  { n: 4, label: 'Generate' },
]

interface StepIndicatorProps {
  current: 1 | 2 | 3 | 4
}

export function StepIndicator({ current }: StepIndicatorProps) {
  return (
    <div className="flex items-center gap-0">
      {STEPS.map(({ n, label }, i) => (
        <div key={n} className="flex items-center">
          <div className="flex flex-col items-center gap-1">
            <div
              className={cn(
                'flex size-7 items-center justify-center rounded-full border-2 text-xs font-semibold transition-colors',
                n < current
                  ? 'border-primary bg-primary text-primary-foreground'
                  : n === current
                    ? 'border-primary bg-primary/10 text-primary'
                    : 'border-border bg-background text-muted-foreground'
              )}
            >
              {n < current ? (
                <svg className="size-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={3}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
                </svg>
              ) : (
                n
              )}
            </div>
            <span
              className={cn(
                'text-[10px] font-medium hidden sm:block',
                n === current ? 'text-primary' : 'text-muted-foreground'
              )}
            >
              {label}
            </span>
          </div>
          {i < STEPS.length - 1 && (
            <div
              className={cn(
                'mx-2 mb-4 h-px w-8 sm:w-14 transition-colors',
                n < current ? 'bg-primary' : 'bg-border'
              )}
            />
          )}
        </div>
      ))}
    </div>
  )
}
