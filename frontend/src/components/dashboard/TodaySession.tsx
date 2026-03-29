import { useNavigate } from 'react-router-dom'
import { format } from 'date-fns'
import { motion } from 'framer-motion'
import { ArrowRight, Clock, Dumbbell } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { ModalityBadge } from '@/components/shared/ModalityBadge'
import type { GeneratedProgram } from '@/api/types'

interface TodaySessionProps {
  program: GeneratedProgram
  weekIndex: number
}

export function TodaySession({ program, weekIndex }: TodaySessionProps) {
  const navigate = useNavigate()
  const today = format(new Date(), 'EEEE')
  const weekData = program.weeks[weekIndex]
  const sessions = weekData?.schedule[today] ?? []
  const session = sessions[0]

  if (!session) {
    return (
      <div className="h-full rounded-xl border border-dashed border-border/60 bg-card/50 p-6 flex flex-col items-center justify-center text-center">
        <Dumbbell className="size-8 text-muted-foreground/40 mb-2" />
        <p className="text-sm font-medium text-muted-foreground">Rest Day</p>
        <p className="text-xs text-muted-foreground/60 mt-1">
          {format(new Date(), 'EEEE, MMMM d')}
        </p>
      </div>
    )
  }

  return (
    <motion.div
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0, transition: { duration: 0.3 } }}
      className="h-full rounded-xl border bg-card p-5 shadow-sm flex flex-col gap-3"
    >
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="text-xs text-muted-foreground">{format(new Date(), 'EEEE, MMMM d')}</p>
          <h3 className="text-base font-bold text-foreground mt-0.5">{session.archetype.name}</h3>
        </div>
        <ModalityBadge modality={session.modality} />
      </div>

      <div className="flex items-center gap-4 text-xs text-muted-foreground">
        <span className="flex items-center gap-1">
          <Clock className="size-3.5" />
          ~{session.archetype.duration_estimate_minutes} min
        </span>
        <span>{session.exercises.length} exercises</span>
      </div>

      <Button
        size="sm"
        className="w-full gap-2 mt-auto"
        onClick={() => navigate(`/program/${(weekData.week_number)}/${today}`)}
      >
        Start Session <ArrowRight className="size-3.5" />
      </Button>
    </motion.div>
  )
}
