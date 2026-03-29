import { Link } from 'react-router-dom'
import { Upload, Heart, Clock, Flame } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { HRZoneChart } from '@/components/bio/HRZoneChart'
import { computeHRZones, parseZoneTarget, isZoneCompliant, maxHRFromDOB } from '@/lib/hrZones'
import { useBioStore } from '@/store/bioStore'
import { useProfileStore } from '@/store/profileStore'
import type { Session } from '@/api/types'

interface WorkoutSummaryCardProps {
  sessionKey: string
  sessions: Session[]
}

export function WorkoutSummaryCard({ sessionKey, sessions }: WorkoutSummaryCardProps) {
  const getMatchedWorkout = useBioStore((s) => s.getMatchedWorkout)
  const matched = getMatchedWorkout(sessionKey)
  const dateOfBirth = useProfileStore((s) => s.dateOfBirth)

  if (!matched) {
    return (
      <div className="flex items-center justify-between rounded-lg border border-dashed border-border bg-muted/20 px-4 py-3">
        <p className="text-sm text-muted-foreground">No workout data linked to this session.</p>
        <Link
          to="/import"
          className="flex items-center gap-1.5 text-xs font-medium text-primary hover:text-primary/80 transition-colors"
        >
          <Upload className="size-3.5" />
          Import
        </Link>
      </div>
    )
  }

  const maxHR = matched.heartRate.max ?? maxHRFromDOB(dateOfBirth) ?? 190
  const zones = computeHRZones(maxHR, matched.heartRate.samples ?? [], matched.heartRate.avg)

  // Check zone compliance across all sessions
  const zoneTargets = sessions.flatMap((s) =>
    s.exercises
      .map((e) => e.load.zone_target)
      .filter((zt): zt is string => Boolean(zt))
  )
  const prescribedZone = zoneTargets.length > 0 ? parseZoneTarget(zoneTargets[0]) : null
  const compliant = prescribedZone != null ? isZoneCompliant(zones, prescribedZone) : null

  const sourceLabel = matched.source === 'apple_health' ? 'Apple Health' : 'Strava'

  return (
    <div className="rounded-lg border border-border bg-card p-4 space-y-3">
      {/* Header */}
      <div className="flex items-center justify-between">
        <h3 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
          Workout Data
        </h3>
        <Badge variant="outline" className="text-[10px]">
          {sourceLabel}
        </Badge>
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
        {compliant != null && (
          <Badge
            variant="outline"
            className={
              compliant
                ? 'border-emerald-500/40 text-emerald-500 text-[10px]'
                : 'border-orange-500/40 text-orange-500 text-[10px]'
            }
          >
            {compliant ? `Z${prescribedZone} compliant` : `Zone compliance: off-target`}
          </Badge>
        )}
      </div>

      {/* HR Zone chart */}
      {(matched.heartRate.avg != null || matched.heartRate.max != null) && (
        <div>
          <p className="text-[10px] text-muted-foreground mb-1">Time in HR Zone</p>
          <HRZoneChart zones={zones} />
        </div>
      )}
    </div>
  )
}
