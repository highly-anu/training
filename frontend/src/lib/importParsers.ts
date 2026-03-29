import type { ImportedWorkout, ModalityId } from '@/api/types'

// ── Activity type → ModalityId mapping ────────────────────────────────────────

const APPLE_HEALTH_MAP: Record<string, ModalityId> = {
  HKWorkoutActivityTypeRunning: 'aerobic_base',
  HKWorkoutActivityTypeCycling: 'aerobic_base',
  HKWorkoutActivityTypeSwimming: 'aerobic_base',
  HKWorkoutActivityTypeWalking: 'durability',
  HKWorkoutActivityTypeHiking: 'durability',
  HKWorkoutActivityTypeHighIntensityIntervalTraining: 'anaerobic_intervals',
  HKWorkoutActivityTypeCrossTraining: 'mixed_modal_conditioning',
  HKWorkoutActivityTypeTraditionalStrengthTraining: 'max_strength',
  HKWorkoutActivityTypeFunctionalStrengthTraining: 'strength_endurance',
  HKWorkoutActivityTypeCoreTraining: 'strength_endurance',
  HKWorkoutActivityTypeYoga: 'mobility',
  HKWorkoutActivityTypeFlexibility: 'mobility',
  HKWorkoutActivityTypeMartialArts: 'combat_sport',
  HKWorkoutActivityTypeBoxing: 'combat_sport',
  HKWorkoutActivityTypeWrestling: 'combat_sport',
  HKWorkoutActivityTypeRowingMachine: 'aerobic_base',
  HKWorkoutActivityTypeCrossCountrySkiing: 'aerobic_base',
  HKWorkoutActivityTypeElliptical: 'aerobic_base',
  HKWorkoutActivityTypeStairClimbing: 'durability',
}

const STRAVA_MAP: Record<string, ModalityId> = {
  Run: 'aerobic_base',
  TrailRun: 'aerobic_base',
  VirtualRun: 'aerobic_base',
  Ride: 'aerobic_base',
  VirtualRide: 'aerobic_base',
  Swim: 'aerobic_base',
  Walk: 'durability',
  Hike: 'durability',
  WeightTraining: 'max_strength',
  HIIT: 'anaerobic_intervals',
  Crossfit: 'mixed_modal_conditioning',
  Workout: 'mixed_modal_conditioning',
  Yoga: 'mobility',
  Rowing: 'aerobic_base',
  Kayaking: 'aerobic_base',
  MartialArts: 'combat_sport',
}

export function mapActivityType(
  rawType: string,
  source: 'apple_health' | 'strava'
): ModalityId | undefined {
  const map = source === 'apple_health' ? APPLE_HEALTH_MAP : STRAVA_MAP
  return map[rawType]
}

// ── Apple Health XML parser ────────────────────────────────────────────────────

function parseLocalDate(isoString: string): string {
  // Apple Health dates are like "2024-03-15 07:30:00 +0000"
  // We want YYYY-MM-DD in local calendar date
  const d = new Date(isoString)
  return d.toLocaleDateString('en-CA') // returns YYYY-MM-DD
}

function minutesBetween(start: string, end: string): number {
  return Math.round((new Date(end).getTime() - new Date(start).getTime()) / 60000)
}

export function parseAppleHealthXml(xmlText: string): ImportedWorkout[] {
  const parser = new DOMParser()
  const doc = parser.parseFromString(xmlText, 'text/xml')
  const workoutEls = Array.from(doc.querySelectorAll('Workout'))

  return workoutEls
    .map((el): ImportedWorkout | null => {
      const activityType = el.getAttribute('workoutActivityType') ?? ''
      const startDate = el.getAttribute('startDate') ?? ''
      const endDate = el.getAttribute('endDate') ?? ''
      if (!startDate || !endDate) return null

      // HR stats from WorkoutStatistics child element
      let hrAvg: number | undefined
      let hrMax: number | undefined
      let hrMin: number | undefined
      const statsEl = el.querySelector(
        'WorkoutStatistics[type="HKQuantityTypeIdentifierHeartRate"]'
      )
      if (statsEl) {
        const avg = statsEl.getAttribute('average')
        const max = statsEl.getAttribute('maximum')
        const min = statsEl.getAttribute('minimum')
        if (avg) hrAvg = parseFloat(avg)
        if (max) hrMax = parseFloat(max)
        if (min) hrMin = parseFloat(min)
      }

      // Energy
      let calories: number | undefined
      const energyEl = el.querySelector(
        'WorkoutStatistics[type="HKQuantityTypeIdentifierActiveEnergyBurned"]'
      )
      if (energyEl) {
        const sum = energyEl.getAttribute('sum')
        if (sum) calories = Math.round(parseFloat(sum))
      }

      // Distance
      let distance: ImportedWorkout['distance']
      const distEl = el.querySelector(
        'WorkoutStatistics[type="HKQuantityTypeIdentifierDistanceWalkingRunning"],' +
          'WorkoutStatistics[type="HKQuantityTypeIdentifierDistanceCycling"]'
      )
      if (distEl) {
        const sum = distEl.getAttribute('sum')
        const unit = distEl.getAttribute('unit') ?? ''
        if (sum) {
          const val = parseFloat(sum)
          distance = { value: val, unit: unit.toLowerCase().includes('km') ? 'km' : 'm' }
        }
      }

      return {
        id: crypto.randomUUID(),
        source: 'apple_health',
        date: parseLocalDate(startDate),
        startTime: startDate,
        endTime: endDate,
        durationMinutes: minutesBetween(startDate, endDate),
        activityType,
        inferredModalityId: mapActivityType(activityType, 'apple_health'),
        heartRate: { avg: hrAvg, max: hrMax, min: hrMin, samples: [] },
        calories,
        distance,
        rawData: {},
      }
    })
    .filter((w): w is ImportedWorkout => w !== null)
}

// ── Strava JSON parser ─────────────────────────────────────────────────────────

interface StravaActivity {
  id?: number
  name?: string
  start_date?: string
  elapsed_time?: number // seconds
  sport_type?: string
  type?: string // older field
  average_heartrate?: number
  max_heartrate?: number
  distance?: number // meters
  total_elevation_gain?: number
  kilojoules?: number
}

export function parseStravaJson(json: unknown): ImportedWorkout[] {
  const activities: StravaActivity[] = Array.isArray(json) ? json : []

  return activities
    .map((a): ImportedWorkout | null => {
      if (!a.start_date) return null
      const sportType = a.sport_type ?? a.type ?? 'Workout'
      const durationMinutes = Math.round((a.elapsed_time ?? 0) / 60)
      const startTime = a.start_date
      const endTime = new Date(
        new Date(a.start_date).getTime() + (a.elapsed_time ?? 0) * 1000
      ).toISOString()

      let distance: ImportedWorkout['distance']
      if (a.distance && a.distance > 0) {
        distance = { value: Math.round(a.distance) / 1000, unit: 'km' }
      }

      return {
        id: crypto.randomUUID(),
        source: 'strava',
        date: new Date(a.start_date).toLocaleDateString('en-CA'),
        startTime,
        endTime,
        durationMinutes,
        activityType: sportType,
        inferredModalityId: mapActivityType(sportType, 'strava'),
        heartRate: {
          avg: a.average_heartrate,
          max: a.max_heartrate,
          samples: [],
        },
        calories: a.kilojoules ? Math.round(a.kilojoules * 0.239) : undefined,
        distance,
        rawData: {},
      }
    })
    .filter((w): w is ImportedWorkout => w !== null)
}
