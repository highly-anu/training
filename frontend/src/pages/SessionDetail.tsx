import { useParams, useNavigate, Link } from 'react-router-dom'
import { motion } from 'framer-motion'
import { ChevronLeft, Wand2, CheckCircle2, Circle } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Separator } from '@/components/ui/separator'
import { SessionHeader } from '@/components/session/SessionHeader'
import { ExerciseRow } from '@/components/session/ExerciseRow'
import { SessionNotes } from '@/components/session/SessionNotes'
import { WorkoutSummaryCard } from '@/components/session/WorkoutSummaryCard'
import { EmptyState } from '@/components/shared/EmptyState'
import { useCurrentProgram } from '@/api/programs'
import { useProfileStore } from '@/store/profileStore'
import { useBioStore } from '@/store/bioStore'

export function SessionDetail() {
  const { week, day } = useParams<{ week: string; day: string }>()
  const navigate = useNavigate()
  const program = useCurrentProgram()

  if (!program) {
    return (
      <motion.div
        key="session-empty"
        initial={{ opacity: 0, y: 16 }}
        animate={{ opacity: 1, y: 0, transition: { duration: 0.25 } }}
        exit={{ opacity: 0, y: -8, transition: { duration: 0.15 } }}
        className="p-6"
      >
        <EmptyState
          title="No program loaded"
          description="Generate a program first to view session details."
          action={{ label: 'Build a Program', onClick: () => navigate('/builder') }}
          icon={<Wand2 className="size-10" />}
        />
      </motion.div>
    )
  }

  const { sessionLogs, setSessionLog } = useProfileStore()
  const upsertSessionPerformance = useBioStore((s) => s.upsertSessionPerformance)

  const weekNumber = parseInt(week ?? '1', 10)
  const weekData = program.weeks.find((w) => w.week_number === weekNumber)
  const sessions = weekData?.schedule[day ?? ''] ?? []

  const sessionKey = `${weekNumber}-${day ?? ''}`
  const isComplete = sessionLogs[sessionKey]?.[0] === true
  function toggleComplete() {
    const next = !isComplete
    setSessionLog(sessionKey, [next])
    if (next) {
      upsertSessionPerformance({
        sessionKey,
        exercises: {},
        notes: '',
        completedAt: new Date().toISOString(),
      })
    }
  }

  if (!weekData || sessions.length === 0) {
    return (
      <motion.div
        key="session-not-found"
        initial={{ opacity: 0, y: 16 }}
        animate={{ opacity: 1, y: 0, transition: { duration: 0.25 } }}
        exit={{ opacity: 0, y: -8, transition: { duration: 0.15 } }}
        className="p-6"
      >
        <Button variant="ghost" size="sm" asChild className="mb-4 -ml-2">
          <Link to="/program"><ChevronLeft className="size-4" /> Program</Link>
        </Button>
        <EmptyState
          title="Rest day"
          description={`Week ${weekNumber} — ${day} is a rest day.`}
        />
      </motion.div>
    )
  }

  return (
    <motion.div
      key={`session-${week}-${day}`}
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0, transition: { duration: 0.25 } }}
      exit={{ opacity: 0, y: -8, transition: { duration: 0.15 } }}
      className="flex h-full flex-col"
    >
      {/* Back nav */}
      <div className="border-b bg-card/50 px-6 py-3">
        <Button variant="ghost" size="sm" asChild className="-ml-2">
          <Link to="/program"><ChevronLeft className="size-4" /> Program</Link>
        </Button>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto p-6 space-y-6">
        {sessions.map((session, sessionIdx) => (
          <div key={sessionIdx} className="space-y-4">
            {sessionIdx > 0 && <Separator />}

            <SessionHeader
              session={session}
              day={day ?? ''}
              weekNumber={weekNumber}
              weekInPhase={weekData.week_in_phase}
              phase={weekData.phase}
            />

            <div className="space-y-2">
              {session.exercises.map((assignment, i) => (
                <ExerciseRow key={i} assignment={assignment} index={i} sessionKey={`${weekNumber}-${day ?? ''}`} />
              ))}
            </div>
          </div>
        ))}

        {/* Workout summary (HR data if imported workout is matched) */}
        <WorkoutSummaryCard sessionKey={sessionKey} sessions={sessions} />

        {/* Session notes + fatigue rating */}
        <SessionNotes sessionKey={sessionKey} />

        <Separator />

        <button
          type="button"
          onClick={toggleComplete}
          className={`w-full flex items-center justify-center gap-2 h-10 rounded-lg text-sm font-medium transition-colors ${
            isComplete
              ? 'bg-emerald-500/10 text-emerald-500 border border-emerald-500/30 hover:bg-emerald-500/20'
              : 'bg-primary text-primary-foreground hover:bg-primary/90'
          }`}
        >
          {isComplete
            ? <><CheckCircle2 className="size-4" /> Completed — tap to undo</>
            : <><Circle className="size-4" /> Mark Session Complete</>
          }
        </button>
      </div>
    </motion.div>
  )
}
