import { useState, useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import { Settings, CalendarDays, Wand2, Flag, RotateCcw } from 'lucide-react'
import { differenceInCalendarDays, differenceInWeeks, parseISO, format, addDays } from 'date-fns'
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from '@/components/ui/sheet'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Separator } from '@/components/ui/separator'
import { useProgramStore } from '@/store/programStore'
import { useBuilderStore } from '@/store/builderStore'
import { useRegenerateFromWeek } from '@/api/programs'
import type { GeneratedProgram } from '@/api/types'

interface ProgramSettingsSheetProps {
  program: GeneratedProgram
}

export function ProgramSettingsSheet({ program }: ProgramSettingsSheetProps) {
  const navigate = useNavigate()
  const [open, setOpen] = useState(false)
  const [rebuildDialogOpen, setRebuildDialogOpen] = useState(false)

  const eventDate = useProgramStore((s) => s.eventDate)
  const programStartDate = useProgramStore((s) => s.programStartDate)
  // Filter out synthetic _blended IDs that may have been stored by earlier versions
  const sourceGoalIds = useProgramStore((s) => s.sourceGoalIds).filter((id) => id !== '_blended')
  const sourceGoalWeights = useProgramStore((s) => s.sourceGoalWeights)
  const setEventDate = useProgramStore((s) => s.setEventDate)
  const setProgramStartDate = useProgramStore((s) => s.setProgramStartDate)
  const loadFromProgram = useBuilderStore((s) => s.loadFromProgram)
  const reset = useBuilderStore((s) => s.reset)
  const regenerate = useRegenerateFromWeek()

  const today = new Date().toISOString().slice(0, 10)

  // Valid real goal IDs to restore — empty means we can't do a pre-filled rebuild
  const canRebuild = sourceGoalIds.length > 0

  const daysToEvent = eventDate
    ? differenceInCalendarDays(parseISO(eventDate), new Date())
    : null
  const weeksToEvent = eventDate
    ? differenceInWeeks(parseISO(eventDate), new Date())
    : null

  // Which week index does "tomorrow" fall in, based on the program start date?
  const tomorrowWeekIdx = useMemo(() => {
    if (!programStartDate) return 0
    const tomorrow = addDays(new Date(), 1)
    const days = differenceInCalendarDays(tomorrow, parseISO(programStartDate))
    return Math.max(0, Math.floor(days / 7))
  }, [programStartDate])

  const weeksRemainingFromTomorrow = program.weeks.length - tomorrowWeekIdx
  const canRegenerateFromTomorrow = weeksRemainingFromTomorrow > 0

  function handleRebuildFromTomorrow() {
    regenerate.mutate({
      philosophyId: sourceGoalIds.length === 1 ? sourceGoalIds[0] : undefined,
      philosophyIds: sourceGoalIds.length > 1 ? sourceGoalIds : undefined,
      philosophyWeights: sourceGoalIds.length > 1 ? sourceGoalWeights : undefined,
      constraints: program.constraints,
      numWeeks: weeksRemainingFromTomorrow,
    })
    setRebuildDialogOpen(false)
    setOpen(false)
  }

  function handleRebuildFull() {
    loadFromProgram({
      goalIds: sourceGoalIds,
      goalWeights: sourceGoalWeights,
      constraints: program.constraints,
      numWeeks: program.weeks.length,
      eventDate,
    })
    setRebuildDialogOpen(false)
    setOpen(false)
    navigate('/builder')
  }

  function handleNewProgram() {
    reset()
    setOpen(false)
    navigate('/builder')
  }

  return (
    <>
    <Sheet open={open} onOpenChange={setOpen}>
      <SheetTrigger asChild>
        <button
          type="button"
          className="shrink-0 rounded-md p-1.5 text-muted-foreground hover:bg-muted hover:text-foreground transition-colors"
          aria-label="Program settings"
        >
          <Settings className="size-4" />
        </button>
      </SheetTrigger>

      <SheetContent className="w-full sm:max-w-md overflow-y-auto">
        <SheetHeader className="mb-6">
          <SheetTitle>Program Settings</SheetTitle>
        </SheetHeader>

        {/* Program summary */}
        <div className="rounded-xl border bg-card p-4 space-y-2 mb-6">
          <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
            Current Program
          </p>
          <p className="text-sm font-semibold">{program.goal.name}</p>
          <p className="text-xs text-muted-foreground">
            {program.weeks.length} weeks · {program.constraints.days_per_week ?? 4} days/week ·{' '}
            {program.constraints.session_time_minutes ?? 60} min sessions
          </p>
        </div>

        <div className="space-y-5">
          {/* Event / goal date */}
          <div className="space-y-2">
            <label className="flex items-center gap-2 text-sm font-medium">
              <Flag className="size-3.5 text-muted-foreground" />
              Event / Goal Date
            </label>
            <p className="text-[11px] text-muted-foreground">
              Race day, expedition start, competition — sets a target endpoint visible on your dashboard.
            </p>
            <div className="flex items-center gap-2">
              <input
                type="date"
                value={eventDate ?? ''}
                min={today}
                onChange={(e) => setEventDate(e.target.value || null)}
                className="flex-1 h-9 rounded-md border border-border bg-background px-3 text-sm focus:outline-none focus:ring-1 focus:ring-primary"
              />
              {eventDate && (
                <button
                  type="button"
                  onClick={() => setEventDate(null)}
                  className="text-xs text-muted-foreground hover:text-foreground underline underline-offset-2 shrink-0"
                >
                  Clear
                </button>
              )}
            </div>

            {eventDate && daysToEvent !== null && (
              <div className={`rounded-lg border px-3 py-2 text-sm font-medium ${
                daysToEvent < 0
                  ? 'border-muted text-muted-foreground'
                  : daysToEvent < 14
                    ? 'border-amber-500/30 bg-amber-500/5 text-amber-500'
                    : 'border-emerald-500/30 bg-emerald-500/5 text-emerald-600'
              }`}>
                {daysToEvent < 0 ? (
                  <span>Event date has passed ({Math.abs(daysToEvent)} days ago)</span>
                ) : daysToEvent === 0 ? (
                  <span>Event is today!</span>
                ) : (
                  <span>
                    <span className="font-bold">{weeksToEvent}w {daysToEvent % 7}d</span> until{' '}
                    {format(parseISO(eventDate), 'MMM d, yyyy')}
                  </span>
                )}
              </div>
            )}
          </div>

          {/* Program start date */}
          <div className="space-y-2">
            <label className="flex items-center gap-2 text-sm font-medium">
              <CalendarDays className="size-3.5 text-muted-foreground" />
              Program Start Date
            </label>
            <p className="text-[11px] text-muted-foreground">
              Used to map program weeks to calendar dates for workout import matching.
            </p>
            <input
              type="date"
              value={programStartDate ?? ''}
              onChange={(e) => setProgramStartDate(e.target.value || null)}
              className="w-full h-9 rounded-md border border-border bg-background px-3 text-sm focus:outline-none focus:ring-1 focus:ring-primary"
            />
          </div>

          <Separator />

          {/* Rebuild / New program */}
          <div className="space-y-3">
            <p className="text-sm font-medium">Change Program</p>

            {canRebuild && (
              <div className="space-y-1.5">
                <p className="text-[11px] text-muted-foreground">
                  Opens the builder pre-filled with your current goal
                  {sourceGoalIds.length > 1 ? 's' : ''}, constraints, and duration.
                </p>
                <Button
                  variant="outline"
                  className="w-full gap-2"
                  onClick={() => setRebuildDialogOpen(true)}
                >
                  <Wand2 className="size-3.5" />
                  Rebuild Program
                </Button>
              </div>
            )}

            <div className="space-y-1.5">
              <p className="text-[11px] text-muted-foreground">
                Start fresh — pick a new goal and generate a completely new program.
              </p>
              <Button
                variant={canRebuild ? 'ghost' : 'outline'}
                className="w-full gap-2"
                onClick={handleNewProgram}
              >
                <RotateCcw className="size-3.5" />
                New Program
              </Button>
            </div>
          </div>
        </div>
      </SheetContent>
    </Sheet>

    <Dialog open={rebuildDialogOpen} onOpenChange={setRebuildDialogOpen}>
      <DialogContent className="sm:max-w-sm">
        <DialogHeader>
          <DialogTitle>Rebuild Program</DialogTitle>
          <DialogDescription>
            Choose how much of your program to replace. Sessions and data you've already logged are never affected.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-3 pt-1">
          {/* Default / recommended option */}
          <button
            type="button"
            disabled={!canRegenerateFromTomorrow || regenerate.isPending}
            onClick={handleRebuildFromTomorrow}
            className="w-full rounded-lg border-2 border-primary bg-primary/5 px-4 py-3 text-left transition-colors hover:bg-primary/10 disabled:opacity-40 disabled:cursor-not-allowed"
          >
            <p className="text-sm font-semibold text-primary">
              {regenerate.isPending ? 'Generating…' : 'From tomorrow onwards'}
            </p>
            <p className="mt-0.5 text-[11px] text-muted-foreground">
              {canRegenerateFromTomorrow
                ? `Keeps your completed sessions. Regenerates the remaining ${weeksRemainingFromTomorrow} week${weeksRemainingFromTomorrow !== 1 ? 's' : ''} using your current goal and constraints.`
                : 'No weeks remaining to regenerate — your program is complete.'}
            </p>
          </button>

          {/* Full rebuild option */}
          <button
            type="button"
            onClick={handleRebuildFull}
            className="w-full rounded-lg border border-border px-4 py-3 text-left transition-colors hover:bg-muted"
          >
            <p className="text-sm font-semibold">Rebuild entire program</p>
            <p className="mt-0.5 text-[11px] text-muted-foreground">
              Opens the builder so you can change goals or constraints. Replaces all weeks from the start.
            </p>
          </button>

          <button
            type="button"
            onClick={() => setRebuildDialogOpen(false)}
            className="w-full text-center text-xs text-muted-foreground hover:text-foreground py-1 transition-colors"
          >
            Cancel
          </button>
        </div>
      </DialogContent>
    </Dialog>
    </>
  )
}
