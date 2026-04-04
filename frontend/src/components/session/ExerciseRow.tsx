import { motion } from 'framer-motion'
import { PerformanceLogger } from './PerformanceLogger'
import { MetaSlot } from './MetaSlot'
import { formatLoad } from '@/lib/formatLoad'
import { useBioStore } from '@/store/bioStore'
import type { ExerciseAssignment, SetPerformance } from '@/api/types'

interface ExerciseRowProps {
  assignment: ExerciseAssignment
  index: number
  sessionKey: string
}

export function ExerciseRow({ assignment, index, sessionKey }: ExerciseRowProps) {
  const getPerformanceLog = useBioStore((s) => s.getPerformanceLog)

  if (assignment.meta) {
    return <MetaSlot assignment={assignment} />
  }

  // Injury-managed or unresolvable slot — render a soft note instead of crashing
  if (!assignment.exercise) {
    return (
      <div className="flex items-center gap-3 rounded-md bg-muted/30 px-4 py-2.5 text-xs text-muted-foreground/60 italic">
        {(assignment as { injury_skip?: boolean }).injury_skip
          ? `(${assignment.slot_role?.replace(/_/g, ' ')} — skipped: injury management)`
          : `(${assignment.slot_role?.replace(/_/g, ' ')} — no exercise available)`}
      </div>
    )
  }

  const loadStr = formatLoad(assignment.load)
  const hasSets = typeof assignment.load.sets === 'number' && assignment.load.sets > 0
  const perfLog = getPerformanceLog(sessionKey) ?? getPerformanceLog(`${sessionKey}-0`)
  const logged = perfLog?.exercises[assignment.exercise.id]

  return (
    <motion.div
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0, transition: { delay: index * 0.05, duration: 0.2 } }}
      className="flex items-start gap-4 rounded-lg border border-border bg-card p-4 hover:border-primary/30 transition-colors"
    >
      {/* Index */}
      <span className="shrink-0 flex size-6 items-center justify-center rounded-full bg-muted text-[10px] font-semibold text-muted-foreground mt-0.5">
        {index + 1}
      </span>

      {/* Main content */}
      <div className="flex-1 min-w-0">
        <div className="flex flex-wrap items-start justify-between gap-2">
          <div>
            <h4 className="text-sm font-semibold text-foreground">{assignment.exercise.name}</h4>
            {loadStr && (
              <p className="mt-0.5 text-xs font-mono text-primary">{loadStr}</p>
            )}
            {assignment.load_note && (
              <p className="mt-0.5 text-[11px] text-muted-foreground">{assignment.load_note}</p>
            )}
          </div>
          {hasSets && (
            <PerformanceLogger
              sets={assignment.load.sets!}
              exerciseId={assignment.exercise.id}
              sessionKey={sessionKey}
              prescribedRpe={assignment.load.target_rpe}
              prescribedWeightKg={assignment.load.weight_kg}
            />
          )}
        </div>
        {assignment.notes && (
          <p className="mt-1.5 text-[11px] text-muted-foreground leading-relaxed">{assignment.notes}</p>
        )}
        {assignment.exercise.notes && !assignment.notes && (
          <p className="mt-1.5 text-[11px] text-muted-foreground/70 leading-relaxed italic">
            {assignment.exercise.notes}
          </p>
        )}
        {logged && logged.sets.length > 0 && (
          <div className="mt-2 border-t border-border/40 pt-2">
            <p className="text-[10px] font-semibold uppercase tracking-wide text-muted-foreground mb-1">Logged</p>
            <div className="flex flex-col gap-0.5">
              {logged.sets.map((s: SetPerformance, i: number) => (
                <p key={i} className="text-[11px] text-muted-foreground font-mono">
                  {formatSetLine(s, i)}
                </p>
              ))}
            </div>
          </div>
        )}
      </div>
    </motion.div>
  )
}

function formatSetLine(s: SetPerformance, i: number): string {
  const parts: string[] = [`Set ${i + 1}:`]
  if (s.repsActual != null) parts.push(`${s.repsActual} reps`)
  if (s.weightKg != null) parts.push(`@ ${s.weightKg} kg`)
  if (s.durationSeconds != null) parts.push(`${s.durationSeconds}s`)
  if (s.rpe != null) parts.push(`RPE ${s.rpe}`)
  return parts.join(' ')
}
