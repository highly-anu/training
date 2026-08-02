import Foundation
import SwiftUI

/// Pure computation engine for analytics. Safe for Task.detached — no @MainActor, no ObservableObject.
/// Mirrors frontend/src/lib/hrZones.ts and sessionAnalysis.ts.
enum AnalyticsEngine {

    // MARK: - Constants

    static let defaultZoneBoundaries: [Double] = [0.60, 0.70, 0.80, 0.90]
    static let banisterWeights: [Double] = [1.0, 1.5, 2.0, 3.0, 4.5]

    // MARK: - Max HR Resolution

    /// Priority: hrConfig.maxHROverride → 220-age from DOB → 190 default.
    static func effectiveMaxHR(hrConfig: HRConfig?, dateOfBirth: String?) -> Int {
        if let override = hrConfig?.maxHROverride, override > 0 { return override }
        if let dob = dateOfBirth {
            let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
            if let birth = fmt.date(from: dob) {
                let age = Calendar.current.dateComponents([.year], from: birth, to: Date()).year ?? 0
                if age > 0 { return 220 - age }
            }
        }
        return 190
    }

    // MARK: - Zone Assignment

    static func assignZone(_ bpm: Int, maxHR: Int, boundaries: [Double] = defaultZoneBoundaries) -> Int {
        guard maxHR > 0 else { return 0 }
        let pct = Double(bpm) / Double(maxHR)
        for (i, bound) in boundaries.enumerated() {
            if pct < bound { return i }
        }
        return 4
    }

    // MARK: - HR Zone Distribution

    static func computeHRZoneDistribution(
        samples: [HRSample],
        avgHR: Int?,
        maxHR workoutMax: Int?,
        hrConfig: HRConfig?,
        dateOfBirth: String? = nil
    ) -> HRZoneDistribution? {
        let maxHR = effectiveMaxHR(hrConfig: hrConfig, dateOfBirth: dateOfBirth)
        let boundaries = hrConfig?.zoneBoundaries ?? defaultZoneBoundaries

        if samples.count >= 2 {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let isoShort = ISO8601DateFormatter()

            let sorted = samples.compactMap { s -> (ts: TimeInterval, bpm: Int)? in
                let t = iso.date(from: s.timestamp)?.timeIntervalSince1970
                    ?? isoShort.date(from: s.timestamp)?.timeIntervalSince1970
                guard let t else { return nil }
                return (t, s.bpm)
            }.sorted { $0.ts < $1.ts }

            var zoneTimes = [Double](repeating: 0, count: 5)
            var total = 0.0
            for i in 0..<(sorted.count - 1) {
                let interval = min(sorted[i + 1].ts - sorted[i].ts, 60.0)
                guard interval > 0 else { continue }
                zoneTimes[assignZone(sorted[i].bpm, maxHR: maxHR, boundaries: boundaries)] += interval
                total += interval
            }
            if total > 0 {
                var pct = zoneTimes.map { Int(($0 / total * 100).rounded()) }
                let diff = 100 - pct.reduce(0, +)
                if let maxIdx = pct.indices.max(by: { pct[$0] < pct[$1] }) { pct[maxIdx] += diff }
                return HRZoneDistribution(z1: Double(pct[0]), z2: Double(pct[1]),
                                          z3: Double(pct[2]), z4: Double(pct[3]),
                                          z5: Double(pct[4]), method: "samples")
            }
        }

        guard let avg = avgHR else { return nil }
        let observedMax = workoutMax ?? Int(Double(avg) * 1.1)
        return estimateZonesFromSummary(maxHR: maxHR, avg: Double(avg),
                                        observedMax: Double(observedMax), boundaries: boundaries)
    }

    private static func normalCDF(_ x: Double, mean: Double, std: Double) -> Double {
        let z = (x - mean) / max(std, 1)
        let t = 1.0 / (1.0 + 0.3275911 * abs(z))
        let poly = t * (0.254829592 + t * (-0.284496736 + t * (1.421413741 + t * (-1.453152027 + t * 1.061405429))))
        let p = 1.0 - poly * exp(-z * z / 2.0)
        return z >= 0 ? p : 1.0 - p
    }

    private static func estimateZonesFromSummary(
        maxHR: Int, avg: Double, observedMax: Double, boundaries: [Double]
    ) -> HRZoneDistribution {
        let std = (observedMax - avg) / 2.5
        let bpmBounds = [0.0] + boundaries.map { $0 * Double(maxHR) } + [Double.infinity]
        var raw = [Double]()
        for i in 0..<5 {
            let lo = bpmBounds[i]; let hi = bpmBounds[i + 1]
            let pLo = lo == 0 ? 0.0 : normalCDF(lo, mean: avg, std: std)
            let pHi = hi == .infinity ? 1.0 : normalCDF(hi, mean: avg, std: std)
            raw.append(Swift.max(0, pHi - pLo))
        }
        let total = raw.reduce(0, +)
        guard total > 0 else {
            return HRZoneDistribution(z1: 100, z2: 0, z3: 0, z4: 0, z5: 0, method: "summary_estimate")
        }
        var pct = raw.map { Int(($0 / total * 100).rounded()) }
        let diff = 100 - pct.reduce(0, +)
        if let maxIdx = pct.indices.max(by: { pct[$0] < pct[$1] }) { pct[maxIdx] += diff }
        return HRZoneDistribution(z1: Double(pct[0]), z2: Double(pct[1]),
                                  z3: Double(pct[2]), z4: Double(pct[3]),
                                  z5: Double(pct[4]), method: "summary_estimate")
    }

    // MARK: - TRIMP

    static func computeTRIMP(zones: HRZoneDistribution, durationMinutes: Double) -> Int {
        let pcts = [zones.z1, zones.z2, zones.z3, zones.z4, zones.z5]
        let trimp = pcts.enumerated().reduce(0.0) { acc, pair in
            acc + (pair.element / 100.0) * durationMinutes * banisterWeights[pair.offset]
        }
        return Swift.max(0, Int(trimp.rounded()))
    }

    static func computeWorkoutTRIMP(workout: ImportedWorkout, hrConfig: HRConfig?, dateOfBirth: String? = nil) -> Int? {
        guard let dur = workout.durationMinutes, dur > 0 else { return nil }
        guard let zones = computeHRZoneDistribution(
            samples: workout.heartRate?.samples ?? [],
            avgHR: workout.heartRate?.avg, maxHR: workout.heartRate?.max,
            hrConfig: hrConfig, dateOfBirth: dateOfBirth
        ) else { return nil }
        return computeTRIMP(zones: zones, durationMinutes: dur)
    }

    // MARK: - Training Effect (Garmin-style)

    static func trainingEffect(trimp: Int, zones: HRZoneDistribution) -> TrainingEffect {
        let highBase     = zones.z1 + zones.z2
        let midRange     = zones.z2 + zones.z3
        let highAnaerobic = zones.z4 + zones.z5

        switch trimp {
        case ..<15: return .recovery
        case 15..<35: return highBase > 60 ? .baseDevelopment : .maintenance
        case 35..<60:
            if highAnaerobic > 40 { return .threshold }
            if midRange > 50      { return .aerobicCapacity }
            return .maintenance
        default: return highAnaerobic > 40 ? .highlyImpacting : .aerobicCapacity
        }
    }

    // MARK: - Recovery Time

    static func recoveryTimeHours(trimp: Int) -> Int {
        switch trimp {
        case ..<20:   return 8
        case 20..<40: return 12
        case 40..<70: return 18
        case 70..<100: return 24
        default:      return 36
        }
    }

    // MARK: - Aerobic Decoupling (Pa:HR drift)

    static func computeAerobicDecoupling(gpsTrack: [GPSPoint], hrSamples: [HRSample]) -> DecouplingResult? {
        let minPairsPerHalf = 10
        let speedThreshold = 0.3
        let matchWindowMs: Double = 10_000   // 10 seconds in ms

        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoShort = ISO8601DateFormatter()
        func parseTs(_ s: String) -> Double? {
            guard let date = iso.date(from: s) ?? isoShort.date(from: s) else { return nil }
            return date.timeIntervalSince1970 * 1000.0
        }

        let hrSorted = hrSamples.compactMap { s -> (ts: Double, bpm: Int)? in
            guard let ts = parseTs(s.timestamp) else { return nil }
            return (ts, s.bpm)
        }.sorted { $0.ts < $1.ts }

        guard !hrSorted.isEmpty else { return nil }

        var pairs: [(pace: Double, hr: Double)] = []
        for pt in gpsTrack {
            guard let speed = pt.speed, speed >= speedThreshold,
                  let ptTs = parseTs(pt.timestamp) else { continue }

            var lo = 0; var hi = hrSorted.count - 1
            while lo < hi { let mid = (lo + hi) / 2; hrSorted[mid].ts < ptTs ? (lo = mid + 1) : (hi = mid) }
            var nearest = hrSorted[lo]
            if lo > 0 && abs(hrSorted[lo - 1].ts - ptTs) < abs(nearest.ts - ptTs) { nearest = hrSorted[lo - 1] }
            guard abs(nearest.ts - ptTs) <= matchWindowMs else { continue }
            pairs.append((1000.0 / speed, Double(nearest.bpm)))
        }

        guard pairs.count >= minPairsPerHalf * 2 else { return nil }

        let mid = pairs.count / 2
        let mean: (ArraySlice<(pace: Double, hr: Double)>) -> (pace: Double, hr: Double) = { s in
            let n = Double(s.count)
            return (s.reduce(0) { $0 + $1.pace } / n, s.reduce(0) { $0 + $1.hr } / n)
        }
        let (p1, h1) = mean(pairs[..<mid])
        let (p2, h2) = mean(pairs[mid...])
        guard h1 > 0, h2 > 0 else { return nil }
        let r1 = p1 / h1; let r2 = p2 / h2
        guard r2 > 0 else { return nil }
        let pct = abs(r1 / r2 - 1.0) * 100.0

        if pct < 5  { return DecouplingResult(pct: pct, label: "efficient", color: .green) }
        if pct < 10 { return DecouplingResult(pct: pct, label: "moderate",  color: .orange) }
        return DecouplingResult(pct: pct, label: "high", color: .red)
    }

    // MARK: - Best Efforts (Strava-style)

    private static let effortTargets: [(label: String, km: Double)] = [
        ("1 km", 1.0), ("5 km", 5.0), ("10 km", 10.0)
    ]

    static func bestEfforts(gpsTrack: [GPSPoint], allWorkouts: [ImportedWorkout]) -> [BestEffort] {
        guard gpsTrack.count >= 10 else { return [] }

        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoShort = ISO8601DateFormatter()
        func parseTs(_ s: String) -> TimeInterval? {
            (iso.date(from: s) ?? isoShort.date(from: s))?.timeIntervalSince1970
        }

        struct Pt { var ts: TimeInterval; var speed: Double }
        let pts: [Pt] = gpsTrack.compactMap { p in
            guard let s = p.speed, s > 0.3, let t = parseTs(p.timestamp) else { return nil }
            return Pt(ts: t, speed: s)
        }.sorted { $0.ts < $1.ts }

        guard pts.count >= 10 else { return [] }

        // Build (cumulative distance metres, elapsed seconds from start)
        var cumDist: [(dist: Double, elapsed: Double)] = [(0, 0)]
        for i in 1..<pts.count {
            let dt = pts[i].ts - pts[i - 1].ts
            let dm = pts[i - 1].speed * dt
            cumDist.append((cumDist[i - 1].dist + dm, pts[i].ts - pts[0].ts))
        }
        let totalKm = (cumDist.last?.dist ?? 0) / 1000.0

        var results: [BestEffort] = []
        for target in effortTargets {
            let targetM = target.km * 1000.0
            guard totalKm >= target.km * 0.9 else { continue }

            var best: Double? = nil
            var lo = 0
            for hi in 1..<cumDist.count {
                while lo < hi && (cumDist[hi].dist - cumDist[lo].dist) > targetM { lo += 1 }
                let segDist = cumDist[hi].dist - cumDist[lo].dist
                if segDist >= targetM * 0.95 {
                    let elapsed = cumDist[hi].elapsed - cumDist[lo].elapsed
                    if elapsed > 0 { best = best.map { Swift.min($0, elapsed) } ?? elapsed }
                }
            }

            guard let secs = best else { continue }
            let secPerKm = secs / target.km
            let paceStr = String(format: "%d:%02d /km", Int(secPerKm) / 60, Int(secPerKm) % 60)

            let prBest = personalRecordBest(distanceKm: target.km, in: allWorkouts)
            let isPR: Bool
            if let prSecs = prBest {
                isPR = secs <= prSecs * 1.001  // within 0.1% — same or faster
            } else {
                isPR = true  // no prior data = first time = PR
            }
            results.append(BestEffort(label: target.label, timeSeconds: secs, paceStr: paceStr, isPersonalRecord: isPR))
        }
        return results
    }

    private static func personalRecordBest(distanceKm: Double, in workouts: [ImportedWorkout]) -> Double? {
        let targetM = distanceKm * 1000.0
        var best: Double? = nil
        for w in workouts {
            guard let dur = w.durationMinutes, dur > 0,
                  let distKm = w.distance?.value, distKm * 1000 >= targetM * 0.9 else { continue }
            let secPerKm = (dur * 60.0) / distKm
            let secs = secPerKm * distanceKm
            best = best.map { Swift.min($0, secs) } ?? secs
        }
        return best
    }

    // MARK: - Period Filtering

    static func filter(_ workouts: [ImportedWorkout], withinDays days: Int?) -> [ImportedWorkout] {
        guard let days else { return workouts }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return workouts.filter { (fmt.date(from: $0.date) ?? .distantPast) >= cutoff }
    }

    // MARK: - Period Stats (with prior period for trend arrows)

    static func periodStats(
        for current: [ImportedWorkout],
        period: AnalyticsPeriod,
        allWorkouts: [ImportedWorkout]
    ) -> WorkoutPeriodStats {
        var prior: [ImportedWorkout] = []
        if let days = period.days {
            let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
            let priorEnd   = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            let priorStart = Calendar.current.date(byAdding: .day, value: -days * 2, to: Date()) ?? Date()
            prior = allWorkouts.filter { w in
                guard let d = fmt.date(from: w.date) else { return false }
                return d >= priorStart && d < priorEnd
            }
        }
        func s(_ ws: [ImportedWorkout]) -> (n: Double, min: Double, km: Double, elev: Double, cal: Double) {
            (Double(ws.count),
             ws.compactMap(\.durationMinutes).reduce(0, +),
             ws.compactMap { $0.distance?.value }.reduce(0, +),
             ws.compactMap { $0.elevation?.gain }.reduce(0, +),
             ws.compactMap(\.calories).reduce(0, +))
        }
        let c = s(current); let p = s(prior)
        return WorkoutPeriodStats(
            sessions: c.n, totalMinutes: c.min,
            totalDistanceKm: c.km, totalElevationGainM: c.elev, totalCalories: c.cal,
            prevSessions: p.n, prevMinutes: p.min, prevDistanceKm: p.km
        )
    }

    // MARK: - Training Load Focus (Garmin — always last 28 days)

    static func trainingLoadFocus(workouts: [ImportedWorkout], hrConfig: HRConfig?, dateOfBirth: String? = nil) -> TrainingLoadFocus {
        let recent = filter(workouts, withinDays: 28)
        var base = 0.0; var threshold = 0.0; var anaerobic = 0.0
        for w in recent {
            guard let dur = w.durationMinutes, dur > 0,
                  let zones = computeHRZoneDistribution(
                      samples: w.heartRate?.samples ?? [],
                      avgHR: w.heartRate?.avg, maxHR: w.heartRate?.max,
                      hrConfig: hrConfig, dateOfBirth: dateOfBirth
                  ) else { continue }
            base      += (zones.z1 + zones.z2) / 100.0 * dur
            threshold += zones.z3 / 100.0 * dur
            anaerobic += (zones.z4 + zones.z5) / 100.0 * dur
        }
        return TrainingLoadFocus(baseMinutes: base, thresholdMinutes: threshold, anaerobicMinutes: anaerobic)
    }

    // MARK: - Weekly Consistency

    static func weeklyConsistency(allWorkouts: [ImportedWorkout]) -> [WeeklyConsistencyEntry] {
        let cal = Calendar.current
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let labelFmt = DateFormatter(); labelFmt.dateFormat = "MMM d"
        var entries: [WeeklyConsistencyEntry] = []
        for weekOffset in stride(from: -11, through: 0, by: 1) {
            guard let ref    = cal.date(byAdding: .weekOfYear, value: weekOffset, to: Date()),
                  let monday = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: ref)),
                  let end    = cal.date(byAdding: .day, value: 7, to: monday) else { continue }
            let count = allWorkouts.filter { w in
                guard let d = fmt.date(from: w.date) else { return false }
                return d >= monday && d < end
            }.count
            entries.append(WeeklyConsistencyEntry(weekLabel: labelFmt.string(from: monday),
                                                   sessionCount: count, weekStart: monday))
        }
        return entries
    }

    // MARK: - Modality Breakdown

    static func modalityBreakdown(workouts: [ImportedWorkout]) -> [ModalityShare] {
        let totalMin = workouts.compactMap(\.durationMinutes).reduce(0, +)
        guard totalMin > 0 else { return [] }
        var byModality: [String: Double] = [:]
        for w in workouts { byModality[w.inferredModalityId ?? "unknown", default: 0] += w.durationMinutes ?? 0 }
        return byModality.sorted { $0.value > $1.value }.prefix(8).map { key, min in
            ModalityShare(modalityId: key, label: ModalityStyle.label(for: key),
                          pct: Int((min / totalMin * 100).rounded()),
                          color: ModalityStyle.color(for: key))
        }
    }

    // MARK: - Activity Type Breakdown

    static func activityTypeBreakdown(workouts: [ImportedWorkout], topN: Int = 8) -> [ActivityTypeEntry] {
        var byType: [String: (hours: Double, count: Double)] = [:]
        for w in workouts {
            let key = w.activityType.replacingOccurrences(of: "_", with: " ").capitalized
            let h = (w.durationMinutes ?? 0) / 60.0
            let cur = byType[key] ?? (0, 0)
            byType[key] = (cur.hours + h, cur.count + 1)
        }
        let colors: [Color] = [.blue, .green, .orange, .purple, .cyan, .pink, .yellow, .indigo]
        return byType.sorted { $0.value.hours > $1.value.hours }.prefix(topN).enumerated().map { i, pair in
            ActivityTypeEntry(name: pair.key, hours: pair.value.hours,
                              sessions: pair.value.count, color: colors[i % colors.count])
        }
    }

    // MARK: - PMC (Performance Management Chart)

    static func computePMC(workouts: [ImportedWorkout], hrConfig: HRConfig?,
                            dateOfBirth: String? = nil, days: Int = 90) -> [PMCEntry] {
        let kCtl = 1.0 - exp(-1.0 / 42.0)
        let kAtl = 1.0 - exp(-1.0 / 7.0)
        let cal = Calendar.current
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let labelFmt = DateFormatter(); labelFmt.dateFormat = "MMM d"

        var trimpByDate: [String: Double] = [:]
        for w in workouts {
            if let t = computeWorkoutTRIMP(workout: w, hrConfig: hrConfig, dateOfBirth: dateOfBirth) {
                trimpByDate[w.date, default: 0] += Double(t)
            }
        }

        var entries: [PMCEntry] = []
        var ctl = 0.0; var atl = 0.0
        guard let start = cal.date(byAdding: .day, value: -days, to: Date()) else { return [] }
        for dayOffset in 0..<days {
            guard let date = cal.date(byAdding: .day, value: dayOffset, to: start) else { continue }
            let dateStr = fmt.string(from: date)
            let trimp = trimpByDate[dateStr] ?? 0.0
            ctl = ctl + kCtl * (trimp - ctl)
            atl = atl + kAtl * (trimp - atl)
            entries.append(PMCEntry(date: date, ctl: ctl, atl: atl, tsb: ctl - atl, trimp: trimp))
        }
        return entries
    }

    // MARK: - Weekly Load

    static func weeklyLoad(workouts: [ImportedWorkout], hrConfig: HRConfig?,
                            dateOfBirth: String? = nil, weeks: Int = 12) -> [WeeklyLoadEntry] {
        let cal = Calendar.current
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let labelFmt = DateFormatter(); labelFmt.dateFormat = "MMM d"
        var entries: [WeeklyLoadEntry] = []
        for weekOffset in stride(from: -(weeks - 1), through: 0, by: 1) {
            guard let ref    = cal.date(byAdding: .weekOfYear, value: weekOffset, to: Date()),
                  let monday = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: ref)),
                  let end    = cal.date(byAdding: .day, value: 7, to: monday) else { continue }
            let ww = workouts.filter { w in
                guard let d = fmt.date(from: w.date) else { return false }
                return d >= monday && d < end
            }
            let totalTrimp = ww.compactMap {
                computeWorkoutTRIMP(workout: $0, hrConfig: hrConfig, dateOfBirth: dateOfBirth)
            }.reduce(0, +)
            entries.append(WeeklyLoadEntry(week: labelFmt.string(from: monday),
                                           trimp: Double(totalTrimp), sessions: Double(ww.count)))
        }
        return entries
    }

    // MARK: - Aggregate Zone Minutes

    static func aggregateZoneMinutes(workouts: [ImportedWorkout], hrConfig: HRConfig?,
                                      dateOfBirth: String? = nil) -> HRZoneMinutes? {
        var totals = [Double](repeating: 0, count: 5)
        var any = false
        for w in workouts {
            guard let dur = w.durationMinutes, dur > 0,
                  let zones = computeHRZoneDistribution(
                      samples: w.heartRate?.samples ?? [],
                      avgHR: w.heartRate?.avg, maxHR: w.heartRate?.max,
                      hrConfig: hrConfig, dateOfBirth: dateOfBirth
                  ) else { continue }
            let pcts = [zones.z1, zones.z2, zones.z3, zones.z4, zones.z5]
            for i in 0..<5 { totals[i] += pcts[i] / 100.0 * dur }
            any = true
        }
        guard any else { return nil }
        return HRZoneMinutes(z1: totals[0], z2: totals[1], z3: totals[2], z4: totals[3], z5: totals[4])
    }
}

