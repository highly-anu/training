import { useMemo, useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { motion, AnimatePresence } from 'framer-motion'
import { LayoutDashboard, Wand2, ChevronRight, Flag } from 'lucide-react'
import { differenceInCalendarDays, differenceInWeeks, parseISO, format } from 'date-fns'
import { cn } from '@/lib/utils'
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
import { ProgressionTab } from '@/components/progression/ProgressionTab'
import { useUiStore } from '@/store/uiStore'
import { useProfileStore } from '@/store/profileStore'
import { useProgramStore } from '@/store/programStore'
import { usePhaseCalendar } from '@/hooks/usePhaseCalendar'
import type { GeneratedProgram } from '@/api/types'

// ── Types ──────────────────────────────────────────────────────────────────────

type SubTab = 'week' | 'analytics' | 'progress'

const SUB_TABS: { id: SubTab; label: string }[] = [
  { id: 'week',      label: 'Week'      },
  { id: 'analytics', label: 'Analytics' },
  { id: 'progress',  label: 'Progress'  },
]

const DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']

// ── Tab Selector ───────────────────────────────────────────────────────────────

function TabSelector({
  active,
  onChange,
}: {
  active: SubTab
  onChange: (t: SubTab) => void
}) {
  return (
    <div className="flex items-center gap-1">
      {SUB_TABS.map((tab) => (
        <button
          key={tab.id}
          type="button"
          onClick={() => onChange(tab.id)}
          className={cn(
            'px-3 py-1 text-xs rounded border transition-colors',
            tab.id === active
              ? 'bg-primary/15 border-primary/40 text-primary'
              : 'border-border text-muted-foreground hover:bg-muted'
          )}
        >
          {tab.label}
        </button>
      ))}
    </div>
  )
}

// ── Week Tab ───────────────────────────────────────────────────────────────────

function WeekTab({
  program,
  weekIndex,
  selectedDay,
  setSelectedDay,
  handleWeekChange,
  canAdvance,
  daysToEvent,
  weeksToEvent,
  eventDate,
}: {
  program: GeneratedProgram
  weekIndex: number
  selectedDay: string | null
  setSelectedDay: (d: string | null) => void
  handleWeekChange: (delta: number) => void
  canAdvance: boolean
  daysToEvent: number | null
  weeksToEvent: number | null
  eventDate: string | null
}) {
  const currentWeek = program.weeks[weekIndex]

  return (
    <div className="max-w-5xl mx-auto px-6 py-6 space-y-6">

      {/* Date + goal name */}
      <div>
        <p className="text-xs text-muted-foreground">{format(new Date(), 'EEEE, MMMM d, yyyy')}</p>
        <h1 className="text-2xl font-bold tracking-tight mt-0.5">{program.goal?.name ?? 'Training Program'}</h1>
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

      {/* Week selector */}
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

      {/* Current week overview */}
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

      {/* Today + Readiness + Development */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 sm:items-stretch">
        <div className="flex flex-col gap-2">
          <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">Today</h2>
          <div className="flex-1 flex flex-col">
            <TodaySession program={program} weekIndex={weekIndex} />
          </div>
        </div>
        <div className="flex flex-col gap-2">
          <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">Readiness</h2>
          <div className="flex-1 flex flex-col">
            <ReadinessWidget />
          </div>
        </div>
        <div className="flex flex-col gap-2">
          <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">Development</h2>
          <div className="flex-1 flex flex-col">
            <DevelopmentWidget />
          </div>
        </div>
      </div>

      {/* Next week preview */}
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

    </div>
  )
}

// ── Analytics Tab ──────────────────────────────────────────────────────────────

function AnalyticsTab({
  program,
  weekIndex,
}: {
  program: GeneratedProgram
  weekIndex: number
}) {
  return (
    <div className="max-w-5xl mx-auto px-6 py-6 space-y-6">

      <div className="grid grid-cols-1 gap-6 md:grid-cols-2">
        <div>
          <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3">
            Goal Priority Mix
          </h2>
          <div className="rounded-xl border bg-card p-4">
            <ModalityDonut priorities={program.goal?.priorities ?? {}} />
          </div>
        </div>

        <div>
          <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3">
            Phase Timeline
          </h2>
          <div className="rounded-xl border bg-card p-4">
            <PhaseTimeline goal={program.goal} currentWeek={weekIndex + 1} />
          </div>
        </div>
      </div>

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
  )
}

// ── Main Page ──────────────────────────────────────────────────────────────────

export function Dashboard() {
  const navigate = useNavigate()
  const program = useCurrentProgram()
  const { selectedWeekIndex: weekIndex, setSelectedWeekIndex } = useUiStore()
  const sessionLogs = useProfileStore((s) => s.sessionLogs)
  const eventDate = useProgramStore((s) => s.eventDate)
  const programStartDate = useProgramStore((s) => s.programStartDate)

  const [activeTab, setActiveTab] = useState<SubTab>('week')
  const [selectedDay, setSelectedDay] = useState<string | null>(null)

  useEffect(() => {
    if (!programStartDate || !program) return
    const dayOffset = differenceInCalendarDays(new Date(), parseISO(programStartDate))
    const todayWeekIndex = Math.max(0, Math.min(Math.floor(dayOffset / 7), program.weeks.length - 1))
    setSelectedWeekIndex(todayWeekIndex)
  }, [programStartDate, program?.weeks.length])

  const daysToEvent = eventDate ? differenceInCalendarDays(parseISO(eventDate), new Date()) : null
  const weeksToEvent = eventDate ? differenceInWeeks(parseISO(eventDate), new Date()) : null

  const currentWeek = program?.weeks[weekIndex]
  const { totalWeeks: _totalWeeks } = usePhaseCalendar(program?.goal, weekIndex + 1)

  const weekComplete = useMemo(() => {
    if (!currentWeek) return false
    return DAYS.every((day) => {
      const sessions = currentWeek.schedule[day] ?? []
      if (sessions.length === 0) return true
      return sessions.every((_, i) => sessionLogs[`${currentWeek.week_number}-${day}`]?.[i] === true)
    })
  }, [currentWeek, sessionLogs])

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
      className="flex h-full flex-col overflow-hidden"
    >
      {/* Header */}
      <div className="flex items-center gap-2 border-b px-6 py-4 shrink-0">
        <LayoutDashboard className="size-5 text-primary" />
        <h1 className="text-lg font-semibold">Dashboard</h1>
        <div className="ml-4 flex items-center gap-2">
          <div className="w-px h-4 bg-border/60 shrink-0" />
          <TabSelector active={activeTab} onChange={setActiveTab} />
        </div>
        <div className="ml-auto">
          <ProgramSettingsSheet program={program} />
        </div>
      </div>

      {/* Content + optional right panel */}
      <div className="flex flex-1 overflow-hidden">

        {/* Scrollable main column */}
        <div className="flex-1 min-w-0 overflow-y-auto">
          {activeTab === 'week' && (
            <WeekTab
              program={program}
              weekIndex={weekIndex}
              selectedDay={selectedDay}
              setSelectedDay={setSelectedDay}
              handleWeekChange={handleWeekChange}
              canAdvance={canAdvance}
              daysToEvent={daysToEvent}
              weeksToEvent={weeksToEvent}
              eventDate={eventDate}
            />
          )}
          {activeTab === 'analytics' && (
            <AnalyticsTab
              program={program}
              weekIndex={weekIndex}
            />
          )}
          {activeTab === 'progress' && (
            <div className="space-y-4">
              <ProgressionTab />
            </div>
          )}
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

      </div>
    </motion.div>
  )
}
