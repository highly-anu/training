import { useNavigate } from 'react-router-dom'
import { motion } from 'framer-motion'
import { Clock, CheckCircle2 } from 'lucide-react'
import { ModalityBadge } from '@/components/shared/ModalityBadge'
import { cn } from '@/lib/utils'
import { useProfileStore } from '@/store/profileStore'
import type { Session } from '@/api/types'

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

  return (
    <motion.button
      whileHover={{ scale: 1.02 }}
      whileTap={{ scale: 0.98 }}
      onClick={() => navigate(`/program/${weekNumber}/${day}`)}
      className={cn(
        'w-full rounded-lg border bg-card p-3 text-left transition-shadow hover:shadow-sm',
        isComplete
          ? 'border-emerald-500/30 bg-emerald-500/5 hover:border-emerald-500/50'
          : 'hover:border-primary/50',
        className
      )}
    >
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="text-xs font-semibold text-foreground truncate">{session.archetype?.name ?? session.modality.replace(/_/g, ' ')}</p>
          <ModalityBadge modality={session.modality} size="sm" className="mt-1" />
        </div>
        {isComplete
          ? <CheckCircle2 className="size-3.5 mt-0.5 text-emerald-500 shrink-0" />
          : <span className="size-3.5 mt-0.5 shrink-0" />
        }
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
