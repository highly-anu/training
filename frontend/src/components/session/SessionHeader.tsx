import { Clock } from 'lucide-react'
import { TrackBadge } from '@/components/shared/TrackBadge'
import { WorkoutIcon } from '@/components/icons/WorkoutIcon'
import { ModalityBadge } from '@/components/shared/ModalityBadge'
import { PhaseBadge } from '@/components/shared/PhaseBadge'
import { TestBadge } from '@/components/standards/TestBadge'
import type { Session, TrainingPhase } from '@/api/types'

interface SessionHeaderProps {
  session: Session
  day: string
  weekNumber: number
  weekInPhase: number
  phase: TrainingPhase
  /** The philosophy's own phase name. */
  phaseLabel?: string
}

export function SessionHeader({ session, day, weekNumber, weekInPhase, phase, phaseLabel }: SessionHeaderProps) {
  return (
    <div className="space-y-2">
      <div className="flex items-center gap-2 flex-wrap">
        <ModalityBadge modality={session.modality} />
        <PhaseBadge phase={phase} label={phaseLabel} />
        {session.test && <TestBadge test={session.test} size="md" />}
        <TrackBadge session={session} size="md" />
      </div>
      {session.test?.instead_of?.name && (
        <p className="text-xs text-muted-foreground">
          A test of this phase's standards, in place of {session.test.instead_of.name}. Log each result on its exercise below.
        </p>
      )}
      <h2 className="flex items-center gap-2 text-lg font-bold text-foreground">
        <WorkoutIcon icon={session.icon} modality={session.modality} className="size-6" />
        {session.archetype?.name ?? session.modality.replace(/_/g, ' ')}
      </h2>
      <p className="text-sm text-muted-foreground">
        Week {weekNumber} — {day}
        <span className="ml-2 text-xs text-muted-foreground/60">(phase wk {weekInPhase})</span>
      </p>
      {(session.archetype?.duration_estimate_minutes ?? 0) > 0 && (
        <div className="flex items-center gap-1.5 text-sm text-muted-foreground">
          <Clock className="size-3.5" />
          ~{session.archetype!.duration_estimate_minutes} min
        </div>
      )}
    </div>
  )
}
