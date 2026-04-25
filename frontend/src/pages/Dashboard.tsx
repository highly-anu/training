import { useMemo, useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { motion, AnimatePresence } from 'framer-motion'
import { Wand2, ChevronRight, Flag } from 'lucide-react'
import { differenceInCalendarDays, differenceInWeeks, parseISO, format } from 'date-fns'
import { useCurrentProgram } from '@/api/programs'
import { TodaySession } from '@/components/dashboard/TodaySession'
import { WeekOverview } from '@/components/dashboard/WeekOverview'
import { DayWorkoutPanel } from '@/components/dashboard/DayWorkoutPanel'
import { ProgramSettingsSheet } from '@/components/dashboard/ProgramSettingsSheet'
import { ModalityDonut } from '@/components/dashboard/ModalityDonut'
import { PhaseTimeline } from '@/components/dashboard/PhaseTimeline'
import { VolumeBar } from '@/components/dashboard/VolumeBar'
import { EmptyState } from '@/components/shared/EmptyState'
import { WeekSelector } from '@/components/program/WeekSelector'
import { ReadinessWidget } from '@/components/bio/ReadinessWidget'
import { DevelopmentWidget } from '@/components/dashboard/DevelopmentWidget'
import { Separator } from '@/components/ui/separator'
import { useUiStore } from '@/store/uiStore'
import { useProfileStore } from '@/store/profileStore'
import { useProgramStore } from '@/store/programStore'
import { usePhaseCalendar } from '@/hooks/usePhaseCalendar'

const DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']

export function Dashboard() {
  const navigate = useNavigate()
  const program = useCurrentProgram()
  const { selectedWeekIndex: weekIndex, setSelectedWeekIndex } = useUiStore()
  const sessionLogs = useProfileStore((s) => s.sessionLogs)
  const eventDate = useProgramStore((s) => s.eventDate)
  const programStartDate = useProgramStore((s) => s.programStartDate)

  // Auto-select the week containing today when the program or start date changes
  useEffect(() => {
    if (!programStartDate || !program) return
    const dayOffset = differenceInCalendarDays(new Date(), parseISO(programStartDate))
    const todayWeekIndex = Math.max(0, Math.min(Math.floor(dayOffset / 7), program.weeks.length - 1))
    setSelectedWeekIndex(todayWeekIndex)
  }, [programStartDate, program?.weeks.length])

  const daysToEvent = eventDate ? differenceInCalendarDays(parseISO(eventDate), new Date()) : null
  const weeksToEvent = eventDate ? differenceInWeeks(parseISO(eventDate), new Date()) : null

  const currentWeek = program?.weeks[weekIndex]
  const { totalWeeks } = usePhaseCalendar(program?.goal, weekIndex + 1)

  const weekComplete = useMemo(() => {
    if (!currentWeek) return false
    return DAYS.every((day) => {
      const sessions = currentWeek.schedule[day] ?? []
      if (sessions.length === 0) return true
      return sessions.every((_, i) => sessionLogs[`${currentWeek.week_number}-${day}`]?.[i] === true)
    })
  }, [currentWeek, sessionLogs])

  const [selectedDay, setSelectedDay] = useState<string | null>(null)

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

  const canAdvance = weekComplete && weekIndex < program.weeks.length - 1

  // Reset selected day when week changes
  // Navigation is bounded by actual generated weeks; totalWeeks may exceed program.weeks.length
  // for multi-phase programs where only some phases have been generated.
  const handleWeekChange = (delta: number) => {
    setSelectedDay(null)
    setSelectedWeekIndex(Math.max(0, Math.min(program.weeks.length - 1, weekIndex + delta)))
  }

  const panelOpen = !!(selectedDay && currentWeek && (currentWeek.schedule[selectedDay] ?? []).length > 0)

  return (
    <motion.div
      key="dashboard"
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0, transition: { duration: 0.25 } }}
      exit={{ opacity: 0, y: -8, transition: { duration: 0.15 } }}
      className="flex h-full overflow-hidden"
    >
      {/* Left scrollable column */}
      <div className="flex-1 min-w-0 overflow-y-auto">
        <div className="p-6 space-y-6 max-w-5xl">
          {/* Header */}
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <p className="text-xs text-muted-foreground">{format(new Date(), 'EEEE, MMMM d, yyyy')}</p>
              <div className="flex items-center gap-2 mt-0.5">
                <h1 className="text-2xl font-bold tracking-tight">{program.goal.name}</h1>
                <ProgramSettingsSheet program={program} />
              </div>
              {daysToEvent !== null && daysToEvent >= 0 && (
                <div className="flex items-center gap-1.5 mt-1">
                  <Flag className="size-3 text-amber-500" />
                  <p className="text-xs font-medium text-amber-500">
                    {weeksToEvent}w {daysToEvent % 7}d until event
                    {eventDate && (
                      <span className="text-muted-foreground font-normal ml-1">
                        · {format(parseISO(eventDate), 'MMM d, yyyy')}
                      </span>
                    )}
                  </p>
                </div>
              )}
              {daysToEvent !== null && daysToEvent < 0 && (
                <p className="text-xs text-muted-foreground mt-1">
                  Event date passed — update in settings
                </p>
              )}
            </div>
            {currentWeek && (
              <WeekSelector
                week={weekIndex + 1}
                totalWeeks={program.weeks.length}
                phase={currentWeek.phase}
                isDeload={currentWeek.is_deload}
                onPrev={() => handleWeekChange(-1)}
                onNext={() => handleWeekChange(1)}
                prevDisabled={weekIndex <= 0}
                nextDisabled={weekIndex >= program.weeks.length - 1}
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
                Week {weekIndex + 1} complete
              </p>
              <button
                type="button"
                onClick={() => handleWeekChange(1)}
                className="flex items-center gap-1 text-xs font-semibold text-emerald-500 hover:text-emerald-400 transition-colors"
              >
                Week {weekIndex + 2} <ChevronRight className="size-3.5" />
              </button>
            </motion.div>
          )}

          {/* Current week overview — full width */}
          <div>
            <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-2">
              Week {weekIndex + 1} Overview
            </h2>
            <div className="rounded-xl border bg-card p-4">
              <WeekOverview
                weekData={currentWeek}
                weekIndex={weekIndex}
                selectedDay={selectedDay}
                onDaySelect={setSelectedDay}
              />
            </div>
          </div>

          {/* Today + Readiness + Development row */}
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 sm:items-stretch">
            <div className="flex flex-col gap-2">
              <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">Today</h2>
              <div className="flex-1 flex flex-col">
                <TodaySession program={program} weekIndex={weekIndex} />
              </div>
            </div>
            <div className="flex flex-col gap-2">
              <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
                Readiness
              </h2>
              <div className="flex-1 flex flex-col">
                <ReadinessWidget />
              </div>
            </div>
            <div className="flex flex-col gap-2">
              <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
                Development
              </h2>
              <div className="flex-1 flex flex-col">
                <DevelopmentWidget />
              </div>
            </div>
          </div>

          {/* Upcoming week preview */}
          {program.weeks[weekIndex + 1] && (
            <div>
              <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-2">
                Next Up — Week {weekIndex + 2}
                {program.weeks[weekIndex + 1].is_deload && (
                  <span className="ml-2 text-amber-500 normal-case font-medium">deload</span>
                )}
              </h2>
              <div className="rounded-xl border bg-card/60 p-4 opacity-80">
                <WeekOverview
                  weekData={program.weeks[weekIndex + 1]}
                  weekIndex={weekIndex + 1}
                  selectedDay={null}
                  onDaySelect={() => {}}
                />
              </div>
            </div>
          )}

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
        </div>
      </div>

      {/* Right panel — animated width */}
      <AnimatePresence>
        {panelOpen && currentWeek && selectedDay && (
          <motion.div
            key={`${currentWeek.week_number}-${selectedDay}`}
            initial={{ width: 0 }}
            animate={{ width: 420 }}
            exit={{ width: 0 }}
            transition={{ duration: 0.25, ease: 'easeInOut' }}
            className="shrink-0 overflow-hidden border-l border-border bg-card"
          >
            <div className="w-[420px] h-full overflow-y-auto">
              <DayWorkoutPanel
                weekData={currentWeek}
                weekIndex={weekIndex}
                day={selectedDay}
                onClose={() => setSelectedDay(null)}
              />
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </motion.div>
  )
}
