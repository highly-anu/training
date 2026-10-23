import { useNavigate } from 'react-router-dom'
import { motion } from 'framer-motion'
import { Clock, CheckCircle2, Activity, CircleSlash } from 'lucide-react'
import { WorkoutIcon } from '@/components/icons/WorkoutIcon'
import { ModalityBadge } from '@/components/shared/ModalityBadge'
import { TestBadge } from '@/components/standards/TestBadge'
import { cn } from '@/lib/utils'
import { useProfileStore } from '@/store/profileStore'
import { useBioStore } from '@/store/bioStore'
import type { Session } from '@/api/types'
import { COMPLETION } from '@/lib/completionColors'
import { hasSessionMatch, sessionKeyVariants } from '@/lib/sessionMatching'
import { useProgramStore } from '@/store/programStore'
import { heldBackSlots, sessionNotes } from '@/lib/heldBack'

interface SessionCardProps {
  session: Session
  weekNumber: number
  day: string
  sessionIndex: number
  className?: string
  /**
   * A program that is not the active one (the preview's draft): no logs or
   * matched workouts are read for it, and opening calls this instead of
   * navigating to the active program's session page.
   */
  onOpen?: () => void
  /** Marked as changed (a preview of a regenerate). */
  highlight?: boolean
}

export function SessionCard({ session, weekNumber, day, sessionIndex, className, onOpen, highlight }: SessionCardProps) {
  const navigate = useNavigate()
  const sessionLogs = useProfileStore((s) => s.sessionLogs)
  const workoutMatches = useBioStore((s) => s.workoutMatches)
  const programVersionId = useProgramStore((s) => s.programVersionId)
  const isDraft = onOpen !== undefined
  const isComplete = !isDraft && sessionLogs[`${weekNumber}-${day}`]?.[sessionIndex] === true
  const dayKey = `${weekNumber}-${day}`
  const hasWorkout = !isDraft && hasSessionMatch(
    workoutMatches,
    sessionKeyVariants(dayKey, sessionIndex),
    programVersionId
  )
  const heldBack = heldBackSlots(session).length
  const notes = sessionNotes(session)

  return (
    <motion.button
      whileHover={{ scale: 1.02 }}
      whileTap={{ scale: 0.98 }}
      onClick={() => (onOpen ? onOpen() : navigate(`/program/${weekNumber}/${day}`))}
      className={cn(
        'w-full rounded-lg border bg-card p-3 text-left transition-shadow hover:shadow-sm',
        isComplete
          ? cn(COMPLETION.border, COMPLETION.bg, 'hover:border-emerald-500/50')
          : 'hover:border-primary/50',
        highlight && 'border-primary/60 ring-1 ring-primary/30',
        className
      )}
    >
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="flex items-center gap-1.5 text-xs font-semibold text-foreground">
            <WorkoutIcon icon={session.icon} modality={session.modality} className="size-4" />
            <span className="truncate">{session.archetype?.name ?? session.modality.replace(/_/g, ' ')}</span>
          </p>
          <div className="mt-1 flex flex-wrap items-center gap-1.5">
            <ModalityBadge modality={session.modality} size="sm" />
            {session.test && <TestBadge test={session.test} />}
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
        {heldBack > 0 && (
          // Icon and words, never colour alone (design system §1.6).
          <span className="ml-1 inline-flex items-center gap-0.5 text-amber-700 dark:text-amber-300">
            · <CircleSlash className="size-2.5" aria-hidden="true" /> {heldBack} held back
          </span>
        )}
      </p>
      {notes.map((n) => (
        <p key={n} className="mt-1 text-[10px] leading-snug text-amber-700 dark:text-amber-300">{n}</p>
      ))}
      {highlight && <p className="mt-1 text-[10px] font-medium text-primary">Changes</p>}
    </motion.button>
  )
}
