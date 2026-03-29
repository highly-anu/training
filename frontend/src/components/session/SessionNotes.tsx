import { useState } from 'react'
import { cn } from '@/lib/utils'
import { useBioStore } from '@/store/bioStore'
import type { FatigueRating } from '@/api/types'

interface SessionNotesProps {
  sessionKey: string
}

const FATIGUE_LABELS: Record<FatigueRating, string> = {
  1: 'Fresh',
  2: 'Light',
  3: 'Moderate',
  4: 'Heavy',
  5: 'Cooked',
}

const FATIGUE_COLORS: Record<FatigueRating, string> = {
  1: 'border-emerald-500 bg-emerald-500/10 text-emerald-500',
  2: 'border-green-500 bg-green-500/10 text-green-500',
  3: 'border-amber-500 bg-amber-500/10 text-amber-500',
  4: 'border-orange-500 bg-orange-500/10 text-orange-500',
  5: 'border-red-500 bg-red-500/10 text-red-500',
}

export function SessionNotes({ sessionKey }: SessionNotesProps) {
  const stored = useBioStore((s) => s.sessionPerformanceLogs[sessionKey])
  const setSessionNotes = useBioStore((s) => s.setSessionNotes)

  const [notes, setNotes] = useState(stored?.notes ?? '')
  const [fatigue, setFatigue] = useState<FatigueRating | undefined>(stored?.fatigueRating)

  function handleNotesChange(val: string) {
    setNotes(val)
    setSessionNotes(sessionKey, val, fatigue)
  }

  function handleFatigueChange(val: FatigueRating) {
    const next = fatigue === val ? undefined : val
    setFatigue(next)
    setSessionNotes(sessionKey, notes, next)
  }

  return (
    <div className="space-y-3 rounded-lg border border-border bg-card/50 p-4">
      <h3 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
        Session Notes
      </h3>

      {/* Fatigue rating */}
      <div className="space-y-1.5">
        <p className="text-xs text-muted-foreground">How did it feel?</p>
        <div className="flex gap-1.5">
          {([1, 2, 3, 4, 5] as FatigueRating[]).map((val) => (
            <button
              key={val}
              type="button"
              onClick={() => handleFatigueChange(val)}
              className={cn(
                'flex-1 rounded-md border px-1 py-1.5 text-[10px] font-medium transition-colors',
                fatigue === val
                  ? FATIGUE_COLORS[val]
                  : 'border-border text-muted-foreground hover:border-primary/50'
              )}
            >
              {val}
              <span className="block text-[9px] opacity-70">{FATIGUE_LABELS[val]}</span>
            </button>
          ))}
        </div>
      </div>

      {/* Notes textarea */}
      <textarea
        rows={3}
        placeholder="How did the session go? Any notes on form, PRs, or how you felt…"
        value={notes}
        onChange={(e) => handleNotesChange(e.target.value)}
        className="w-full resize-none rounded-md border border-border bg-background px-3 py-2 text-sm placeholder:text-muted-foreground/50 focus:outline-none focus:ring-1 focus:ring-primary"
      />
    </div>
  )
}
