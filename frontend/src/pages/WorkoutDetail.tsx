import { useMemo, useState, lazy, Suspense } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { motion } from 'framer-motion'
import {
  ChevronLeft,
  Clock,
  Flame,
  Heart,
  MapPin,
  Activity,
  Mountain,
  CheckCircle2,
  Info,
  AlertTriangle,
  Link2,
} from 'lucide-react'
import { format, parseISO } from 'date-fns'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Separator } from '@/components/ui/separator'
import { HRZoneChart } from '@/components/bio/HRZoneChart'
import { HRTimeline } from '@/components/workout/HRTimeline'
import { MatchConfirmDialog } from '@/components/bio/MatchConfirmDialog'
import { useBioStore } from '@/store/bioStore'
import { useProfileStore } from '@/store/profileStore'
import { useProgramStore } from '@/store/programStore'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import { computeHRZones, maxHRFromDOB } from '@/lib/hrZones'
import { computeSessionInsight } from '@/lib/sessionAnalysis'
import { scoreMatch, sessionCalendarDate } from '@/lib/workoutMatcher'
import { useCurrentProgram } from '@/api/programs'
import type { ImportedWorkout, InsightItem, PendingMatch } from '@/api/types'

// Lazy-load Leaflet map (heavy dependency)
const GPSMap = lazy(() =>
  import('@/components/workout/GPSMap').then((m) => ({ default: m.GPSMap }))
)

const SEVERITY_STYLES = {
  positive: { icon: CheckCircle2, color: 'text-emerald-500' },
  neutral: { icon: Info, color: 'text-muted-foreground' },
  warning: { icon: AlertTriangle, color: 'text-amber-500' },
} as const

const SCORE_RING = {
  green: 'ring-emerald-500/40 text-emerald-500',
  yellow: 'ring-amber-500/40 text-amber-500',
  red: 'ring-red-500/40 text-red-500',
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
            {item.metric.prescribed} &rarr; {item.metric.actual} {item.metric.unit}
          </p>
        )}
      </div>
    </div>
  )
}

function StatCard({
  icon: Icon,
  label,
  value,
  sub,
}: {
  icon: React.ComponentType<{ className?: string }>
  label: string
  value: string
  sub?: string
}) {
  return (
    <div className="rounded-lg border border-border bg-card px-4 py-3 space-y-1">
      <div className="flex items-center gap-2 text-muted-foreground">
        <Icon className="size-3.5" />
        <span className="text-[11px] font-medium uppercase tracking-wider">{label}</span>
      </div>
      <p className="text-xl font-semibold tabular-nums">{value}</p>
      {sub && <p className="text-[11px] text-muted-foreground">{sub}</p>}
    </div>
  )
}

function formatDuration(minutes: number) {
  const h = Math.floor(minutes / 60)
  const m = minutes % 60
  return h > 0 ? `${h}h ${m}m` : `${m}m`
}

function formatDistance(dist: { value: number; unit: 'km' | 'm' }) {
  if (dist.unit === 'km') return `${dist.value.toFixed(2)} km`
  if (dist.value >= 1000) return `${(dist.value / 1000).toFixed(2)} km`
  return `${Math.round(dist.value)} m`
}

function formatPace(dist: { value: number; unit: 'km' | 'm' }, durationMinutes: number) {
  const km = dist.unit === 'km' ? dist.value : dist.value / 1000
  if (km <= 0) return null
  const paceMin = durationMinutes / km
  const paceMins = Math.floor(paceMin)
  const paceSecs = Math.round((paceMin - paceMins) * 60)
  return `${paceMins}:${paceSecs.toString().padStart(2, '0')} /km`
}

export function WorkoutDetail() {
  const { workoutId } = useParams<{ workoutId: string }>()
  const navigate = useNavigate()
  const workout = useBioStore((s) =>
    s.importedWorkouts.find((w) => w.id === workoutId)
  ) as ImportedWorkout | undefined

  const workoutMatches = useBioStore((s) => s.workoutMatches)
  const match = workoutMatches.find((m) => m.importedWorkoutId === workoutId)

  const [linkPending, setLinkPending] = useState<PendingMatch | null>(null)
  const programStartDate = useProgramStore((s) => s.programStartDate)

  const perfLogs = useBioStore((s) => s.sessionPerformanceLogs)
  const program = useCurrentProgram()

  const dob = useProfileStore((s) => s.dateOfBirth ?? null)
  const maxHR = maxHRFromDOB(dob) ?? 190

  // Resolve matched session from program
  const matchedSessions = useMemo(() => {
    if (!match || !program) return null
    const [weekStr, ...dayParts] = match.sessionKey.split('-')
    const weekNum = parseInt(weekStr, 10)
    const dayName = dayParts.join('-')
    const week = program.weeks.find((w) => w.week_number === weekNum)
    return week?.schedule[dayName] ?? null
  }, [match, program])

  const insight = useMemo(() => {
    if (!workout || !matchedSessions) return null
    const perfLog = match ? perfLogs[match.sessionKey] : undefined
    return computeSessionInsight(matchedSessions, workout, perfLog, maxHR, match?.sessionKey)
  }, [workout, matchedSessions, perfLogs, match, maxHR])

  const hrZones = useMemo(() => {
    if (!workout) return null
    const samples = workout.heartRate.samples ?? []
    if (samples.length === 0 && workout.heartRate.avg == null) return null
    return computeHRZones(maxHR, samples, workout.heartRate.avg ?? undefined)
  }, [workout, maxHR])

  function handleManualLink() {
    if (!workout || !program || !programStartDate) return
    const candidates: { sessionKey: string; score: number }[] = []
    for (let weekIdx = 0; weekIdx < program.weeks.length; weekIdx++) {
      const week = program.weeks[weekIdx]
      for (const [dayName, sessions] of Object.entries(week.schedule)) {
        const key = `${week.week_number}-${dayName}`
        for (const s of sessions) {
          const sc = scoreMatch(workout, s.modality, s.archetype?.duration_estimate_minutes ?? 60)
          const calDate = sessionCalendarDate(programStartDate, weekIdx, dayName)
          const dateBonus = calDate === workout.date ? 5 : 0
          candidates.push({ sessionKey: key, score: sc + dateBonus })
        }
      }
    }
    const sorted = candidates.sort((a, b) => b.score - a.score)
    if (sorted.length > 0) {
      setLinkPending({
        importedWorkout: workout,
        candidateSessionKeys: [sorted[0].sessionKey],
      })
    }
  }

  if (!workout) {
    return (
      <motion.div
        key="workout-not-found"
        initial={{ opacity: 0, y: 16 }}
        animate={{ opacity: 1, y: 0, transition: { duration: 0.25 } }}
        exit={{ opacity: 0, y: -8, transition: { duration: 0.15 } }}
        className="p-6"
      >
        <Button variant="ghost" size="sm" onClick={() => navigate('/import')}>
          <ChevronLeft className="size-4 mr-1" />
          Back
        </Button>
        <p className="text-sm text-muted-foreground mt-4">Workout not found.</p>
      </motion.div>
    )
  }

  const displayType = workout.activityType.replace(/HKWorkoutActivityType/, '')
  const modColor = workout.inferredModalityId
    ? MODALITY_COLORS[workout.inferredModalityId]
    : null

  let dateStr: string
  try {
    dateStr = format(parseISO(workout.startTime), 'EEEE, MMMM d, yyyy')
  } catch {
    dateStr = workout.date
  }

  let timeStr: string
  try {
    timeStr = format(parseISO(workout.startTime), 'HH:mm') + ' – ' + format(parseISO(workout.endTime), 'HH:mm')
  } catch {
    timeStr = ''
  }

  const pace =
    workout.distance ? formatPace(workout.distance, workout.durationMinutes) : null

  const hasGPS = workout.gpsTrack && workout.gpsTrack.length > 1
  const hasSamples = (workout.heartRate.samples?.length ?? 0) > 1

  const rawEntries = Object.entries(workout.rawData).filter(
    ([, v]) => v != null && v !== '' && v !== 0
  )

  return (
    <motion.div
      key="workout-detail"
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0, transition: { duration: 0.25 } }}
      exit={{ opacity: 0, y: -8, transition: { duration: 0.15 } }}
      className="h-full overflow-y-auto p-6 space-y-6 max-w-2xl"
    >
      {/* Back button */}
      <Button variant="ghost" size="sm" onClick={() => navigate('/import')}>
        <ChevronLeft className="size-4 mr-1" />
        Back to Import
      </Button>

      {/* Header */}
      <div className="space-y-2">
        <div className="flex items-center gap-3 flex-wrap">
          <h1 className="text-2xl font-bold tracking-tight">{displayType}</h1>
          {modColor && (
            <Badge
              variant="outline"
              className={`text-xs ${modColor.border} ${modColor.text}`}
            >
              {modColor.label}
            </Badge>
          )}
          <Badge variant="outline" className="text-xs text-muted-foreground">
            {workout.source.replace('_', ' ')}
          </Badge>
          {match && match.matchConfidence !== 'rejected' && (
            <Badge
              variant="outline"
              className="text-xs border-emerald-500/40 text-emerald-500"
            >
              matched &rarr; {match.sessionKey}
            </Badge>
          )}
          {(!match || match.matchConfidence === 'rejected') && program && programStartDate && (
            <Button size="sm" variant="outline" onClick={handleManualLink}>
              <Link2 className="size-3.5 mr-1" />
              Link to Session
            </Button>
          )}
        </div>
        <p className="text-sm text-muted-foreground">
          {dateStr}
          {timeStr && <span className="ml-2 text-muted-foreground/60">{timeStr}</span>}
        </p>
      </div>

      <Separator />

      {/* GPS Map */}
      {hasGPS && (
        <div className="space-y-2">
          <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
            Route
          </h2>
          <Suspense
            fallback={
              <div className="flex items-center justify-center h-[360px] rounded-lg border border-border bg-muted/20">
                <div className="size-5 animate-spin rounded-full border-2 border-primary border-t-transparent" />
              </div>
            }
          >
            <GPSMap
              track={workout.gpsTrack!}
              maxHR={maxHR}
            />
          </Suspense>
          <div className="flex gap-4 text-[10px] text-muted-foreground">
            <span><span className="inline-block w-3 h-0.5 rounded bg-[#22c55e] align-middle mr-1" />Start</span>
            <span><span className="inline-block w-3 h-0.5 rounded bg-[#ef4444] align-middle mr-1" />End</span>
            <span className="ml-auto">Track colored by HR zone</span>
          </div>
        </div>
      )}

      {/* Stat cards */}
      <div className="grid grid-cols-2 gap-3">
        <StatCard
          icon={Clock}
          label="Duration"
          value={formatDuration(workout.durationMinutes)}
          sub={`${workout.durationMinutes} min total`}
        />
        {workout.heartRate.avg != null && (
          <StatCard
            icon={Heart}
            label="Avg Heart Rate"
            value={`${Math.round(workout.heartRate.avg)} bpm`}
            sub={
              workout.heartRate.max != null
                ? `Max ${Math.round(workout.heartRate.max)} bpm`
                : undefined
            }
          />
        )}
        {workout.calories != null && workout.calories > 0 && (
          <StatCard
            icon={Flame}
            label="Calories"
            value={`${Math.round(workout.calories)}`}
            sub="kcal"
          />
        )}
        {workout.distance && (
          <StatCard
            icon={MapPin}
            label="Distance"
            value={formatDistance(workout.distance)}
            sub={pace ?? undefined}
          />
        )}
        {workout.elevation && (
          <StatCard
            icon={Mountain}
            label="Elevation"
            value={`+${workout.elevation.gain} m`}
            sub={`-${workout.elevation.loss} m`}
          />
        )}
        {workout.heartRate.max != null && workout.heartRate.avg == null && (
          <StatCard
            icon={Activity}
            label="Max Heart Rate"
            value={`${Math.round(workout.heartRate.max)} bpm`}
          />
        )}
      </div>

      {/* Prescribed vs Actual */}
      {insight && insight.insights.length > 0 && (
        <>
          <Separator />
          <div className="space-y-3">
            <div className="flex items-center gap-3">
              <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
                Prescribed vs Actual
              </h2>
              <span
                className={`inline-flex items-center justify-center size-7 rounded-full ring-2 text-xs font-bold ${SCORE_RING[insight.status]}`}
              >
                {insight.complianceScore}
              </span>
            </div>
            <div className="rounded-lg border border-border bg-card p-3 divide-y divide-border">
              {insight.insights.map((item) => (
                <InsightRow key={item.key} item={item} />
              ))}
            </div>
          </div>
        </>
      )}

      {/* HR Timeline */}
      {hasSamples && (
        <>
          <Separator />
          <div className="space-y-2">
            <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
              Heart Rate Over Time
            </h2>
            <HRTimeline
              samples={workout.heartRate.samples!}
              avgHR={workout.heartRate.avg}
              maxHR={maxHR}
            />
          </div>
        </>
      )}

      {/* HR Zone Distribution */}
      {hrZones && (
        <>
          <Separator />
          <div className="space-y-2">
            <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
              HR Zone Distribution
            </h2>
            <HRZoneChart zones={hrZones} />
          </div>
        </>
      )}

      {/* Raw data */}
      {rawEntries.length > 0 && (
        <>
          <Separator />
          <div className="space-y-2">
            <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
              Source Data
            </h2>
            <div className="rounded-lg border border-border bg-card overflow-hidden">
              <table className="w-full text-sm">
                <tbody>
                  {rawEntries.map(([key, val]) => (
                    <tr key={key} className="border-b border-border last:border-0">
                      <td className="px-3 py-2 text-muted-foreground font-mono text-xs w-1/3">
                        {key}
                      </td>
                      <td className="px-3 py-2 text-xs font-medium">
                        {typeof val === 'object' ? JSON.stringify(val) : String(val)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </>
      )}

      {/* Manual link dialog */}
      <MatchConfirmDialog match={linkPending} onClose={() => setLinkPending(null)} />
    </motion.div>
  )
}
