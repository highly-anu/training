import * as React from 'react'
import { Minus, Plus } from 'lucide-react'
import { cn } from '@/lib/utils'

/**
 * A number with its label, typed or stepped. Empty is `undefined`, never 0:
 * a field the athlete cleared is one they have not answered.
 */
export interface NumberFieldProps {
  label: string
  value: number | undefined
  onChange: (value: number | undefined) => void
  min?: number
  max?: number
  step?: number
  /** Marked as the field a problem names. */
  invalid?: boolean
  className?: string
}

export function NumberField({ label, value, onChange, min = 0, max = 100000, step = 1, invalid, className }: NumberFieldProps) {
  const id = React.useId()
  const clamp = (n: number) => Math.min(max, Math.max(min, Math.round(n * 100) / 100))
  const nudge = (by: number) => onChange(clamp((value ?? (by > 0 ? min - by : min + step)) + by))
  return (
    <div className={cn('flex flex-col gap-1', className)}>
      <label htmlFor={id} className="text-xs text-muted-foreground">{label}</label>
      <div className={cn('flex h-9 items-stretch rounded-md border border-input bg-background', invalid && 'border-bad')}>
        <button type="button" aria-label={`Less: ${label}`} onClick={() => nudge(-step)}
          className="flex w-7 items-center justify-center rounded-l-md text-muted-foreground hover:bg-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
          <Minus className="size-3" />
        </button>
        <input
          id={id}
          inputMode="decimal"
          aria-invalid={invalid || undefined}
          value={value ?? ''}
          onChange={(e) => {
            const text = e.target.value.replace(',', '.').trim()
            if (text === '') return onChange(undefined)
            const n = Number(text)
            if (!Number.isNaN(n)) onChange(clamp(n))
          }}
          className="w-12 min-w-0 flex-1 bg-transparent text-center text-sm tabular-nums focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        />
        <button type="button" aria-label={`More: ${label}`} onClick={() => nudge(step)}
          className="flex w-7 items-center justify-center rounded-r-md text-muted-foreground hover:bg-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
          <Plus className="size-3" />
        </button>
      </div>
    </div>
  )
}
