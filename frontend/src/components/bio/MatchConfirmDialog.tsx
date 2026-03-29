import { useState, useMemo } from 'react'
import { format, parseISO } from 'date-fns'
import { X, ChevronDown, ChevronRight } from 'lucide-react'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { useBioStore } from '@/store/bioStore'
import { useCurrentProgram } from '@/api/programs'
import type { PendingMatch } from '@/api/types'

interface MatchConfirmDialogProps {
  match: PendingMatch | null
  onClose: () => void
}

function sessionLabel(sessionKey: string): string {
  const parts = sessionKey.split('-')
  if (parts.length < 2) return sessionKey
  return `Week ${parts[0]} — ${parts.slice(1).join('-')}`
}

function sessionModality(sessionKey: string, program: ReturnType<typeof useCurrentProgram>): string {
  if (!program) return ''
  const [week, ...dayParts] = sessionKey.split('-')
  const dayName = dayParts.join('-')
  const weekData = program.weeks.find((w) => w.week_number === parseInt(week, 10))
  const sessions = weekData?.schedule[dayName] ?? []
  return sessions.map((s) => s.modality.replace(/_/g, ' ')).join(', ')
}

export function MatchConfirmDialog({ match, onClose }: MatchConfirmDialogProps) {
  const confirmMatch = useBioStore((s) => s.confirmMatch)
  const rejectMatch = useBioStore((s) => s.rejectMatch)
  const program = useCurrentProgram()
  const [browseOpen, setBrowseOpen] = useState(false)

  // Build all sessions list for manual browse, grouped by week
  // (must be before early return to satisfy Rules of Hooks)
  const allSessionsByWeek = useMemo(() => {
    if (!program) return []
    return program.weeks.map((week) => {
      const sessions: { key: string; dayName: string; modalities: string }[] = []
      for (const [dayName, daySessions] of Object.entries(week.schedule)) {
        if (daySessions.length === 0) continue
        const key = `${week.week_number}-${dayName}`
        sessions.push({
          key,
          dayName,
          modalities: daySessions.map((s) => s.modality.replace(/_/g, ' ')).join(', '),
        })
      }
      return { weekNumber: week.week_number, sessions }
    }).filter((w) => w.sessions.length > 0)
  }, [program])

  if (!match) return null

  const { importedWorkout, candidateSessionKeys } = match
  const topSuggestion = candidateSessionKeys[0] ?? null

  function handleConfirm(sessionKey: string) {
    confirmMatch(importedWorkout.id, sessionKey)
    onClose()
  }

  function handleReject() {
    rejectMatch(importedWorkout.id)
    onClose()
  }

  const startFormatted = (() => {
    try {
      return format(parseISO(importedWorkout.startTime), 'EEE, MMM d — h:mm a')
    } catch {
      return importedWorkout.date
    }
  })()

  return (
    <Dialog open onOpenChange={() => onClose()}>
      <DialogContent className="max-w-md max-h-[80vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Match Workout to Session</DialogTitle>
          <DialogDescription>
            Which training session does this workout belong to?
          </DialogDescription>
        </DialogHeader>

        {/* Workout summary */}
        <div className="rounded-lg border border-border bg-muted/30 p-3 space-y-1.5">
          <div className="flex items-center justify-between">
            <span className="text-sm font-medium">
              {importedWorkout.activityType.replace(/HKWorkoutActivityType/, '')}
            </span>
            <Badge variant="outline" className="text-[10px]">
              {importedWorkout.source === 'apple_health' ? 'Apple Health'
                : importedWorkout.source === 'fit_file' ? '.fit file'
                : 'Strava'}
            </Badge>
          </div>
          <p className="text-xs text-muted-foreground">{startFormatted}</p>
          <div className="flex gap-3 text-xs text-muted-foreground">
            <span>{importedWorkout.durationMinutes} min</span>
            {importedWorkout.heartRate.avg != null && (
              <span>{Math.round(importedWorkout.heartRate.avg)} bpm avg</span>
            )}
          </div>
        </div>

        {/* Top suggestion */}
        {topSuggestion && (
          <div className="space-y-1.5">
            <p className="text-xs font-medium text-muted-foreground">Suggested match</p>
            <button
              type="button"
              onClick={() => handleConfirm(topSuggestion)}
              className="w-full flex items-center justify-between rounded-lg border border-primary/30 bg-primary/5 px-3 py-2.5 text-sm hover:border-primary/50 hover:bg-primary/10 transition-colors text-left"
            >
              <div>
                <p className="font-medium">{sessionLabel(topSuggestion)}</p>
                <p className="text-xs text-muted-foreground capitalize">
                  {sessionModality(topSuggestion, program)}
                </p>
              </div>
              <span className="text-xs text-primary">Select →</span>
            </button>
          </div>
        )}

        {/* Browse all sessions */}
        <div className="space-y-2">
          <button
            type="button"
            onClick={() => setBrowseOpen(!browseOpen)}
            className="flex items-center gap-1.5 text-xs text-muted-foreground hover:text-foreground transition-colors"
          >
            {browseOpen ? <ChevronDown className="size-3.5" /> : <ChevronRight className="size-3.5" />}
            Link to a different session
          </button>

          {browseOpen && (
            <div className="space-y-3 max-h-60 overflow-y-auto rounded-lg border border-border p-2">
              {allSessionsByWeek.map(({ weekNumber, sessions }) => (
                <div key={weekNumber}>
                  <p className="text-[10px] font-medium text-muted-foreground uppercase tracking-wide mb-1">
                    Week {weekNumber}
                  </p>
                  <div className="space-y-1">
                    {sessions.map(({ key, dayName, modalities }) => (
                      <button
                        key={key}
                        type="button"
                        onClick={() => handleConfirm(key)}
                        className="w-full flex items-center justify-between rounded-md px-2 py-1.5 text-xs hover:bg-muted transition-colors text-left"
                      >
                        <div>
                          <span className="font-medium">{dayName}</span>
                          <span className="text-muted-foreground ml-2 capitalize">{modalities}</span>
                        </div>
                        <span className="text-[10px] text-primary opacity-0 group-hover:opacity-100">Select</span>
                      </button>
                    ))}
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Reject */}
        <Button
          variant="ghost"
          size="sm"
          onClick={handleReject}
          className="w-full text-muted-foreground"
        >
          <X className="size-3.5 mr-1.5" />
          No match — skip this workout
        </Button>
      </DialogContent>
    </Dialog>
  )
}
