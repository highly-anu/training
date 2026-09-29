import { useState } from 'react'
import { cn } from '@/lib/utils'
import { useBioStore } from '@/store/bioStore'
import type { ExerciseLoad } from '@/api/types'
import { outcomeFieldsFor, type OutcomeField } from '@/lib/outcomeFields'

/**
 * Logging for slots that are not sets × reps.
 *
 * Until this existed, the session screen offered a logger only when
 * `load.sets > 0`, so a 60-minute Zone 2 run, an AMRAP, a ruck or a hold had
 * no way to record what happened. Every methodology whose currency is rounds,
 * minutes or kilometres — CrossFit, Uphill, Wildman — was unmeasurable by
 * construction. This writes the `ExercisePerformance` outcome fields the
 * server has always read (`rounds`, `durationSec`, `distanceKm`), beside the
 * prescription so planned and actual sit together.
 */

interface OutcomeLoggerProps {
  slotType: string
  exerciseId: string
  sessionKey: string
  load: ExerciseLoad
}

type Field = OutcomeField

const LABEL: Record<Field, string> = { rounds: 'Rounds', minutes: 'Min', km: 'km', reps: 'Reps' }

function prescribed(load: ExerciseLoad, field: Field): string | undefined {
  switch (field) {
    case 'rounds':  return load.target_rounds != null ? String(load.target_rounds) : undefined
    case 'minutes': return load.duration_minutes != null ? String(load.duration_minutes)
                         : load.time_minutes != null ? String(load.time_minutes) : undefined
    case 'km':      return load.distance_km != null ? String(load.distance_km)
                         : load.distance_m != null ? String(load.distance_m / 1000) : undefined
    case 'reps':    return load.reps_per_round != null ? String(load.reps_per_round) : undefined
  }
}

export function OutcomeLogger({ slotType, exerciseId, sessionKey, load }: OutcomeLoggerProps) {
  const fields = outcomeFieldsFor(slotType)
  const stored = useBioStore((s) => s.sessionPerformanceLogs[sessionKey]?.exercises[exerciseId])
  const setExerciseOutcome = useBioStore((s) => s.setExerciseOutcome)

  const [draft, setDraft] = useState<Record<Field, string>>({
    rounds:  stored?.rounds != null ? String(stored.rounds) : '',
    minutes: stored?.durationSec != null ? String(Math.round(stored.durationSec / 60)) : '',
    km:      stored?.distanceKm != null ? String(stored.distanceKm) : '',
    reps:    stored?.sets?.[0]?.repsActual != null ? String(stored.sets[0].repsActual) : '',
  })

  if (fields.length === 0) return null

  function commit(field: Field, raw: string) {
    const n = raw.trim() === '' ? undefined : parseFloat(raw)
    const value = n != null && !isNaN(n) ? n : undefined
    setExerciseOutcome(sessionKey, exerciseId, {
      rounds:      field === 'rounds'  ? value : stored?.rounds,
      durationSec: field === 'minutes' ? (value != null ? Math.round(value * 60) : undefined) : stored?.durationSec,
      distanceKm:  field === 'km'      ? value : stored?.distanceKm,
      reps:        field === 'reps'    ? value : undefined,
    })
  }

  const logged = fields.some((f) => draft[f] !== '')

  return (
    <div className="flex items-center gap-2" aria-label="Log outcome">
      {fields.map((f) => (
        <label key={f} className="flex items-center gap-1 text-[10px] text-muted-foreground">
          <span className="w-9 text-right">{LABEL[f]}</span>
          <input
            type="number"
            min={0}
            step={f === 'km' ? 0.1 : 1}
            inputMode="decimal"
            placeholder={prescribed(load, f) ?? '—'}
            value={draft[f]}
            onChange={(e) => setDraft((d) => ({ ...d, [f]: e.target.value }))}
            onBlur={(e) => commit(f, e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter') { commit(f, (e.target as HTMLInputElement).value); (e.target as HTMLInputElement).blur() } }}
            className={cn(
              'h-6 w-14 rounded border border-border bg-background px-1.5 text-center text-[11px]',
              'focus:outline-none focus:ring-1 focus:ring-primary',
              draft[f] !== '' && 'border-primary/50'
            )}
            aria-label={`${LABEL[f]} for ${exerciseId}`}
          />
        </label>
      ))}
      {logged && <span className="text-[10px] text-emerald-700 dark:text-emerald-300">logged</span>}
    </div>
  )
}
