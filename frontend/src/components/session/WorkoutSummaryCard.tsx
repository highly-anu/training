import { useMemo, useState, lazy, Suspense } from 'react'
import { Link } from 'react-router-dom'
import { Upload, Heart, Clock, Flame, MapPin, Mountain, CheckCircle2, Info, AlertTriangle, Zap, Link2, ExternalLink } from 'lucide-react'
import { format, parseISO } from 'date-fns'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from '@/components/ui/dialog'
import { HRZoneChart } from '@/components/bio/HRZoneChart'
import { HRTimeline } from '@/components/workout/HRTimeline'
import { computeHRZones, maxHRFromDOB } from '@/lib/hrZones'
import { computeSessionInsight } from '@/lib/sessionAnalysis'
import { scoreMatch, sessionCalendarDate } from '@/lib/workoutMatcher'
import { useBioStore } from '@/store/bioStore'
import { useProfileStore } from '@/store/profileStore'
import { useProgramStore } from '@/store/programStore'
import type { Session, InsightItem, ImportedWorkout } from '@/api/types'

const GPSMap = lazy(() =>
  import('@/components/workout/GPSMap').then((m) => ({ default: m.GPSMap }))
)

interface WorkoutSummaryCardProps {
  sessionKey: string
  sessions: Session[]
  weekIndex?: number
}

const SEVERITY_STYLES = {
  positive: { icon: CheckCircle2, color: 'text-emerald-500' },
  neutral: { icon: Info, color: 'text-muted-foreground' },
  warning: { icon: AlertTriangle, color: 'text-amber-500' },
} as const

function InsightRow({ item }: { item: InsightItem }) {
  const { icon: Icon, color } = SEVERITY_STYLES[item.severity]
  return (
    <div className="flex gap-2 py-1.5">
      <Icon className={`size-3.5 shrink-0 mt-0.5 ${color}`} />
      <div className="min-w-0">
        <p className={`text-xs font-medium ${color}`}>{item.label}</p>
        <p className="text-[11px] text-muted-foreground">{item.detail}</p>
        {item.metric && (
          <p className="text-[10px] text-muted-foreground/60 mt-0.5 font-mono">
            {item.metric.prescribed} → {item.metric.actual} {item.metric.unit}
          </p>
        )}
      </div>
    </div>
  )
}

const SCORE_RING = {
  green: 'ring-emerald-500/40 text-emerald-500',
  yellow: 'ring-amber-500/40 text-amber-500',
  red: 'ring-red-500/40 text-red-500',
} as const

export function WorkoutSummaryCard({ sessionKey, sessions, weekIndex: weekIndexProp }: WorkoutSummaryCardProps) {
  const getMatchedWorkout = useBioStore((s) => s.getMatchedWorkout)
  const matched = getMatchedWorkout(sessionKey)
  const importedWorkouts = useBioStore((s) => s.importedWorkouts)
  const workoutMatches = useBioStore((s) => s.workoutMatches)
  const confirmMatch = useBioStore((s) => s.confirmMatch)
  const perfLog = useBioStore((s) => s.sessionPerformanceLogs[sessionKey])
  const dateOfBirth = useProfileStore((s) => s.dateOfBirth)
  const programStartDate = useProgramStore((s) => s.programStartDate)

  const maxHR = maxHRFromDOB(dateOfBirth) ?? 190

  const zones = useMemo(
    () => matched ? computeHRZones(maxHR, matched.heartRate.samples ?? [], matched.heartRate.avg) : null,
    [matched, maxHR],
  )

  const insight = useMemo(
    () => matched ? computeSessionInsight(sessions, matched, perfLog, maxHR, sessionKey) : null,
    [sessions, matched, perfLog, maxHR, sessionKey],
  )

  const suggestion = useMemo(() => {
    if (matched) return null
    if (!programStartDate || weekIndexProp == null) return null
    const dashIdx = sessionKey.indexOf('-')
    const dayName = sessionKey.slice(dashIdx + 1)
    const calDate = sessionCalendarDate(programStartDate, weekIndexProp, dayName)
    if (!calDate) return null

    const matchedIds = new Set(
      workoutMatches.filter(m => m.matchConfidence !== 'rejected').map(m => m.importedWorkoutId)
    )
    const candidates = importedWorkouts.filter(w => w.date === calDate && !matchedIds.has(w.id))
    if (candidates.length === 0) return null

    // If there's exactly one candidate on the same date, always suggest it
    if (candidates.length === 1) return { workout: candidates[0], score: 5 }

    let bestWorkout: typeof candidates[0] | null = null
    let bestScore = 0
    for (const w of candidates) {
      for (const s of sessions) {
        const score = scoreMatch(w, s.modality, s.archetype?.duration_estimate_minutes ?? 60)
        if (score > bestScore) { bestScore = score; bestWorkout = w }
      }
    }
    return bestWorkout ? { workout: bestWorkout, score: bestScore } : null
  }, [matched, sessionKey, sessions, importedWorkouts, workoutMatches, programStartDate, weekIndexProp])

  const [showLinkPicker, setShowLinkPicker] = useState(false)

  const unmatchedWorkouts = useMemo(() => {
    const matchedIds = new Set(
      workoutMatches.filter(m => m.matchConfidence !== 'rejected').map(m => m.importedWorkoutId)
    )
    return importedWorkouts
      .filter(w => !matchedIds.has(w.id))
      .sort((a, b) => b.date.localeCompare(a.date))
  }, [importedWorkouts, workoutMatches])

  if (!matched) {
    return (
      <>
        <div className="rounded-lg border border-dashed border-border bg-muted/20 px-4 py-3 space-y-3">
          {suggestion ? (
            <>
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <Zap className="size-3.5 text-amber-500" />
                  <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
                    Suggested Match
                  </p>
                </div>
                <Button
                  size="sm"
                  variant="outline"
                  className="h-7 text-xs border-emerald-500/40 text-emerald-500 hover:bg-emerald-500/10"
                  onClick={() => confirmMatch(suggestion.workout.id, sessionKey)}
                >
                  <CheckCircle2 className="size-3 mr-1" />
                  Confirm
                </Button>
              </div>
              <div className="flex flex-wrap gap-3 text-sm">
                <span className="font-medium">
                  {suggestion.workout.activityType.replace(/HKWorkoutActivityType/, '')}
                </span>
                <span className="text-muted-foreground">{suggestion.workout.durationMinutes} min</span>
                {suggestion.workout.heartRate.avg != null && (
                  <span className="text-muted-foreground">{Math.round(suggestion.workout.heartRate.avg)} bpm avg</span>
                )}
              </div>
            </>
          ) : (
            <div className="flex items-center justify-between">
              <p className="text-sm text-muted-foreground">No workout data linked to this session.</p>
              <div className="flex items-center gap-2">
                {unmatchedWorkouts.length > 0 && (
                  <button
                    type="button"
                    onClick={() => setShowLinkPicker(true)}
                    className="flex items-center gap-1.5 text-xs font-medium text-primary hover:text-primary/80 transition-colors"
                  >
                    <Link2 className="size-3.5" />
                    Link existing
                  </button>
                )}
                <Link
                  to={`/import?linkTo=${sessionKey}`}
                  className="flex items-center gap-1.5 text-xs font-medium text-primary hover:text-primary/80 transition-colors"
                >
                  <Upload className="size-3.5" />
                  Import
                </Link>
              </div>
            </div>
          )}
        </div>

        {/* Link existing workout picker */}
        <LinkWorkoutDialog
          open={showLinkPicker}
          onClose={() => setShowLinkPicker(false)}
          workouts={unmatchedWorkouts}
          onSelect={(w) => { confirmMatch(w.id, sessionKey); setShowLinkPicker(false) }}
        />
      </>
    )
  }

  const sourceLabel =
    matched.source === 'apple_health' ? 'Apple Health'
    : matched.source === 'fit_file' ? '.fit file'
    : matched.source === 'strava' ? 'Strava'
    : matched.source

  const hasGPS = matched.gpsTrack && matched.gpsTrack.length > 1
  const hasSamples = (matched.heartRate.samples?.length ?? 0) > 1

  const pace = matched.distance
    ? (() => {
        const km = matched.distance!.unit === 'km' ? matched.distance!.value : matched.distance!.value / 1000
        if (km <= 0 || matched.durationMinutes <= 0) return null
        const paceMin = matched.durationMinutes / km
        const mins = Math.floor(paceMin)
        const secs = Math.round((paceMin - mins) * 60)
        return `${mins}:${secs.toString().padStart(2, '0')} /km`
      })()
    : null

  return (
    <div className="rounded-lg border border-border bg-card p-4 space-y-3">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <h3 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
            Workout Data
          </h3>
          {insight && (
            <span
              className={`inline-flex items-center justify-center size-6 rounded-full ring-2 text-[10px] font-bold ${SCORE_RING[insight.status]}`}
            >
              {insight.complianceScore}
            </span>
          )}
        </div>
        <div className="flex items-center gap-2">
          <Badge variant="outline" className="text-[10px]">
            {sourceLabel}
          </Badge>
          <Link
            to={`/import/${matched.id}`}
            className="text-[10px] text-muted-foreground hover:text-foreground transition-colors flex items-center gap-0.5"
          >
            <ExternalLink className="size-3" />
            Details
          </Link>
        </div>
      </div>

      {/* Stats row */}
      <div className="flex flex-wrap gap-4">
        {matched.heartRate.avg != null && (
          <div className="flex items-center gap-1.5">
            <Heart className="size-3.5 text-red-400" />
            <span className="text-sm font-semibold">{Math.round(matched.heartRate.avg)}</span>
            {matched.heartRate.max != null && (
              <span className="text-xs text-muted-foreground">/ {Math.round(matched.heartRate.max)} bpm</span>
            )}
          </div>
        )}
        <div className="flex items-center gap-1.5">
          <Clock className="size-3.5 text-muted-foreground" />
          <span className="text-sm">{matched.durationMinutes} min</span>
        </div>
        {matched.calories != null && (
          <div className="flex items-center gap-1.5">
            <Flame className="size-3.5 text-orange-400" />
            <span className="text-sm">{matched.calories} kcal</span>
          </div>
        )}
        {matched.distance && (
          <div className="flex items-center gap-1.5">
            <MapPin className="size-3.5 text-blue-400" />
            <span className="text-sm">
              {matched.distance.unit === 'km'
                ? `${matched.distance.value.toFixed(1)} km`
                : `${(matched.distance.value / 1000).toFixed(1)} km`}
            </span>
            {pace && <span className="text-xs text-muted-foreground">{pace}</span>}
          </div>
        )}
        {matched.elevation && (matched.elevation.gain > 0 || matched.elevation.loss > 0) && (
          <div className="flex items-center gap-1.5">
            <Mountain className="size-3.5 text-emerald-400" />
            <span className="text-sm">+{matched.elevation.gain}m / -{matched.elevation.loss}m</span>
          </div>
        )}
      </div>

      {/* GPS Map */}
      {hasGPS && (
        <div>
          <p className="text-[10px] text-muted-foreground mb-1">Route</p>
          <Suspense
            fallback={
              <div className="flex items-center justify-center h-[200px] rounded-lg border border-border bg-muted/20">
                <div className="size-4 animate-spin rounded-full border-2 border-primary border-t-transparent" />
              </div>
            }
          >
            <GPSMap
              track={matched.gpsTrack!}
              maxHR={maxHR}
              className="h-[200px]"
            />
          </Suspense>
        </div>
      )}

      {/* HR Timeline */}
      {hasSamples && (
        <div>
          <p className="text-[10px] text-muted-foreground mb-1">Heart Rate Over Time</p>
          <HRTimeline
            samples={matched.heartRate.samples!}
            avgHR={matched.heartRate.avg}
            maxHR={maxHR}
          />
        </div>
      )}

      {/* HR Zone chart */}
      {zones && (matched.heartRate.avg != null || matched.heartRate.max != null) && (
        <div>
          <p className="text-[10px] text-muted-foreground mb-1">Time in HR Zone</p>
          <HRZoneChart zones={zones} />
        </div>
      )}

      {/* Session Insights */}
      {insight && insight.insights.length > 0 && (
        <div className="pt-1 border-t border-border">
          <p className="text-[10px] text-muted-foreground mb-1 uppercase tracking-wider font-semibold">
            Insights
          </p>
          <div className="divide-y divide-border">
            {insight.insights.map((item) => (
              <InsightRow key={item.key} item={item} />
            ))}
          </div>
        </div>
      )}
    </div>
  )
}

// ── Link existing workout picker dialog ──────────────────────────────────────

function LinkWorkoutDialog({
  open,
  onClose,
  workouts,
  onSelect,
}: {
  open: boolean
  onClose: () => void
  workouts: ImportedWorkout[]
  onSelect: (w: ImportedWorkout) => void
}) {
  return (
    <Dialog open={open} onOpenChange={() => onClose()}>
      <DialogContent className="max-w-md max-h-[70vh] flex flex-col">
        <DialogHeader>
          <DialogTitle>Link Imported Workout</DialogTitle>
          <DialogDescription>
            Select an imported workout to link to this session.
          </DialogDescription>
        </DialogHeader>
        <div className="overflow-y-auto space-y-2 flex-1">
          {workouts.length === 0 && (
            <p className="text-sm text-muted-foreground py-4 text-center">
              No unlinked imported workouts available.
            </p>
          )}
          {workouts.map((w) => {
            let dateLabel: string
            try { dateLabel = format(parseISO(w.startTime), 'EEE, MMM d') }
            catch { dateLabel = w.date }
            return (
              <button
                key={w.id}
                type="button"
                onClick={() => onSelect(w)}
                className="w-full flex items-center justify-between rounded-lg border border-border bg-card px-3 py-2.5 text-sm hover:border-primary/50 hover:bg-primary/5 transition-colors text-left"
              >
                <div>
                  <p className="font-medium">
                    {w.activityType.replace(/HKWorkoutActivityType/, '')}
                  </p>
                  <p className="text-xs text-muted-foreground">
                    {dateLabel} · {w.durationMinutes} min
                    {w.heartRate.avg != null && ` · ${Math.round(w.heartRate.avg)} bpm`}
                  </p>
                </div>
                <span className="text-xs text-primary shrink-0 ml-2">Link →</span>
              </button>
            )
          })}
        </div>
      </DialogContent>
    </Dialog>
  )
}
