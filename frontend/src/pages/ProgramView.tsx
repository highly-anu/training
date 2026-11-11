import { useScrollRestore } from '@/lib/useScrollRestore'
import { PageHeader } from '@/components/layout/PageHeader'
import { SubTabs, tabDomId } from '@/components/layout/SubTabs'
import { Button } from '@/components/ui/button'
import { LoadingState, FailedState } from '@/components/shared/states'
import { useState, useEffect, useRef, useMemo } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { Page } from '@/components/layout/Page'
import { differenceInCalendarDays, format, parseISO } from 'date-fns'
import { CalendarDays, Wand2, ShieldAlert, Plus } from 'lucide-react'
import { useCurrentProgram } from '@/api/programs'
import { useRegeneratePreview } from '@/hooks/useRegeneratePreview'
import { WeekCalendar } from '@/components/program/WeekCalendar'
import { WeekSelector } from '@/components/program/WeekSelector'
import { PhaseBar } from '@/components/program/PhaseBar'
import { ProgramOverview } from '@/components/program/ProgramOverview'
import { ProgramHistoryList } from '@/components/program/ProgramHistoryList'
import { EmptyState } from '@/components/shared/EmptyState'
import { PhaseBadge } from '@/components/shared/PhaseBadge'
import { InjuryPicker } from '@/components/builder/InjuryPicker'
import { Sheet, SheetContent, SheetHeader, SheetTitle } from '@/components/ui/sheet'
import { Badge } from '@/components/ui/badge'
import { Separator } from '@/components/ui/separator'
import { usePhaseCalendar } from '@/hooks/usePhaseCalendar'
import { useProfileStore } from '@/store/profileStore'
import { useProgramStore } from '@/store/programStore'
import { usePhilosophies } from '@/api/philosophies'
import { cn } from '@/lib/utils'
import type { CustomInjuryFlag, InjuryFlagId, TrainingPhase } from '@/api/types'
import { regenerateSource, tailResume } from '@/lib/programSource'
import { sessionCalendarDate } from '@/lib/workoutMatcher'
import { ReplaceSessionSheet } from '@/components/session/ReplaceSessionSheet'

type ProgramTab = 'overview' | 'calendar' | 'history'
// Overview leads since 2026-10-17, the same order as the phone's (information-architecture.md §2).
const PROGRAM_TABS: ProgramTab[] = ['overview', 'calendar', 'history']
const PROGRAM_TAB_ITEMS = [
  { id: 'overview', label: 'Overview' },
  { id: 'calendar', label: 'Calendar' },
  { id: 'history', label: 'History' },
] as const satisfies readonly { id: ProgramTab; label: string }[]

export function ProgramView() {
  const scroller = useScrollRestore()
  const navigate = useNavigate()
  const program = useCurrentProgram()
  const [weekIndex, setWeekIndex] = useState(0)
  // URL-driven so History can be linked to directly (it was its own page).
  const [searchParams, setSearchParams] = useSearchParams()
  const tabParam = searchParams.get('tab')
  const activeTab: ProgramTab = PROGRAM_TABS.includes(tabParam as ProgramTab) ? (tabParam as ProgramTab) : 'overview'
  function setActiveTab(tab: ProgramTab) {
    setSearchParams(
      (prev) => {
        const next = new URLSearchParams(prev)
        if (tab === 'overview') next.delete('tab')
        else next.set('tab', tab)
        return next
      },
      { replace: true }
    )
  }
  const [injurySheetOpen, setInjurySheetOpen] = useState(false)
  const [localFlags, setLocalFlags] = useState<InjuryFlagId[]>([])
  const [localCustom, setLocalCustom] = useState<CustomInjuryFlag[]>([])

  const weekRefs = useRef<(HTMLDivElement | null)[]>([])

  const {
    customInjuryFlags,
    addCustomInjuryFlag, removeCustomInjuryFlag,
  } = useProfileStore()

  const programStartDate = useProgramStore((s) => s.programStartDate)
  const programLoadState = useProgramStore((s) => s.programLoadState)
  const loadProgram = useProgramStore((s) => s.loadFromServer)
  const sourceGoalIds = useProgramStore((s) => s.sourceGoalIds)
  const { data: philosophies } = usePhilosophies()

  // The title is the STORED program's methodology. It used to read the
  // builder's persisted selection, so browsing a philosophy in the builder
  // (or landing there from Explore) renamed the program the athlete is on.
  const programTitle = (() => {
    const ids = sourceGoalIds.filter((id) => id !== '_blended')
    const names = philosophies?.filter((p) => ids.includes(p.id)).map((p) => p.name) ?? []
    if (names.length > 0) return names.join(' + ')
    return program?.goal?.name ?? 'Training Program'
  })()
  const currentWeekData = program?.weeks[weekIndex]
  const { segments, totalWeeks } = usePhaseCalendar(program ?? undefined, weekIndex + 1)
  const regenerate = useRegeneratePreview()
  // A session added on the fly: today or a later day (a past day would switch
  // the program's version; src/program_history.carry_over_until).
  const [addTarget, setAddTarget] = useState<{ weekIndex: number; day: string } | null>(null)
  const todayIso = format(new Date(), 'yyyy-MM-dd')
  const canAddOn = (weekIdx: number, day: string) =>
    !!programStartDate && sessionCalendarDate(programStartDate, weekIdx, day) >= todayIso

  // Which array index is the real current calendar week?
  const currentCalendarWeekIdx = useMemo(() => {
    if (!programStartDate) return -1
    const days = differenceInCalendarDays(new Date(), parseISO(programStartDate))
    return Math.floor(days / 7)
  }, [programStartDate])

  // Scroll to active week when weekIndex changes (only on calendar tab)
  useEffect(() => {
    if (activeTab !== 'calendar') return
    weekRefs.current[weekIndex]?.scrollIntoView({ behavior: 'smooth', block: 'start' })
  }, [weekIndex, activeTab])

  // Seed the draft when the sheet opens, during render rather than in an
  // effect — an effect would render the sheet once with the previous session's
  // selections before correcting them.
  const [prevInjurySheetOpen, setPrevInjurySheetOpen] = useState(injurySheetOpen)
  if (injurySheetOpen !== prevInjurySheetOpen) {
    setPrevInjurySheetOpen(injurySheetOpen)
    if (injurySheetOpen && program) {
      setLocalFlags([...(program.constraints?.injury_flags ?? [])] as InjuryFlagId[])
      setLocalCustom([...customInjuryFlags])
    }
  }

  const activeInjuryCount =
    (program?.constraints?.injury_flags?.length ?? 0) + customInjuryFlags.length

  function handleRegenerate() {
    if (!program || !currentWeekData) return
    const { sourceGoalIds: storedIds, sourceGoalWeights } = useProgramStore.getState()
    const resume = tailResume(program, weekIndex)
    // Shown in Program ▸ Preview first; saved only on its Apply.
    regenerate.open(
      {
        ...regenerateSource(storedIds, sourceGoalWeights, program),
        trackId: resume.trackId,
        ...(resume.lanes ? { lanes: resume.lanes } : {}),
        startPhaseId: resume.startPhaseId,
        constraints: {
          ...resume.constraints,
          injury_flags: localFlags,
        },
        // The stored program's length, never the methodology's canonical
        // plan: sizing from the latter asked for 18 weeks on a 4-week plan.
        numWeeks: program.weeks.length - weekIndex,
        weekInProgram: weekIndex + 1,
        customInjuryFlags: localCustom,
        // Never the days already behind the athlete.
        keepBefore: format(new Date(), 'yyyy-MM-dd'),
      },
      weekIndex,
    )
  }

  // No program on screen yet is one of three things, and only the last is
  // "build one": still loading, could not be loaded (it may well exist), none.
  if (!program && programLoadState === 'error') {
    return (
      <Page key="program-failed" className="flex h-full items-center justify-center p-6">
        <FailedState
          title="Could not load your program"
          error="The server could not be reached. Your program is safe — try again in a moment."
          onRetry={() => { void loadProgram() }}
          className="max-w-md"
        />
      </Page>
    )
  }
  if (!program && programLoadState !== 'loaded') {
    return (
      <Page enter="fade" key="program-loading" className="h-full p-6">
        <LoadingState shape="cards" count={3} label="Loading your program" className="mx-auto max-w-3xl" />
      </Page>
    )
  }

  if (!program) {
    return (
      <Page
        key="program-empty"
        className="flex h-full items-center justify-center p-6"
      >
        <EmptyState
          title="No program generated yet"
          description="Use the builder to pick a philosophy and generate a personalized program."
          action={{ label: 'Build a Program', onClick: () => navigate('/program/new') }}
          icon={<Wand2 className="size-10" />}
        />
      </Page>
    )
  }

  return (
    <Page
      key="program"
      className="flex h-full flex-col"
    >
      <PageHeader
        icon={CalendarDays}
        title={programTitle}
        tabs={<SubTabs id="program-tabs" label="Program sections" tabs={PROGRAM_TAB_ITEMS} active={activeTab} onChange={setActiveTab} />}
        actions={
          <>
            <button
              type="button"
              onClick={() => navigate('/program/new')}
              className="flex items-center gap-1.5 rounded-md border px-2.5 py-1.5 text-xs text-muted-foreground hover:border-primary/40 hover:text-foreground transition-colors"
            >
              <Plus className="size-3.5" aria-hidden="true" />
              New program
            </button>
            <button
              type="button"
              onClick={() => setInjurySheetOpen(true)}
              className="flex items-center gap-1.5 rounded-md border px-2.5 py-1.5 text-xs text-muted-foreground hover:border-primary/40 hover:text-foreground transition-colors"
            >
              <ShieldAlert className="size-3.5" />
              Injuries
              {activeInjuryCount > 0 && (
                <Badge variant="secondary" className="ml-0.5 h-4 px-1 text-[10px]">
                  {activeInjuryCount}
                </Badge>
              )}
            </button>
            {activeTab === 'calendar' && currentWeekData && (
              <WeekSelector
                week={currentWeekData.week_number}
                totalWeeks={totalWeeks}
                phase={currentWeekData.phase}
                phaseLabel={currentWeekData.phase_name}
                isDeload={currentWeekData.is_deload}
                onPrev={() => setWeekIndex((i) => Math.max(0, i - 1))}
                onNext={() => setWeekIndex((i) => Math.min(program.weeks.length - 1, i + 1))}
              />
            )}
          </>
        }
      >
        {activeTab !== 'history' && (
          <PhaseBar segments={segments} totalWeeks={totalWeeks} currentWeek={weekIndex + 1} />
        )}
      </PageHeader>

      {/* Body. Not <TabPanels>: the calendar scrolls to its week as it mounts. */}
      <div ref={scroller} className="flex-1 overflow-y-auto" role="tabpanel" aria-labelledby={tabDomId('program-tabs', activeTab)}>
        {activeTab === 'calendar' ? (
          <div className="max-w-5xl mx-auto px-6 py-6 space-y-8">
            {program.weeks.map((weekData, idx) => (
              <div
                key={weekData.week_number}
                ref={(el) => { weekRefs.current[idx] = el }}
                className={cn(
                  'space-y-3 rounded-xl p-3 -mx-3 transition-colors duration-(--motion-slow)',
                  idx === weekIndex ? 'bg-primary/5 ring-1 ring-primary/20' : ''
                )}
              >
                <div className="flex items-center gap-2 px-1">
                  <span className="text-sm font-semibold text-foreground">
                    Week {weekData.week_number}
                  </span>
                  <PhaseBadge phase={weekData.phase as TrainingPhase} label={weekData.phase_name} />
                  {weekData.is_deload && (
                    <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-slate-500/15 text-slate-700 dark:text-slate-300 border border-slate-500/30">
                      Deload
                    </span>
                  )}
                </div>
                <WeekCalendar weekData={weekData} isCurrentWeek={idx === currentCalendarWeekIdx}
                  canAdd={(day) => canAddOn(idx, day)}
                  onAddSession={(day) => setAddTarget({ weekIndex: idx, day })} />
              </div>
            ))}
          </div>
        ) : activeTab === 'overview' ? (
          <ProgramOverview program={program} segments={segments} />
        ) : (
          <ProgramHistoryList />
        )}
      </div>

      {/* Manage Injuries Sheet */}
      <Sheet open={injurySheetOpen} onOpenChange={(v) => !v && setInjurySheetOpen(false)}>
        <SheetContent className="w-full sm:max-w-md overflow-y-auto">
          <SheetHeader>
            <SheetTitle>Manage Injuries</SheetTitle>
            <p className="text-xs text-muted-foreground">
              Adjust your injuries and regenerate the program from Week {weekIndex + 1}.
              Weeks before the current week are preserved.
            </p>
          </SheetHeader>

          <div className="mt-4 space-y-4">
            <InjuryPicker
              selected={localFlags}
              onChange={setLocalFlags}
              customInjuries={localCustom}
              onCustomInjuriesChange={(injuries: CustomInjuryFlag[]) => {
                // Sync to profileStore
                const added = injuries.find((i) => !localCustom.some((c) => c.id === i.id))
                const removed = localCustom.find((c) => !injuries.some((i) => i.id === c.id))
                if (added) addCustomInjuryFlag(added)
                if (removed) removeCustomInjuryFlag(removed.id)
                setLocalCustom(injuries)
              }}
            />

            <Separator />

            <Button className="h-9 w-full" onClick={handleRegenerate} loading={regenerate.isPending}>
              Preview from week {weekIndex + 1}
            </Button>
            {regenerate.error && (
              <p className="text-xs text-red-700 dark:text-red-300">
                {regenerate.error.message || 'Could not regenerate'}
              </p>
            )}
          </div>
        </SheetContent>
      </Sheet>
      {addTarget && program.weeks[addTarget.weekIndex] && (
        <ReplaceSessionSheet open mode="add" onOpenChange={(o) => !o && setAddTarget(null)}
          weekIndex={addTarget.weekIndex} weekData={program.weeks[addTarget.weekIndex]}
          day={addTarget.day} program={program} />
      )}
    </Page>
  )
}
