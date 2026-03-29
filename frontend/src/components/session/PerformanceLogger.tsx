import { useState } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { ChevronDown, ChevronUp } from 'lucide-react'
import { cn } from '@/lib/utils'
import { useProfileStore } from '@/store/profileStore'
import { useBioStore } from '@/store/bioStore'
import type { SetPerformance, RPE } from '@/api/types'

interface PerformanceLoggerProps {
  sets: number
  exerciseId: string
  sessionKey: string
  prescribedRpe?: number
  prescribedWeightKg?: number
}

export function PerformanceLogger({
  sets,
  exerciseId,
  sessionKey,
  prescribedRpe,
  prescribedWeightKg,
}: PerformanceLoggerProps) {
  const storeKey = `${sessionKey}-${exerciseId}`
  const storedBooleans = useProfileStore((s) => s.sessionLogs[storeKey])
  const setSessionLog = useProfileStore((s) => s.setSessionLog)
  const storedPerf = useBioStore((s) => s.sessionPerformanceLogs[sessionKey]?.exercises[exerciseId])
  const setSetPerformance = useBioStore((s) => s.setSetPerformance)

  const [expanded, setExpanded] = useState(false)
  const [completed, setCompleted] = useState<boolean[]>(
    storedBooleans ?? Array(sets).fill(false)
  )
  // Local detail state — keyed by setIndex
  const [details, setDetails] = useState<Record<number, Partial<SetPerformance>>>(() => {
    if (!storedPerf) return {}
    const out: Record<number, Partial<SetPerformance>> = {}
    storedPerf.sets.forEach((s) => {
      out[s.setIndex] = s
    })
    return out
  })

  function toggle(i: number) {
    setCompleted((prev) => {
      const next = [...prev]
      next[i] = !next[i]
      setSessionLog(storeKey, next)
      // Sync completion to bioStore
      const detail = details[i] ?? {}
      setSetPerformance(sessionKey, exerciseId, {
        setIndex: i,
        completed: next[i],
        repsActual: detail.repsActual,
        weightKg: detail.weightKg,
        rpe: detail.rpe,
      })
      return next
    })
  }

  function updateDetail(i: number, field: keyof SetPerformance, raw: string) {
    const numVal = raw === '' ? undefined : parseFloat(raw)
    setDetails((prev) => {
      const next = { ...prev, [i]: { ...prev[i], [field]: numVal } }
      setSetPerformance(sessionKey, exerciseId, {
        setIndex: i,
        completed: completed[i] ?? false,
        repsActual: next[i]?.repsActual,
        weightKg: next[i]?.weightKg,
        rpe: next[i]?.rpe as RPE | undefined,
      })
      return next
    })
  }

  const doneCount = completed.filter(Boolean).length

  return (
    <div className="space-y-1.5">
      {/* Set buttons row */}
      <div className="flex items-center gap-1.5">
        {completed.map((done, i) => (
          <motion.button
            key={`${exerciseId}-set-${i}`}
            whileTap={{ scale: 1.3 }}
            onClick={() => toggle(i)}
            animate={{ backgroundColor: done ? 'var(--color-primary)' : undefined }}
            transition={{ duration: 0.15 }}
            className={cn(
              'size-6 rounded-md border transition-colors text-[10px] font-bold',
              done
                ? 'border-primary bg-primary text-primary-foreground'
                : 'border-border bg-muted text-muted-foreground hover:border-primary/60'
            )}
            aria-label={`Set ${i + 1} ${done ? 'completed' : 'pending'}`}
          >
            {i + 1}
          </motion.button>
        ))}
        <span className="ml-1 text-xs text-muted-foreground">
          {doneCount}/{sets}
        </span>
        <button
          type="button"
          onClick={() => setExpanded((v) => !v)}
          className="ml-1 p-0.5 rounded text-muted-foreground hover:text-foreground transition-colors"
          aria-label={expanded ? 'Hide set details' : 'Log set details'}
        >
          {expanded ? <ChevronUp className="size-3.5" /> : <ChevronDown className="size-3.5" />}
        </button>
      </div>

      {/* Expanded detail inputs */}
      <AnimatePresence>
        {expanded && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: 'auto' }}
            exit={{ opacity: 0, height: 0 }}
            transition={{ duration: 0.18 }}
            className="overflow-hidden"
          >
            <div className="rounded-md border border-border bg-muted/30 p-2 space-y-1">
              {/* Header row */}
              <div className="grid grid-cols-[24px_1fr_1fr_1fr] gap-2 px-1">
                <span className="text-[10px] text-muted-foreground">#</span>
                <span className="text-[10px] text-muted-foreground text-center">Reps</span>
                <span className="text-[10px] text-muted-foreground text-center">kg</span>
                <span className="text-[10px] text-muted-foreground text-center">RPE</span>
              </div>
              {Array.from({ length: sets }, (_, i) => (
                <div key={i} className="grid grid-cols-[24px_1fr_1fr_1fr] gap-2 items-center">
                  <span
                    className={cn(
                      'text-[11px] font-semibold text-center',
                      completed[i] ? 'text-primary' : 'text-muted-foreground'
                    )}
                  >
                    {i + 1}
                  </span>
                  <input
                    type="number"
                    min={0}
                    step={1}
                    placeholder="—"
                    value={details[i]?.repsActual ?? ''}
                    onChange={(e) => updateDetail(i, 'repsActual', e.target.value)}
                    className="h-6 w-full rounded border border-border bg-background px-1.5 text-center text-[11px] focus:outline-none focus:ring-1 focus:ring-primary"
                  />
                  <input
                    type="number"
                    min={0}
                    step={0.5}
                    placeholder={prescribedWeightKg != null ? String(prescribedWeightKg) : '—'}
                    value={details[i]?.weightKg ?? ''}
                    onChange={(e) => updateDetail(i, 'weightKg', e.target.value)}
                    className="h-6 w-full rounded border border-border bg-background px-1.5 text-center text-[11px] focus:outline-none focus:ring-1 focus:ring-primary"
                  />
                  <input
                    type="number"
                    min={1}
                    max={10}
                    step={1}
                    placeholder={prescribedRpe != null ? String(prescribedRpe) : '—'}
                    value={details[i]?.rpe ?? ''}
                    onChange={(e) => updateDetail(i, 'rpe', e.target.value)}
                    className="h-6 w-full rounded border border-border bg-background px-1.5 text-center text-[11px] focus:outline-none focus:ring-1 focus:ring-primary"
                  />
                </div>
              ))}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  )
}
