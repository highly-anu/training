import { useNavigate } from 'react-router-dom'
import { motion } from 'framer-motion'
import { Clock, CheckCircle2, Activity } from 'lucide-react'
import { ModalityBadge } from '@/components/shared/ModalityBadge'
import { cn } from '@/lib/utils'
import { useProfileStore } from '@/store/profileStore'
import { useBioStore } from '@/store/bioStore'
import type { Session } from '@/api/types'
import { COMPLETION } from '@/lib/completionColors'

interface SessionCardProps {
  session: Session
  weekNumber: number
  day: string
  sessionIndex: number
  className?: string
}

export function SessionCard({ session, weekNumber, day, sessionIndex, className }: SessionCardProps) {
  const navigate = useNavigate()
  const sessionLogs = useProfileStore((s) => s.sessionLogs)
  const isComplete = sessionLogs[`${weekNumber}-${day}`]?.[sessionIndex] === true
  const workoutMatches = useBioStore((s) => s.workoutMatches)
  const dayKey = `${weekNumber}-${day}`
  const perKey = `${dayKey}-${sessionIndex}`
  const hasWorkout = workoutMatches.some(
    (m) => (m.sessionKey === perKey || m.sessionKey === dayKey) && m.matchConfidence !== 'rejected'
  )

  return (
    <motion.button
      whileHover={{ scale: 1.02 }}
      whileTap={{ scale: 0.98 }}
      onClick={() => navigate(`/program/${weekNumber}/${day}`)}
      className={cn(
        'w-full rounded-lg border bg-card p-3 text-left transition-shadow hover:shadow-sm',
        isComplete
          ? cn(COMPLETION.border, COMPLETION.bg, 'hover:border-emerald-500/50')
          : 'hover:border-primary/50',
        className
      )}
    >
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="text-xs font-semibold text-foreground truncate">{session.archetype?.name ?? session.modality.replace(/_/g, ' ')}</p>
          <div className="mt-1 flex flex-wrap items-center gap-1.5">
            <ModalityBadge modality={session.modality} size="sm" />
            {session.provenance?.borrowed && (
              // This session came from a package the philosophy declares it
              // borrows from — say so rather than passing it off as its own.
              <span
                title={session.provenance.reason}
                className="rounded-full bg-muted px-1.5 py-0.5 text-[9px] font-medium text-muted-foreground"
              >
                via {session.provenance.label ?? session.provenance.package.replace(/_/g, ' ')}
              </span>
            )}
          </div>
        </div>
        <div className="flex items-center gap-1 shrink-0 mt-0.5">
          {hasWorkout && <Activity className="size-3.5 text-blue-700 dark:text-blue-300" />}
          {isComplete
            ? <CheckCircle2 className={cn('size-3.5', COMPLETION.text)} />
            : <span className="size-3.5" />
          }
        </div>
      </div>
      {session.duration_min && (
        <div className="mt-2 flex items-center gap-1 text-[10px] text-muted-foreground">
          <Clock className="size-3" />
          {session.duration_min} min
        </div>
      )}
      <p className="mt-1.5 text-[10px] text-muted-foreground">
        {session.exercises.length} exercise{session.exercises.length !== 1 ? 's' : ''}
      </p>
    </motion.button>
  )
}
