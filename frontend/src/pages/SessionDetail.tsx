import { useState } from 'react'
import { useParams, useNavigate, Link } from 'react-router-dom'
import { motion } from 'framer-motion'
import { ChevronLeft, Wand2, CheckCircle2, Circle, RefreshCw } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Separator } from '@/components/ui/separator'
import { SessionHeader } from '@/components/session/SessionHeader'
import { ReplaceSessionSheet } from '@/components/session/ReplaceSessionSheet'
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
  const getPerformanceLog = useBioStore((s) => s.getPerformanceLog)
  const upsertSessionPerformance = useBioStore((s) => s.upsertSessionPerformance)
  const [replaceTarget, setReplaceTarget] = useState<{ idx: number } | null>(null)

  const weekNumber = parseInt(week ?? '1', 10)
  const weekIdx = program.weeks.findIndex((w) => w.week_number === weekNumber)
  const weekData = weekIdx >= 0 ? program.weeks[weekIdx] : undefined
  const sessions = weekData?.schedule[day ?? ''] ?? []

  const sessionKey = `${weekNumber}-${day ?? ''}`
  function toggleComplete(si: number) {
    const current = sessionLogs[sessionKey] ?? []
    const next = [...current]
    next[si] = !next[si]
    setSessionLog(sessionKey, next)
    if (next[si]) {
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
        {sessions.map((session, sessionIdx) => {
          const isComplete = sessionLogs[sessionKey]?.[sessionIdx] === true
            || !!getPerformanceLog(sessionKey)?.completedAt
            || !!getPerformanceLog(`${sessionKey}-${sessionIdx}`)?.completedAt
          return (
            <div key={sessionIdx} className="space-y-4">
              {sessionIdx > 0 && <Separator />}

              <div className="flex items-start justify-between gap-2">
                <div className="flex-1 min-w-0">
                  <SessionHeader
                    session={session}
                    day={day ?? ''}
                    weekNumber={weekNumber}
                    weekInPhase={weekData.week_in_phase}
                    phase={weekData.phase}
                  />
                </div>
                <Button
                  variant="outline"
                  size="sm"
                  className="shrink-0 mt-1"
                  onClick={() => setReplaceTarget({ idx: sessionIdx })}
                >
                  <RefreshCw className="size-3.5 mr-1.5" />
                  Replace
                </Button>
              </div>

              <div className="space-y-2">
                {session.exercises.map((assignment, i) => (
                  <ExerciseRow key={i} assignment={assignment} index={i} sessionKey={sessionKey} sessionIdx={sessionIdx} />
                ))}
              </div>

              <button
                type="button"
                onClick={() => toggleComplete(sessionIdx)}
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
          )
        })}

        {/* Workout summary (HR data if imported workout is matched) */}
        <WorkoutSummaryCard sessionKey={sessionKey} sessions={sessions} weekIndex={weekIdx >= 0 ? weekIdx : undefined} />

        {/* Session notes + fatigue rating */}
        <SessionNotes sessionKey={sessionKey} />
      </div>

      {weekData && replaceTarget && (
        <ReplaceSessionSheet
          open={true}
          onOpenChange={(open) => { if (!open) setReplaceTarget(null) }}
          session={sessions[replaceTarget.idx]}
          weekIndex={weekIdx >= 0 ? weekIdx : 0}
          weekData={weekData}
          day={day ?? ''}
          sessionIndex={replaceTarget.idx}
          program={program}
        />
      )}
    </motion.div>
  )
}
