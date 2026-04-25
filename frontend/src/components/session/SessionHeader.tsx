import { Clock } from 'lucide-react'
import { ModalityBadge } from '@/components/shared/ModalityBadge'
import { PhaseBadge } from '@/components/shared/PhaseBadge'
import type { Session, TrainingPhase } from '@/api/types'

interface SessionHeaderProps {
  session: Session
  day: string
  weekNumber: number
  weekInPhase: number
  phase: TrainingPhase
}

export function SessionHeader({ session, day, weekNumber, weekInPhase, phase }: SessionHeaderProps) {
  return (
    <div className="space-y-2">
      <div className="flex items-center gap-2 flex-wrap">
        <ModalityBadge modality={session.modality} />
        <PhaseBadge phase={phase} />
      </div>
      <h2 className="text-lg font-bold text-foreground">{session.archetype?.name ?? session.modality.replace(/_/g, ' ')}</h2>
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
