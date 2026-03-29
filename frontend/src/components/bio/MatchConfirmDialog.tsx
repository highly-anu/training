import { format, parseISO } from 'date-fns'
import { X } from 'lucide-react'
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

  if (!match) return null

  const { importedWorkout, candidateSessionKeys } = match

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
      <DialogContent className="max-w-md">
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
              {importedWorkout.source === 'apple_health' ? 'Apple Health' : 'Strava'}
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

        {/* Candidate sessions */}
        <div className="space-y-2">
          {candidateSessionKeys.map((key) => (
            <button
              key={key}
              type="button"
              onClick={() => handleConfirm(key)}
              className="w-full flex items-center justify-between rounded-lg border border-border bg-card px-3 py-2.5 text-sm hover:border-primary/50 hover:bg-primary/5 transition-colors text-left"
            >
              <div>
                <p className="font-medium">{sessionLabel(key)}</p>
                <p className="text-xs text-muted-foreground capitalize">
                  {sessionModality(key, program)}
                </p>
              </div>
              <span className="text-xs text-primary">Select →</span>
            </button>
          ))}
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
