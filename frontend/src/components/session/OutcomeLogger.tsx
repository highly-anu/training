import { useRef, useState } from 'react'
import { cn } from '@/lib/utils'
import { useBioStore } from '@/store/bioStore'
import type { ExerciseLoad, RPE } from '@/api/types'
import { formatClock, outcomeFieldsFor, parseClock, type OutcomeExercise, type OutcomeField } from '@/lib/outcomeFields'

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
  exercise?: OutcomeExercise | null
  exerciseId: string
  sessionKey: string
  load: ExerciseLoad
  /** A test's scored slot: the result its standard needs is asked for first. */
  standard?: { result?: string | null } | null
}

type Field = OutcomeField

const LABEL: Record<Field, string> = { rounds: 'Rounds', minutes: 'Min', time: 'Time', km: 'km', reps: 'Reps', seconds: 'Hold s' }

function prescribed(load: ExerciseLoad, field: Field): string | undefined {
  switch (field) {
    case 'rounds':  return load.target_rounds != null ? String(load.target_rounds) : undefined
    case 'minutes': return load.duration_minutes != null ? String(load.duration_minutes)
                         : load.time_minutes != null ? String(load.time_minutes) : undefined
    case 'time':    return 'm:ss'
    case 'km':      return load.distance_km != null ? String(load.distance_km)
                         : load.distance_m != null ? String(load.distance_m / 1000) : undefined
    case 'reps':    return load.reps_per_round != null ? String(load.reps_per_round) : undefined
    case 'seconds': return load.hold_seconds != null ? String(load.hold_seconds) : undefined
  }
}

export function OutcomeLogger({ slotType, exercise, exerciseId, sessionKey, load, standard }: OutcomeLoggerProps) {
  const fields = outcomeFieldsFor(slotType, exercise, standard)
  const stored = useBioStore((s) => s.sessionPerformanceLogs[sessionKey]?.exercises[exerciseId])
  const setExerciseOutcome = useBioStore((s) => s.setExerciseOutcome)

  const [draft, setDraft] = useState<Record<Field, string>>({
    rounds:  stored?.rounds != null ? String(stored.rounds) : '',
    minutes: stored?.durationSec != null ? String(Math.round(stored.durationSec / 60)) : '',
    time:    stored?.durationSec != null ? formatClock(stored.durationSec) : '',
    km:      stored?.distanceKm != null ? String(stored.distanceKm) : '',
    reps:    stored?.sets?.[0]?.repsActual != null ? String(stored.sets[0].repsActual) : '',
    seconds: stored?.sets?.[0]?.durationSeconds != null ? String(stored.sets[0].durationSeconds) : '',
  })
  // What each field last saved: a blur that changed nothing writes nothing.
  const saved = useRef(draft)

  if (fields.length === 0) return null

  function commit(field: Field, raw: string) {
    if (raw.trim() === saved.current[field].trim()) return
    const n = raw.trim() === '' ? undefined : parseFloat(raw)
    const value = n != null && !isNaN(n) ? n : undefined
    // A clock that does not read stays in the field, unsaved, rather than
    // being stored as something else.
    const clock = field === 'time' ? parseClock(raw) : undefined
    if (field === 'time' && raw.trim() !== '' && clock == null) return
    if (field === 'time' && clock != null) setDraft((d) => ({ ...d, time: formatClock(clock) }))
    saved.current = { ...saved.current, [field]: field === 'time' && clock != null ? formatClock(clock) : raw }
    setExerciseOutcome(sessionKey, exerciseId, {
      rounds:      field === 'rounds'  ? value : stored?.rounds,
      durationSec: field === 'minutes' ? (value != null ? Math.round(value * 60) : undefined)
                 : field === 'time'    ? clock : stored?.durationSec,
      distanceKm:  field === 'km'      ? value : stored?.distanceKm,
      reps:        field === 'reps'    ? value : undefined,
      holdSec:     field === 'seconds' ? value : undefined,
    })
  }

  const logged = fields.some((f) => draft[f] !== '')

  return (
    <div className="flex flex-wrap items-center gap-2" aria-label="Log outcome">
      {load.advances_module && (
        <label className="flex items-center gap-1 text-[10px] text-muted-foreground">
          Bell kg
          <input type="number" min={1} step={0.5} aria-label={`Bell kg for ${exerciseId}`}
            defaultValue={stored?.weightKg ?? load.weight_kg ?? ''}
            className="h-6 w-14 rounded border border-border bg-background px-1.5 text-center text-[11px]"
            onBlur={(event) => {
              const weightKg = Number(event.target.value)
              if (Number.isFinite(weightKg) && weightKg > 0) setExerciseOutcome(sessionKey, exerciseId, { weightKg })
            }} />
        </label>
      )}
      {load.advances_module && (
        <label className="flex items-center gap-1 text-[10px] text-muted-foreground">
          RPE
          <input type="number" min={1} max={10} step={1}
            aria-label={`RPE for ${exerciseId}`} defaultValue={stored?.rpe ?? ''}
            className="h-6 w-14 rounded border border-border bg-background px-1.5 text-center text-[11px]"
            onBlur={(event) => {
              const value = Number(event.target.value)
              if (Number.isInteger(value) && value >= 1 && value <= 10) {
                setExerciseOutcome(sessionKey, exerciseId, { rpe: value as RPE })
              }
            }} />
        </label>
      )}
      {fields.map((f) => (
        <label key={f} className="flex items-center gap-1 text-[10px] text-muted-foreground">
          <span className="w-9 text-right">{LABEL[f]}</span>
          <input
            type={f === 'time' ? 'text' : 'number'}
            min={0}
            step={f === 'km' ? 0.1 : 1}
            inputMode={f === 'time' ? 'text' : 'decimal'}
            placeholder={prescribed(load, f) ?? '—'}
            value={draft[f]}
            onChange={(e) => setDraft((d) => ({ ...d, [f]: e.target.value }))}
            onBlur={(e) => commit(f, e.target.value)}
            // Enter only blurs: the blur saves, once.
            onKeyDown={(e) => { if (e.key === 'Enter') (e.target as HTMLInputElement).blur() }}
            className={cn(
              'h-6 rounded border border-border bg-background px-1.5 text-center text-[11px]',
              f === 'time' ? 'w-16' : 'w-14',
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
