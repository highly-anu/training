/**
 * Session analysis engine — compares prescribed sessions to actual workout data
 * and produces actionable insights. Pure functions, no store access.
 */
import type {
  Session,
  ImportedWorkout,
  SessionPerformanceLog,
  ModalityId,
  InsightItem,
  SessionInsight,
  WeekInsightSummary,
  WeekData,
  DevelopmentTrend,
  HRSample,
} from '@/api/types'
import { computeHRZones, parseZoneTarget, isZoneCompliant } from '@/lib/hrZones'

// ── Modality family classification ───────────────────────────────────────────

const STRENGTH: ModalityId[] = ['max_strength', 'relative_strength', 'strength_endurance', 'power']
const CARDIO: ModalityId[] = ['aerobic_base']
const INTERVALS: ModalityId[] = ['anaerobic_intervals', 'mixed_modal_conditioning']
const SKILL: ModalityId[] = ['movement_skill', 'mobility', 'rehab']

type ModalityFamily = 'strength' | 'aerobic' | 'intervals' | 'distance' | 'mobility' | 'other'

function modalityFamily(mod: ModalityId): ModalityFamily {
  if (STRENGTH.includes(mod)) return 'strength'
  if (CARDIO.includes(mod)) return 'aerobic'
  if (INTERVALS.includes(mod)) return 'intervals'
  if (mod === 'durability') return 'distance'
  if (SKILL.includes(mod)) return 'mobility'
  return 'other'
}

// ── Helpers ──────────────────────────────────────────────────────────────────

function pctDelta(prescribed: number, actual: number): number {
  if (prescribed <= 0) return 0
  return Math.abs(actual - prescribed) / prescribed
}

function avgBpm(samples: HRSample[]): number {
  if (samples.length === 0) return 0
  return samples.reduce((s, h) => s + h.bpm, 0) / samples.length
}

function thirdAvgs(samples: HRSample[]): { first: number; last: number } | null {
  if (samples.length < 9) return null
  const third = Math.floor(samples.length / 3)
  return {
    first: avgBpm(samples.slice(0, third)),
    last: avgBpm(samples.slice(-third)),
  }
}

function parseReps(reps: number | string | undefined): number | null {
  if (reps == null) return null
  if (typeof reps === 'number') return reps
  // Handle range like "8-10" → take lower bound
  const m = reps.match(/^(\d+)/)
  return m ? parseInt(m[1], 10) : null
}

// ── Per-type analyzers ───────────────────────────────────────────────────────

function analyzeAerobic(
  sessions: Session[],
  workout: ImportedWorkout,
  maxHR: number,
): InsightItem[] {
  const insights: InsightItem[] = []

  // Prescribed duration
  const prescribedMin = sessions.reduce((sum, s) => {
    const dur = s.exercises.reduce((d, e) => d + (e.load.duration_minutes ?? 0), 0)
    return sum + (dur || s.duration_min || s.archetype.duration_estimate_minutes || 0)
  }, 0)

  if (prescribedMin > 0) {
    const delta = pctDelta(prescribedMin, workout.durationMinutes)
    const severity = delta <= 0.1 ? 'positive' : delta <= 0.25 ? 'neutral' : 'warning'
    insights.push({
      key: 'duration_delta',
      label: 'Duration',
      detail:
        severity === 'positive'
          ? 'Session duration matched the prescription.'
          : severity === 'neutral'
            ? 'Duration was slightly off from the prescribed target.'
            : `Duration deviated significantly from the ${prescribedMin} min target.`,
      severity,
      metric: { prescribed: `${prescribedMin}`, actual: `${workout.durationMinutes}`, unit: 'min' },
    })
  }

  // Zone compliance
  const samples = workout.heartRate.samples ?? []
  const zoneTargets = sessions.flatMap((s) =>
    s.exercises.map((e) => e.load.zone_target).filter((zt): zt is string => Boolean(zt)),
  )
  const prescribedZone = zoneTargets.length > 0 ? parseZoneTarget(zoneTargets[0]) : null
  const zones = computeHRZones(maxHR, samples, workout.heartRate.avg ?? undefined)

  if (prescribedZone != null) {
    const compliant = isZoneCompliant(zones, prescribedZone)
    const zoneKey = `z${prescribedZone}` as keyof typeof zones
    const actualPct = typeof zones[zoneKey] === 'number' ? zones[zoneKey] as number : 0
    const aboveZones = Array.from({ length: 5 - prescribedZone }, (_, i) => {
      const z = prescribedZone + 1 + i
      const k = `z${z}` as keyof typeof zones
      return typeof zones[k] === 'number' ? zones[k] as number : 0
    }).reduce((a, b) => a + b, 0)
    const belowZones = Array.from({ length: prescribedZone - 1 }, (_, i) => {
      const z = i + 1
      const k = `z${z}` as keyof typeof zones
      return typeof zones[k] === 'number' ? zones[k] as number : 0
    }).reduce((a, b) => a + b, 0)

    let detail: string
    if (compliant) {
      detail = `${actualPct}% of time in Zone ${prescribedZone} — on target.`
    } else if (aboveZones > actualPct) {
      detail = `Only ${actualPct}% in Z${prescribedZone}, but ${aboveZones}% in higher zones — session was harder than prescribed.`
    } else if (belowZones > actualPct) {
      detail = `Only ${actualPct}% in Z${prescribedZone}, with ${belowZones}% in lower zones — session was easier than prescribed.`
    } else {
      detail = `${actualPct}% in Z${prescribedZone} (target ≥50%) — time was spread across zones.`
    }

    insights.push({
      key: 'zone_compliance',
      label: `Zone ${prescribedZone} Compliance`,
      detail,
      severity: compliant ? 'positive' : 'warning',
      metric: { prescribed: `≥50% Z${prescribedZone}`, actual: `${actualPct}%`, unit: `Z${prescribedZone}` },
    })
  }

  // Zone distribution — always show when HR data is available
  if (workout.heartRate.avg != null) {
    const z12 = zones.z1 + zones.z2
    const z3 = zones.z3
    const z45 = zones.z4 + zones.z5

    // For aerobic base work, majority should be in Z1-Z2
    const isAerobicCompliant = z12 >= 70
    const zoneParts = [
      zones.z1 > 0 ? `Z1 ${zones.z1}%` : '',
      zones.z2 > 0 ? `Z2 ${zones.z2}%` : '',
      zones.z3 > 0 ? `Z3 ${zones.z3}%` : '',
      zones.z4 > 0 ? `Z4 ${zones.z4}%` : '',
      zones.z5 > 0 ? `Z5 ${zones.z5}%` : '',
    ].filter(Boolean).join(', ')

    if (!prescribedZone) {
      // No explicit zone target — evaluate based on aerobic base principles
      insights.push({
        key: 'zone_distribution',
        label: 'HR Zone Distribution',
        detail: isAerobicCompliant
          ? `${z12}% of time in Z1-Z2 — good aerobic base effort. ${zoneParts}`
          : z45 > 20
            ? `${z45}% of time in Z4-Z5 — session was more intense than typical aerobic base work. ${zoneParts}`
            : `${z3}% of time in Z3 — session sat in the moderate zone. ${zoneParts}`,
        severity: isAerobicCompliant ? 'positive' : z45 > 30 ? 'warning' : 'neutral',
      })
    } else {
      // Already showed zone compliance above — add distribution as supplementary info
      insights.push({
        key: 'zone_distribution',
        label: 'Zone Breakdown',
        detail: zoneParts,
        severity: 'neutral',
      })
    }
  }

  // Zone drift (cardiac drift detection)
  if (samples.length >= 9) {
    const thirds = thirdAvgs(samples)
    if (thirds) {
      const drift = (thirds.last - thirds.first) / thirds.first
      if (drift > 0.05) {
        insights.push({
          key: 'zone_drift',
          label: 'Cardiac Drift',
          detail: `HR rose ${Math.round(drift * 100)}% from start to end at steady effort — pace may have been too aggressive for the target zone.`,
          severity: 'warning',
          metric: { prescribed: `${Math.round(thirds.first)}`, actual: `${Math.round(thirds.last)}`, unit: 'bpm' },
        })
      }
    }
  }

  // Pace insight for running/cycling
  if (workout.distance && workout.durationMinutes > 0) {
    const km = workout.distance.unit === 'km' ? workout.distance.value : workout.distance.value / 1000
    if (km > 0) {
      const paceMin = workout.durationMinutes / km
      const pMins = Math.floor(paceMin)
      const pSecs = Math.round((paceMin - pMins) * 60)
      insights.push({
        key: 'pace',
        label: 'Avg Pace',
        detail: `${pMins}:${pSecs.toString().padStart(2, '0')} /km over ${km.toFixed(1)} km`,
        severity: 'neutral',
        metric: { prescribed: '', actual: `${pMins}:${pSecs.toString().padStart(2, '0')}`, unit: '/km' },
      })
    }
  }

  // Elevation insight
  if (workout.elevation && workout.elevation.gain > 50) {
    insights.push({
      key: 'elevation',
      label: 'Elevation',
      detail: `+${workout.elevation.gain}m / -${workout.elevation.loss}m — hilly terrain affects HR and pace.`,
      severity: 'neutral',
    })
  }

  return insights
}

function analyzeStrength(
  sessions: Session[],
  workout: ImportedWorkout,
  perfLog: SessionPerformanceLog | undefined,
): InsightItem[] {
  const insights: InsightItem[] = []

  if (!perfLog || Object.keys(perfLog.exercises).length === 0) {
    insights.push({
      key: 'no_perf_data',
      label: 'No Logged Data',
      detail: 'Log your sets and weights in the session to get detailed strength insights.',
      severity: 'neutral',
    })
    // Still provide HR info if available
    if (workout.heartRate.avg != null) {
      insights.push({
        key: 'hr_during_strength',
        label: 'Session HR',
        detail: `Average heart rate was ${Math.round(workout.heartRate.avg)} bpm during this strength session.`,
        severity: 'neutral',
      })
    }
    return insights
  }

  // Aggregate prescribed vs actual across all exercises
  let totalPrescribedReps = 0
  let totalActualReps = 0
  let totalPrescribedSets = 0
  let totalCompletedSets = 0
  const loadDeltas: { name: string; prescribed: number; actual: number }[] = []
  const rpeDeltas: { name: string; target: number; actual: number }[] = []

  for (const session of sessions) {
    for (const ea of session.exercises) {
      if (ea.meta) continue
      const exId = ea.exercise.id
      const logged = perfLog.exercises[exId]
      const prescribedSets = ea.load.sets ?? 0
      const prescribedReps = parseReps(ea.load.reps) ?? 0

      totalPrescribedSets += prescribedSets
      totalPrescribedReps += prescribedSets * prescribedReps

      if (logged) {
        const completedSets = logged.sets.filter((s) => s.completed).length
        const actualReps = logged.sets.reduce((sum, s) => sum + (s.repsActual ?? 0), 0)
        totalCompletedSets += completedSets
        totalActualReps += actualReps

        // Load comparison
        if (ea.load.weight_kg != null) {
          const maxLogged = Math.max(...logged.sets.filter((s) => s.weightKg != null).map((s) => s.weightKg!), 0)
          if (maxLogged > 0) {
            loadDeltas.push({ name: ea.exercise.name, prescribed: ea.load.weight_kg, actual: maxLogged })
          }
        }

        // RPE comparison
        if (ea.load.target_rpe != null && logged.rpe != null) {
          rpeDeltas.push({ name: ea.exercise.name, target: ea.load.target_rpe, actual: logged.rpe })
        }
      }
    }
  }

  // Set completion
  if (totalPrescribedSets > 0) {
    const ratio = totalCompletedSets / totalPrescribedSets
    insights.push({
      key: 'set_completion',
      label: 'Set Completion',
      detail:
        ratio >= 1
          ? 'All prescribed sets completed.'
          : ratio >= 0.8
            ? `Completed ${totalCompletedSets}/${totalPrescribedSets} sets — most of the session done.`
            : `Only ${totalCompletedSets}/${totalPrescribedSets} sets completed — session cut short.`,
      severity: ratio >= 0.8 ? 'positive' : 'warning',
      metric: { prescribed: `${totalPrescribedSets}`, actual: `${totalCompletedSets}`, unit: 'sets' },
    })
  }

  // Volume compliance
  if (totalPrescribedReps > 0 && totalActualReps > 0) {
    const ratio = totalActualReps / totalPrescribedReps
    insights.push({
      key: 'volume_compliance',
      label: 'Volume',
      detail:
        ratio >= 0.9
          ? 'Total reps completed as prescribed.'
          : `Completed ${totalActualReps} of ${totalPrescribedReps} prescribed reps.`,
      severity: ratio >= 0.9 ? 'positive' : ratio >= 0.7 ? 'neutral' : 'warning',
      metric: { prescribed: `${totalPrescribedReps}`, actual: `${totalActualReps}`, unit: 'reps' },
    })
  }

  // Load compliance (summarize across exercises)
  for (const ld of loadDeltas) {
    const ratio = ld.actual / ld.prescribed
    if (ratio > 1.1) {
      insights.push({
        key: `load_${ld.name}`,
        label: `${ld.name} Load`,
        detail: `Exceeded prescribed load — strong session.`,
        severity: 'positive',
        metric: { prescribed: `${ld.prescribed}`, actual: `${ld.actual}`, unit: 'kg' },
      })
    } else if (ratio < 0.9) {
      insights.push({
        key: `load_${ld.name}`,
        label: `${ld.name} Load`,
        detail: `Loaded lighter than prescribed — check if recovery is adequate.`,
        severity: 'warning',
        metric: { prescribed: `${ld.prescribed}`, actual: `${ld.actual}`, unit: 'kg' },
      })
    }
  }

  // RPE delta
  for (const rd of rpeDeltas) {
    const delta = rd.actual - rd.target
    if (delta >= 2) {
      insights.push({
        key: `rpe_${rd.name}`,
        label: `${rd.name} RPE`,
        detail: `Felt harder than intended (RPE ${rd.actual} vs target ${rd.target}) — consider if recovery is adequate.`,
        severity: 'warning',
      })
    } else if (delta <= -2 && loadDeltas.some((ld) => ld.name === rd.name && ld.actual >= ld.prescribed * 0.9)) {
      insights.push({
        key: `rpe_${rd.name}`,
        label: `${rd.name} RPE`,
        detail: `Load felt easy (RPE ${rd.actual} vs target ${rd.target}) at prescribed weight — ready for progression.`,
        severity: 'positive',
      })
    }
  }

  // HR during strength
  if (workout.heartRate.avg != null) {
    insights.push({
      key: 'hr_during_strength',
      label: 'Session HR',
      detail: `Average HR ${Math.round(workout.heartRate.avg)} bpm${workout.heartRate.max != null ? `, peak ${Math.round(workout.heartRate.max)} bpm` : ''}.`,
      severity: 'neutral',
    })
  }

  return insights
}

function analyzeIntervals(
  sessions: Session[],
  workout: ImportedWorkout,
  maxHR: number,
): InsightItem[] {
  const insights: InsightItem[] = []

  // Duration match
  const prescribedMin = sessions.reduce((sum, s) => {
    const tm = s.exercises.reduce((d, e) => d + (e.load.time_minutes ?? 0), 0)
    return sum + (tm || s.duration_min || s.archetype.duration_estimate_minutes || 0)
  }, 0)

  if (prescribedMin > 0) {
    const delta = pctDelta(prescribedMin, workout.durationMinutes)
    insights.push({
      key: 'duration_match',
      label: 'Duration',
      detail:
        delta <= 0.15
          ? 'Session duration matched the prescribed time cap.'
          : `Duration was ${Math.round(delta * 100)}% off from the ${prescribedMin} min target.`,
      severity: delta <= 0.15 ? 'positive' : delta <= 0.3 ? 'neutral' : 'warning',
      metric: { prescribed: `${prescribedMin}`, actual: `${workout.durationMinutes}`, unit: 'min' },
    })
  }

  // HR intensity — intervals should spend meaningful time in Z4-Z5
  const samples = workout.heartRate.samples ?? []
  const zones = computeHRZones(maxHR, samples, workout.heartRate.avg ?? undefined)
  const highZonePct = zones.z4 + zones.z5

  if (workout.heartRate.avg != null) {
    if (highZonePct < 30) {
      insights.push({
        key: 'hr_intensity',
        label: 'Intensity',
        detail: `Only ${highZonePct}% of time in Z4-Z5 — intensity may have been too low for interval work.`,
        severity: 'warning',
      })
    } else if (zones.z5 > 60) {
      insights.push({
        key: 'hr_intensity',
        label: 'Intensity',
        detail: `${zones.z5}% of session in Z5 — very high intensity. Ensure adequate recovery before the next hard session.`,
        severity: 'warning',
      })
    } else {
      insights.push({
        key: 'hr_intensity',
        label: 'Intensity',
        detail: `${highZonePct}% of time in Z4-Z5 — good intensity for interval work.`,
        severity: 'positive',
      })
    }
  }

  return insights
}

function analyzeDistance(
  sessions: Session[],
  workout: ImportedWorkout,
): InsightItem[] {
  const insights: InsightItem[] = []

  // Find prescribed distance
  let prescribedKm = 0
  for (const s of sessions) {
    for (const e of s.exercises) {
      if (e.load.distance_km) prescribedKm += e.load.distance_km
      if (e.load.distance_m) prescribedKm += e.load.distance_m / 1000
    }
  }

  if (prescribedKm > 0 && workout.distance) {
    const actualKm = workout.distance.unit === 'km' ? workout.distance.value : workout.distance.value / 1000
    const delta = pctDelta(prescribedKm, actualKm)
    insights.push({
      key: 'distance_delta',
      label: 'Distance',
      detail:
        delta <= 0.1
          ? 'Distance covered matched the prescription.'
          : `Distance was ${actualKm > prescribedKm ? 'over' : 'under'} by ${Math.round(delta * 100)}%.`,
      severity: delta <= 0.1 ? 'positive' : delta <= 0.25 ? 'neutral' : 'warning',
      metric: { prescribed: `${prescribedKm.toFixed(1)}`, actual: `${actualKm.toFixed(1)}`, unit: 'km' },
    })

    // Pace
    if (workout.durationMinutes > 0 && actualKm > 0) {
      const pace = workout.durationMinutes / actualKm
      const pMins = Math.floor(pace)
      const pSecs = Math.round((pace - pMins) * 60)
      insights.push({
        key: 'pace',
        label: 'Pace',
        detail: `Average pace was ${pMins}:${pSecs.toString().padStart(2, '0')} /km.`,
        severity: 'neutral',
      })
    }
  }

  // Duration fallback if no distance prescribed
  const prescribedMin = sessions.reduce(
    (sum, s) => sum + (s.duration_min || s.archetype.duration_estimate_minutes || 0), 0,
  )
  if (prescribedKm === 0 && prescribedMin > 0) {
    const delta = pctDelta(prescribedMin, workout.durationMinutes)
    insights.push({
      key: 'duration_delta',
      label: 'Duration',
      detail: delta <= 0.15 ? 'Duration matched.' : `Duration was ${Math.round(delta * 100)}% off target.`,
      severity: delta <= 0.15 ? 'positive' : delta <= 0.3 ? 'neutral' : 'warning',
      metric: { prescribed: `${prescribedMin}`, actual: `${workout.durationMinutes}`, unit: 'min' },
    })
  }

  return insights
}

function analyzeMobility(
  sessions: Session[],
  workout: ImportedWorkout,
): InsightItem[] {
  const insights: InsightItem[] = []

  const prescribedMin = sessions.reduce(
    (sum, s) => sum + (s.duration_min || s.archetype.duration_estimate_minutes || 0), 0,
  )

  if (prescribedMin > 0) {
    const ratio = workout.durationMinutes / prescribedMin
    insights.push({
      key: 'duration_compliance',
      label: 'Duration',
      detail:
        ratio >= 0.8
          ? 'Mobility session completed at or near full duration.'
          : ratio >= 0.5
            ? 'Session was shorter than prescribed — some benefit, but aim for the full duration.'
            : 'Session was significantly cut short.',
      severity: ratio >= 0.8 ? 'positive' : ratio >= 0.5 ? 'neutral' : 'warning',
      metric: { prescribed: `${prescribedMin}`, actual: `${workout.durationMinutes}`, unit: 'min' },
    })
  }

  return insights
}

// ── Compliance scoring ───────────────────────────────────────────────────────

function scoreInsights(insights: InsightItem[]): number {
  if (insights.length === 0) return 50
  const weights = { positive: 100, neutral: 60, warning: 20 }
  const total = insights.reduce((sum, i) => sum + weights[i.severity], 0)
  return Math.round(total / insights.length)
}

// ── Main entry point ─────────────────────────────────────────────────────────

export function computeSessionInsight(
  sessions: Session[],
  workout: ImportedWorkout,
  perfLog: SessionPerformanceLog | undefined,
  maxHR: number,
  sessionKey: string = '',
): SessionInsight {
  const family = modalityFamily(sessions[0]?.modality ?? 'aerobic_base')

  let insights: InsightItem[]
  switch (family) {
    case 'aerobic':
      insights = analyzeAerobic(sessions, workout, maxHR)
      break
    case 'strength':
      insights = analyzeStrength(sessions, workout, perfLog)
      break
    case 'intervals':
      insights = analyzeIntervals(sessions, workout, maxHR)
      break
    case 'distance':
      insights = analyzeDistance(sessions, workout)
      break
    case 'mobility':
      insights = analyzeMobility(sessions, workout)
      break
    default:
      insights = analyzeMobility(sessions, workout) // fallback to duration check
  }

  const complianceScore = scoreInsights(insights)
  const status = complianceScore >= 70 ? 'green' : complianceScore >= 45 ? 'yellow' : 'red'

  return { sessionKey, complianceScore, status, insights }
}

// ── Week-level aggregation ───────────────────────────────────────────────────

export function computeWeekInsights(
  weekData: WeekData,
  sessionInsights: SessionInsight[],
): WeekInsightSummary {
  // Count total sessions in the week
  let sessionsTotal = 0
  for (const day of Object.values(weekData.schedule)) {
    sessionsTotal += day.length
  }

  const matched = sessionInsights.length
  const avgCompliance =
    matched > 0
      ? Math.round(sessionInsights.reduce((s, i) => s + i.complianceScore, 0) / matched)
      : 0

  // Collect warning flags, deduplicate by key, sort by frequency
  const flagCounts = new Map<string, { item: InsightItem; count: number }>()
  for (const si of sessionInsights) {
    for (const item of si.insights) {
      if (item.severity === 'warning') {
        const existing = flagCounts.get(item.key)
        if (existing) existing.count++
        else flagCounts.set(item.key, { item, count: 1 })
      }
    }
  }
  const topFlags = [...flagCounts.values()]
    .sort((a, b) => b.count - a.count)
    .slice(0, 3)
    .map((f) => f.item)

  const status = avgCompliance >= 70 ? 'green' : avgCompliance >= 45 ? 'yellow' : 'red'

  return {
    weekNumber: weekData.week_number,
    sessionsMatched: matched,
    sessionsTotal,
    avgCompliance,
    status,
    topFlags,
  }
}

// ── Development trends ───────────────────────────────────────────────────────

function trendDirection(points: number[]): 'improving' | 'stable' | 'declining' {
  if (points.length < 3) return 'stable'
  const third = Math.ceil(points.length / 3)
  const firstAvg = points.slice(0, third).reduce((a, b) => a + b, 0) / third
  const lastAvg = points.slice(-third).reduce((a, b) => a + b, 0) / third
  const delta = (lastAvg - firstAvg) / (Math.abs(firstAvg) || 1)
  if (delta > 0.05) return 'improving'
  if (delta < -0.05) return 'declining'
  return 'stable'
}

export function computeDevelopmentTrends(
  weekInsights: WeekInsightSummary[],
  allInsights: SessionInsight[],
  allWorkouts: ImportedWorkout[],
  weekDataMap: Map<number, WeekData>,
): DevelopmentTrend[] {
  const trends: DevelopmentTrend[] = []

  // 1. Weekly compliance trend
  const compliancePoints = weekInsights
    .filter((w) => w.sessionsMatched > 0)
    .map((w) => ({ weekNumber: w.weekNumber, value: w.avgCompliance }))

  if (compliancePoints.length >= 2) {
    const dir = trendDirection(compliancePoints.map((p) => p.value))
    trends.push({
      metric: 'compliance',
      label: 'Session Compliance',
      dataPoints: compliancePoints,
      direction: dir,
      detail:
        dir === 'improving'
          ? 'Compliance is improving — sessions are aligning closer to the program.'
          : dir === 'declining'
            ? 'Compliance is trending down — review if the program matches your capacity.'
            : 'Compliance has been steady.',
    })
  }

  // 2. Session completion rate
  const completionPoints = weekInsights
    .filter((w) => w.sessionsTotal > 0)
    .map((w) => ({
      weekNumber: w.weekNumber,
      value: Math.round((w.sessionsMatched / w.sessionsTotal) * 100),
    }))

  if (completionPoints.length >= 2) {
    const dir = trendDirection(completionPoints.map((p) => p.value))
    trends.push({
      metric: 'completion',
      label: 'Session Tracking',
      dataPoints: completionPoints,
      direction: dir,
      detail:
        dir === 'improving'
          ? 'You\'re tracking more of your sessions each week.'
          : dir === 'declining'
            ? 'Fewer sessions are being tracked — keep importing workouts to get better insights.'
            : 'Session tracking rate has been consistent.',
    })
  }

  // 3. Aerobic efficiency — avg HR at zone 2 over time
  const z2Sessions: { weekNumber: number; avgHR: number }[] = []
  for (const si of allInsights) {
    const zoneInsight = si.insights.find((i) => i.key === 'zone_compliance' && i.severity === 'positive')
    if (!zoneInsight) continue
    // Find the workout for this session
    const wk = allWorkouts.find((w) => {
      // Match via sessionKey — we need the workout that was matched to this session
      return si.sessionKey && w.heartRate.avg != null
    })
    if (!wk || wk.heartRate.avg == null) continue
    const weekNum = parseInt(si.sessionKey.split('-')[0], 10)
    if (!isNaN(weekNum)) {
      z2Sessions.push({ weekNumber: weekNum, avgHR: wk.heartRate.avg })
    }
  }

  if (z2Sessions.length >= 3) {
    // Average per week
    const byWeek = new Map<number, number[]>()
    for (const s of z2Sessions) {
      const arr = byWeek.get(s.weekNumber) ?? []
      arr.push(s.avgHR)
      byWeek.set(s.weekNumber, arr)
    }
    const points = [...byWeek.entries()]
      .sort(([a], [b]) => a - b)
      .map(([weekNumber, hrs]) => ({
        weekNumber,
        value: Math.round(hrs.reduce((a, b) => a + b, 0) / hrs.length),
      }))

    if (points.length >= 3) {
      // For HR, "improving" means HR is going DOWN
      const rawDir = trendDirection(points.map((p) => p.value))
      const dir = rawDir === 'improving' ? 'declining' : rawDir === 'declining' ? 'improving' : 'stable'
      trends.push({
        metric: 'aerobic_efficiency',
        label: 'Aerobic Efficiency',
        dataPoints: points,
        direction: dir,
        detail:
          dir === 'improving'
            ? `HR at Zone 2 effort is dropping — aerobic fitness is improving.`
            : dir === 'declining'
              ? 'HR at Zone 2 effort is rising — may indicate fatigue or detraining.'
              : 'Aerobic efficiency has been stable.',
      })
    }
  }

  return trends
}
