import { useState, useEffect, useRef } from 'react'
import { useNavigate } from 'react-router-dom'
import { motion } from 'framer-motion'
import { Wand2, ShieldAlert } from 'lucide-react'
import { useCurrentProgram, useRegenerateFromWeek } from '@/api/programs'
import { WeekCalendar } from '@/components/program/WeekCalendar'
import { WeekSelector } from '@/components/program/WeekSelector'
import { PhaseBar } from '@/components/program/PhaseBar'
import { ProgramOverview } from '@/components/program/ProgramOverview'
import { EmptyState } from '@/components/shared/EmptyState'
import { PhaseBadge } from '@/components/shared/PhaseBadge'
import { InjuryPicker } from '@/components/builder/InjuryPicker'
import { Sheet, SheetContent, SheetHeader, SheetTitle } from '@/components/ui/sheet'
import { Badge } from '@/components/ui/badge'
import { Separator } from '@/components/ui/separator'
import { usePhaseCalendar } from '@/hooks/usePhaseCalendar'
import { useProfileStore } from '@/store/profileStore'
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { cn } from '@/lib/utils'
import type { CustomInjuryFlag, InjuryFlagId, TrainingPhase } from '@/api/types'

export function ProgramView() {
  const navigate = useNavigate()
  const program = useCurrentProgram()
  const [weekIndex, setWeekIndex] = useState(0)
  const [activeTab, setActiveTab] = useState<'calendar' | 'overview'>('overview')
  const [injurySheetOpen, setInjurySheetOpen] = useState(false)
  const [localFlags, setLocalFlags] = useState<InjuryFlagId[]>([])
  const [localCustom, setLocalCustom] = useState<CustomInjuryFlag[]>([])

  const weekRefs = useRef<(HTMLDivElement | null)[]>([])

  const {
    customInjuryFlags, injuryFlags: profileFlags,
    addCustomInjuryFlag, removeCustomInjuryFlag,
    toggleInjuryFlag,
  } = useProfileStore()

  const currentWeekData = program?.weeks[weekIndex]
  const { segments, totalWeeks } = usePhaseCalendar(program?.goal, weekIndex + 1)
  const regenerate = useRegenerateFromWeek()

  // Scroll to active week when weekIndex changes (only on calendar tab)
  useEffect(() => {
    if (activeTab !== 'calendar') return
    weekRefs.current[weekIndex]?.scrollIntoView({ behavior: 'smooth', block: 'start' })
  }, [weekIndex, activeTab])

  // Initialise draft state when sheet opens
  useEffect(() => {
    if (injurySheetOpen && program) {
      setLocalFlags([...(program.constraints.injury_flags ?? [])] as InjuryFlagId[])
      setLocalCustom([...customInjuryFlags])
    }
  }, [injurySheetOpen])

  const activeInjuryCount =
    (program?.constraints.injury_flags?.length ?? 0) + customInjuryFlags.length

  function handleRegenerate() {
    if (!program || !currentWeekData) return
    regenerate.mutate(
      {
        goalId: program.goal.id,
        constraints: {
          ...program.constraints,
          injury_flags: localFlags,
          periodization_week: currentWeekData.week_in_phase,
        },
        numWeeks: totalWeeks - weekIndex,
        customInjuryFlags: localCustom,
      },
      { onSuccess: () => setInjurySheetOpen(false) }
    )
  }

  if (!program) {
    return (
      <motion.div
        key="program-empty"
        initial={{ opacity: 0, y: 16 }}
        animate={{ opacity: 1, y: 0, transition: { duration: 0.25 } }}
        exit={{ opacity: 0, y: -8, transition: { duration: 0.15 } }}
        className="p-6"
      >
        <EmptyState
          title="No program generated yet"
          description="Use the builder to configure your goal and generate a personalized program."
          action={{ label: 'Build a Program', onClick: () => navigate('/builder') }}
          icon={<Wand2 className="size-10" />}
        />
      </motion.div>
    )
  }

  return (
    <motion.div
      key="program"
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0, transition: { duration: 0.25 } }}
      exit={{ opacity: 0, y: -8, transition: { duration: 0.15 } }}
      className="flex h-full flex-col"
    >
      {/* Header */}
      <div className="border-b bg-card/50 px-6 py-4 space-y-3">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h1 className="text-xl font-bold tracking-tight">{program.goal.name}</h1>
            <p className="text-sm text-muted-foreground">{totalWeeks}-week program</p>
          </div>
          <div className="flex items-center gap-2">
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
                isDeload={currentWeekData.is_deload}
                onPrev={() => setWeekIndex((i) => Math.max(0, i - 1))}
                onNext={() => setWeekIndex((i) => Math.min(program.weeks.length - 1, i + 1))}
              />
            )}
          </div>
        </div>

        <PhaseBar segments={segments} totalWeeks={totalWeeks} currentWeek={weekIndex + 1} />

        <Tabs value={activeTab} onValueChange={(v) => setActiveTab(v as typeof activeTab)}>
          <TabsList className="h-7 bg-muted/50">
            <TabsTrigger value="overview" className="h-5 px-3 text-xs">Overview</TabsTrigger>
            <TabsTrigger value="calendar" className="h-5 px-3 text-xs">Calendar</TabsTrigger>
          </TabsList>
        </Tabs>
      </div>

      {/* Body */}
      <div className="flex-1 overflow-y-auto">
        {activeTab === 'calendar' ? (
          <div className="p-6 space-y-8">
            {program.weeks.map((weekData, idx) => (
              <div
                key={weekData.week_number}
                ref={(el) => { weekRefs.current[idx] = el }}
                className={cn(
                  'space-y-3 rounded-xl p-3 -mx-3 transition-colors duration-300',
                  idx === weekIndex ? 'bg-primary/5 ring-1 ring-primary/20' : ''
                )}
              >
                <div className="flex items-center gap-2 px-1">
                  <span className="text-sm font-semibold text-foreground">
                    Week {weekData.week_number}
                  </span>
                  <PhaseBadge phase={weekData.phase as TrainingPhase} />
                  {weekData.is_deload && (
                    <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-slate-500/15 text-slate-400 border border-slate-500/30">
                      Deload
                    </span>
                  )}
                </div>
                <WeekCalendar weekData={weekData} />
              </div>
            ))}
          </div>
        ) : (
          <ProgramOverview program={program} segments={segments} />
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

            <button
              type="button"
              onClick={handleRegenerate}
              disabled={regenerate.isPending}
              className="w-full h-9 rounded-md bg-primary text-sm font-medium text-primary-foreground disabled:opacity-50 transition-opacity"
            >
              {regenerate.isPending
                ? 'Generating…'
                : `Regenerate from Week ${weekIndex + 1}`}
            </button>
          </div>
        </SheetContent>
      </Sheet>
    </motion.div>
  )
}
