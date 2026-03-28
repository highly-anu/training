import { useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import { motion } from 'framer-motion'
import { Wand2, ChevronRight } from 'lucide-react'
import { useCurrentProgram } from '@/api/programs'
import { TodaySession } from '@/components/dashboard/TodaySession'
import { WeekOverview } from '@/components/dashboard/WeekOverview'
import { ModalityDonut } from '@/components/dashboard/ModalityDonut'
import { PhaseTimeline } from '@/components/dashboard/PhaseTimeline'
import { VolumeBar } from '@/components/dashboard/VolumeBar'
import { EmptyState } from '@/components/shared/EmptyState'
import { WeekSelector } from '@/components/program/WeekSelector'
import { Separator } from '@/components/ui/separator'
import { useUiStore } from '@/store/uiStore'
import { useProfileStore } from '@/store/profileStore'
import { format } from 'date-fns'

const DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']

export function Dashboard() {
  const navigate = useNavigate()
  const program = useCurrentProgram()
  const { selectedWeekIndex: weekIndex, setSelectedWeekIndex } = useUiStore()
  const sessionLogs = useProfileStore((s) => s.sessionLogs)

  if (!program) {
    return (
      <motion.div
        key="dashboard-empty"
        initial={{ opacity: 0, y: 16 }}
        animate={{ opacity: 1, y: 0, transition: { duration: 0.25 } }}
        exit={{ opacity: 0, y: -8, transition: { duration: 0.15 } }}
        className="flex h-full items-center justify-center p-6"
      >
        <EmptyState
          title="No program yet"
          description="Build your first training program to see your dashboard and today's session."
          action={{ label: 'Build a Program', onClick: () => navigate('/builder') }}
          icon={<Wand2 className="size-10" />}
          className="max-w-md"
        />
      </motion.div>
    )
  }

  const currentWeek = program.weeks[weekIndex]

  const weekComplete = useMemo(() => {
    if (!currentWeek) return false
    return DAYS.every((day) => {
      const sessions = currentWeek.schedule[day] ?? []
      if (sessions.length === 0) return true
      return sessionLogs[`${currentWeek.week_number}-${day}`]?.[0] === true
    })
  }, [currentWeek, sessionLogs])

  const canAdvance = weekComplete && weekIndex < program.weeks.length - 1

  return (
    <motion.div
      key="dashboard"
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0, transition: { duration: 0.25 } }}
      exit={{ opacity: 0, y: -8, transition: { duration: 0.15 } }}
      className="p-6 space-y-6 max-w-5xl"
    >
      {/* Header */}
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="text-xs text-muted-foreground">{format(new Date(), 'EEEE, MMMM d, yyyy')}</p>
          <h1 className="text-2xl font-bold tracking-tight mt-0.5">{program.goal.name}</h1>
        </div>
        {currentWeek && (
          <WeekSelector
            week={currentWeek.week_number}
            totalWeeks={program.weeks.length}
            phase={currentWeek.phase}
            isDeload={currentWeek.is_deload}
            onPrev={() => setSelectedWeekIndex(Math.max(0, weekIndex - 1))}
            onNext={() => setSelectedWeekIndex(Math.min(program.weeks.length - 1, weekIndex + 1))}
          />
        )}
      </div>

      {/* Week complete banner */}
      {canAdvance && (
        <motion.div
          initial={{ opacity: 0, y: -8 }}
          animate={{ opacity: 1, y: 0 }}
          className="flex items-center justify-between gap-3 rounded-xl border border-emerald-500/30 bg-emerald-500/10 px-4 py-3"
        >
          <p className="text-sm font-medium text-emerald-500">
            Week {currentWeek?.week_number} complete
          </p>
          <button
            type="button"
            onClick={() => setSelectedWeekIndex(weekIndex + 1)}
            className="flex items-center gap-1 text-xs font-semibold text-emerald-500 hover:text-emerald-400 transition-colors"
          >
            Week {weekIndex + 2} <ChevronRight className="size-3.5" />
          </button>
        </motion.div>
      )}

      {/* Top row */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {/* Today's session */}
        <div className="lg:col-span-1">
          <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-2">Today</h2>
          <TodaySession program={program} weekIndex={weekIndex} />
        </div>

        {/* Week overview */}
        <div className="sm:col-span-1 lg:col-span-2">
          <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-2">
            Week {currentWeek?.week_number} Overview
          </h2>
          <div className="rounded-xl border bg-card p-4">
            <WeekOverview weekData={currentWeek} />
          </div>
        </div>
      </div>

      <Separator />

      {/* Middle row */}
      <div className="grid grid-cols-1 gap-6 md:grid-cols-2">
        {/* Modality donut */}
        <div>
          <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3">
            Goal Priority Mix
          </h2>
          <div className="rounded-xl border bg-card p-4">
            <ModalityDonut priorities={program.goal.priorities} />
          </div>
        </div>

        {/* Phase timeline */}
        <div>
          <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3">
            Phase Timeline
          </h2>
          <div className="rounded-xl border bg-card p-4">
            <PhaseTimeline goal={program.goal} currentWeek={weekIndex + 1} />
          </div>
        </div>
      </div>

      {/* Volume chart */}
      {program.volume_summary && program.volume_summary.length > 0 && (
        <div>
          <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3">
            Weekly Volume (min)
          </h2>
          <div className="rounded-xl border bg-card p-4">
            <VolumeBar summaries={program.volume_summary} />
          </div>
        </div>
      )}
    </motion.div>
  )
}
