import { useScrollRestore } from '@/lib/useScrollRestore'
import { PageHeader } from '@/components/layout/PageHeader'
import { FailedState, LoadingState } from '@/components/shared/states'
import { useMemo, useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { motion, AnimatePresence } from 'framer-motion'
import { nudgeIn, panelMotion } from '@/lib/motion'
import { Page } from '@/components/layout/Page'
import { House, Wand2, ChevronRight, CheckCircle2, Flag } from 'lucide-react'
import { differenceInCalendarDays, differenceInWeeks, parseISO, format } from 'date-fns'
import { cn } from '@/lib/utils'
import { useCurrentProgram } from '@/api/programs'
import { TodaySession } from '@/components/dashboard/TodaySession'
import { TestDayCard } from '@/components/dashboard/TestDayCard'
import { ResultsToConfirmCard } from '@/components/dashboard/ResultsToConfirmCard'
import { WeekOverview } from '@/components/dashboard/WeekOverview'
import { DayWorkoutPanel } from '@/components/dashboard/DayWorkoutPanel'
import { ProgramSettingsSheet } from '@/components/dashboard/ProgramSettingsSheet'
import { EmptyState } from '@/components/shared/EmptyState'
import { WeekSelector } from '@/components/program/WeekSelector'
import { ReadinessWidget } from '@/components/bio/ReadinessWidget'
import { AdherenceWidget } from '@/components/dashboard/AdherenceWidget'
import { SuggestionsCard } from '@/components/dashboard/SuggestionsCard'
import { ProgressWidget } from '@/components/dashboard/ProgressWidget'
import { useUiStore } from '@/store/uiStore'
import { useProfileStore } from '@/store/profileStore'
import { useProgramStore } from '@/store/programStore'
import type { GeneratedProgram } from '@/api/types'
import { COMPLETION } from '@/lib/completionColors'

// Home is the one page that mixes blocks on purpose: today's session, the
// week, readiness, and compact development and progression cards that open
// Analytics. The program's shape (priority mix, phases, volume) lives under
// Program ▸ Overview and the progression review under Analytics ▸ Progress —
// both used to be sub-tabs here.

const DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']

// ── Week ───────────────────────────────────────────────────────────────────────

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
            <Flag className="size-3 text-amber-700 dark:text-amber-300" />
            <p className="text-xs font-medium text-amber-700 dark:text-amber-300">
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

      {/* Week selector, and the week done on the same row */}
      {currentWeek && (
        <div className="flex flex-wrap items-center justify-between gap-3">
          <WeekSelector
            week={weekIndex + 1}
            totalWeeks={program.weeks.length}
            phase={currentWeek.phase}
            phaseLabel={currentWeek.phase_name}
            isDeload={currentWeek.is_deload}
            onPrev={() => handleWeekChange(-1)}
            onNext={() => handleWeekChange(1)}
            prevDisabled={weekIndex <= 0}
            nextDisabled={weekIndex >= program.weeks.length - 1}
          />
          {canAdvance && (
            <motion.button
              type="button"
              {...nudgeIn}
              onClick={() => handleWeekChange(1)}
              aria-label={`Week ${weekIndex + 1} done — go to week ${weekIndex + 2}`}
              className={cn('ml-auto flex items-center gap-1.5 rounded-full border px-3 py-1 text-xs font-medium transition-opacity hover:opacity-80',
                            COMPLETION.border, COMPLETION.bgStrong, COMPLETION.text)}
            >
              <CheckCircle2 className="size-3.5" />
              Week done
              <span className="opacity-70">· Next</span>
              <ChevronRight className="size-3.5" />
            </motion.button>
          )}
        </div>
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

      {/* Workouts waiting for a match decision — only when there are any */}
      <SuggestionsCard />

      {/* Results logged sessions suggest — today's test shows its own below */}
      <ResultsToConfirmCard
        testDayKey={program.weeks[weekIndex] ? `${program.weeks[weekIndex].week_number}-${format(new Date(), 'EEEE')}` : undefined}
        testStandards={(program.weeks[weekIndex]?.schedule[format(new Date(), 'EEEE')] ?? [])
          .flatMap((s) => s.test?.standards ?? [])} />

      {/* Today + Readiness + Adherence + Progress */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4 sm:items-stretch">
        <div className="flex flex-col gap-2">
          <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">Today</h2>
          <div className="flex-1 flex flex-col">
            <TodaySession program={program} weekIndex={weekIndex} />
            <TestDayCard program={program} weekIndex={weekIndex} />
          </div>
        </div>
        <div className="flex flex-col gap-2">
          <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">Readiness</h2>
          <div className="flex-1 flex flex-col">
            <ReadinessWidget />
          </div>
        </div>
        <div className="flex flex-col gap-2">
          <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">Adherence</h2>
          <div className="flex-1 flex flex-col">
            <AdherenceWidget />
          </div>
        </div>
        <div className="flex flex-col gap-2">
          <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">Progress</h2>
          <div className="flex-1 flex flex-col">
            <ProgressWidget />
          </div>
        </div>
      </div>

      {/* Next week preview */}
      {program.weeks[weekIndex + 1] && (
        <div>
          <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-2">
            Next Up — Week {weekIndex + 2}
            {program.weeks[weekIndex + 1].is_deload && (
              <span className="ml-2 text-amber-700 dark:text-amber-300 normal-case font-medium">deload</span>
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

// ── Main Page ──────────────────────────────────────────────────────────────────

export function Dashboard() {
  const scroller = useScrollRestore()
  const navigate = useNavigate()
  const program = useCurrentProgram()
  const programLoadState = useProgramStore((s) => s.programLoadState)
  const loadProgram = useProgramStore((s) => s.loadFromServer)
  const { selectedWeekIndex: weekIndex, setSelectedWeekIndex } = useUiStore()
  const sessionLogs = useProfileStore((s) => s.sessionLogs)
  const eventDate = useProgramStore((s) => s.eventDate)
  const programStartDate = useProgramStore((s) => s.programStartDate)

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

  const weekComplete = useMemo(() => {
    if (!currentWeek) return false
    return DAYS.every((day) => {
      const sessions = currentWeek.schedule[day] ?? []
      const logged = (i: number) => sessionLogs[`${currentWeek.week_number}-${day}`]?.[i] === true
      // An extra the athlete added counts once done, never as one still to do.
      return sessions.every((sess, i) => sess.added || logged(i))
    })
  }, [currentWeek, sessionLogs])

  // A failed load is not an empty program. Offering "build your first
  // program" here would invite overwriting a program that is still on the
  // server but could not be fetched.
  if (programLoadState === 'error' && !program) {
    return (
      <div className="flex h-full items-center justify-center p-6">
        <FailedState
          title="Could not load your program"
          error="The server could not be reached. Your program is safe — try again in a moment."
          onRetry={() => { void loadProgram() }}
          className="max-w-md"
        />
      </div>
    )
  }

  // Only show the loader when there is nothing to show yet. A background
  // refetch keeps the current program on screen instead of blanking it.
  if (programLoadState !== 'loaded' && !program) {
    return (
      <Page
        enter="fade"
        key="dashboard-loading"
        className="h-full p-6"
      >
        <LoadingState shape="cards" count={3} label="Loading your program" className="mx-auto max-w-3xl" />
      </Page>
    )
  }

  if (!program) {
    return (
      <Page
        key="dashboard-empty"
        className="flex h-full items-center justify-center p-6"
      >
        <EmptyState
          title="No program yet"
          description="Build your first training program to see your dashboard and today's session."
          action={{ label: 'Build a Program', onClick: () => navigate('/program/new') }}
          icon={<Wand2 className="size-10" />}
          className="max-w-md"
        />
      </Page>
    )
  }

  const canAdvance = weekComplete && weekIndex < program.weeks.length - 1

  const handleWeekChange = (delta: number) => {
    setSelectedDay(null)
    setSelectedWeekIndex(Math.max(0, Math.min(program.weeks.length - 1, weekIndex + delta)))
  }

  const panelOpen = !!(selectedDay && currentWeek && (currentWeek.schedule[selectedDay] ?? []).length > 0)

  return (
    <Page
      key="dashboard"
      className="flex h-full flex-col overflow-hidden"
    >
      <PageHeader icon={House} title="Today" actions={<ProgramSettingsSheet program={program} />} />

      {/* Content + optional right panel */}
      <div className="flex flex-1 overflow-hidden">

        {/* Scrollable main column */}
        <div ref={scroller} className="flex-1 min-w-0 overflow-y-auto">
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
        </div>

        {/* Right panel — animated width */}
        <AnimatePresence>
          {panelOpen && currentWeek && selectedDay && (
            <motion.div
              key={`${currentWeek.week_number}-${selectedDay}`}
              {...panelMotion(420)}
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
    </Page>
  )
}
