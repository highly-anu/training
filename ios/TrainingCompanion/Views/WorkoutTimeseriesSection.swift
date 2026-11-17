import SwiftUI

/// The recorded shape of a workout: where it went, and what the sensors saw.
///
/// Two screens drew this independently — `WorkoutDetailView` and
/// `SessionLogDetailView` — and had already drifted: only one offered the Swiss
/// 3D toggle, and they disagreed on how many GPS points make a pace chart (10
/// vs 1). See §6.10 of `ios/docs/design-system.md`.

// MARK: - Route

/// The map. Renders nothing at all when there is no track, rather than an empty
/// grey rectangle.
/// Whether a recorded track is a route worth a map: at least two real fixes
/// (inside the valid range, not the 0,0 a device writes without a fix) that
/// spread over more than `minimumSpanMeters`. An indoor or gym session on a
/// watch can carry a handful of points in one spot; drawn, that is a map of
/// the gym, not where the workout went. The Workout complete sheet and the
/// workout detail both ask this.
enum WorkoutRoute {
    static let minimumSpanMeters = 50.0

    static func fixes(_ points: [GPSPoint]) -> [GPSPoint] {
        points.filter { p in
            abs(p.lat) <= 90 && abs(p.lng) <= 180 && !(p.lat == 0 && p.lng == 0)
        }
    }

    static func hasRoute(_ points: [GPSPoint]) -> Bool {
        let real = fixes(points)
        guard real.count >= 2,
              let minLat = real.map(\.lat).min(), let maxLat = real.map(\.lat).max(),
              let minLng = real.map(\.lng).min(), let maxLng = real.map(\.lng).max()
        else { return false }
        // Equirectangular diagonal of the bounding box — plenty for "did it move".
        let midLat = (minLat + maxLat) / 2 * .pi / 180
        let dy = (maxLat - minLat) * 111_320
        let dx = (maxLng - minLng) * 111_320 * cos(midLat)
        return (dx * dx + dy * dy).squareRoot() > minimumSpanMeters
    }
}

struct WorkoutRouteSection: View {
    let points: [GPSPoint]

    private enum MapMode { case flat, swiss3d }
    @State private var mapMode: MapMode = .flat

    var body: some View {
        if WorkoutRoute.hasRoute(points) {
            Section("Route") {
                if isInSwitzerland(points) {
                    Picker("View", selection: $mapMode) {
                        Label("Map", systemImage: "map").tag(MapMode.flat)
                        Label("3D", systemImage: "cube").tag(MapMode.swiss3d)
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 0, trailing: 8))
                    .onChange(of: mapMode) { AppHaptics.selection() }
                }

                Group {
                    if mapMode == .swiss3d && isInSwitzerland(points) {
                        Swiss3DMapView(points: points)
                            .frame(height: 300)
                    } else {
                        WorkoutRouteMapView(points: points)
                            .frame(height: 220)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: AppMetrics.radiusControl))
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 8, trailing: 8))
            }
        }
    }
}

// MARK: - Charts

/// HR, elevation and pace over the workout, with a selector when more than one
/// has data, and one scrubber for all three: drag across any of them and the
/// line above reads the moment — time, heart rate, pace, altitude — and stays
/// there when the chart is switched (since 1.39; no chart could be read before).
///
/// The selection is a `ChartKind?` derived from what is actually available, not
/// an `Int` defaulting to 0. The old form let the view select a chart that did
/// not exist — a workout with elevation but no HR reserved 160pt and drew
/// nothing — and that bug had already been copied into a second screen. Here it
/// cannot be expressed.
struct WorkoutChartsSection: View {
    let gpsTrack: [GPSPoint]?
    let hrSamples: [HRSample]
    let avgHR: Int?
    let maxHR: Int?
    let elevationGain: Double?
    let distanceKm: Double?
    let hrConfig: HRConfig?

    @State private var selected: ChartKind?
    /// Seconds from the start under the finger; nil when nothing is touched.
    @State private var scrub: Double?
    @State private var series = WorkoutScrub.Series()

    enum ChartKind: String, Hashable {
        case hr, elevation, pace

        var label: String {
            switch self {
            case .hr:        return "HR"
            case .elevation: return "Elevation"
            case .pace:      return "Pace"
            }
        }

        var icon: String {
            switch self {
            case .hr:        return "heart.fill"
            case .elevation: return "mountain.2.fill"
            case .pace:      return "figure.run"
            }
        }
    }

    /// Enough points to draw a line, not a dot. The two screens disagreed on
    /// this (10 vs 1); 10 is the threshold `PaceTimelineView` was written for.
    private static let minimumPacePoints = 10

    private var available: [ChartKind] {
        var kinds: [ChartKind] = []
        if !hrSamples.isEmpty { kinds.append(.hr) }
        if gpsTrack?.contains(where: { $0.altitude != nil }) == true { kinds.append(.elevation) }
        if (gpsTrack ?? []).filter({ ($0.speed ?? 0) > 0.3 }).count >= Self.minimumPacePoints {
            kinds.append(.pace)
        }
        return kinds
    }

    var body: some View {
        if !available.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 0) {
                    if available.count > 1 {
                        Picker("Chart", selection: $selected) {
                            ForEach(available, id: \.self) { kind in
                                Label(kind.label, systemImage: kind.icon)
                                    .tag(Optional(kind))
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.bottom, 10)
                        .onChange(of: selected) { AppHaptics.selection() }
                    }

                    Text(WorkoutScrub.readout(at: scrub, in: series) ?? "Drag across the chart to read a moment")
                        .font(.caption).monospacedDigit()
                        .foregroundStyle(scrub == nil ? .secondary : .primary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .padding(.bottom, AppMetrics.gapSmall)
                        .accessibilityHidden(scrub == nil)

                    chart
                        .frame(height: 160)
                        .animation(AppAnimation.crossfade, value: selected)
                        .sensoryFeedback(.selection, trigger: scrub == nil)
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            } header: {
                Text(available.count == 1 ? available[0].label : "Activity Data")
            }
            // Keep the selection inside what the data supports — on first
            // appearance, and whenever the workout's data changes underneath.
            .task(id: available) {
                normalizeSelection()
                let (hr, track, km) = (hrSamples, gpsTrack ?? [], distanceKm)
                series = await Task.detached(priority: .userInitiated) {
                    WorkoutScrub.Series(hr: hr, track: track, distanceKm: km)
                }.value
            }
            .onChange(of: available) { normalizeSelection() }
        }
    }

    private func normalizeSelection() {
        if let selected, available.contains(selected) { return }
        selected = available.first
    }

    @ViewBuilder
    private var chart: some View {
        switch selected {
        case .hr:
            HRTimelineView(samples: hrSamples, avgHR: avgHR, maxHR: maxHR, hrConfig: hrConfig, scrub: $scrub)
        case .elevation:
            if let gpsTrack {
                ElevationProfileView(points: gpsTrack, gainM: elevationGain, scrub: $scrub)
            }
        case .pace:
            if let gpsTrack {
                PaceTimelineView(points: gpsTrack, distanceKm: distanceKm, scrub: $scrub)
            }
        case nil:
            EmptyView()
        }
    }
}

extension WorkoutChartsSection {
    /// Convenience for the common case: everything comes off one workout.
    init(workout: ImportedWorkout, hrConfig: HRConfig?) {
        self.init(gpsTrack: workout.gpsTrack,
                  hrSamples: workout.heartRate?.samples ?? [],
                  avgHR: workout.heartRate?.avg,
                  maxHR: workout.heartRate?.max,
                  elevationGain: workout.elevation?.gain,
                  distanceKm: workout.distance?.value,
                  hrConfig: hrConfig)
    }
}

// MARK: - Scrubbing

/// What the workout's charts say at one moment. Pure, so it is tested without
/// a chart: the three series as the charts draw them, and the line that reads
/// them at a time.
enum WorkoutScrub {
    struct Series: Sendable {
        var hr: [(elapsed: Double, value: Double)] = []
        var pace: [(elapsed: Double, value: Double)] = []
        var altitude: [(elapsed: Double, value: Double)] = []

        init() {}

        nonisolated init(hr samples: [HRSample], track: [GPSPoint], distanceKm: Double?) {
            hr = HRTimelineView.buildData(samples: samples).data.map { ($0.elapsed, Double($0.bpm)) }
            pace = PaceTimelineView.buildData(points: track, distanceKm: distanceKm).data
                .map { ($0.elapsed, $0.paceSecPerKm) }
            altitude = ElevationProfileView.buildData(points: track).data.map { ($0.elapsed, $0.alt) }
        }
    }

    /// The value recorded nearest `time`, if one was within a minute of it —
    /// a pause in the recording reads as nothing, not as its last value.
    nonisolated static func value(at time: Double, in series: [(elapsed: Double, value: Double)]) -> Double? {
        guard let nearest = series.min(by: { abs($0.elapsed - time) < abs($1.elapsed - time) }),
              abs(nearest.elapsed - time) <= 60 else { return nil }
        return nearest.value
    }

    /// "12:30 · 142 bpm · 5:12 /km · 412 m"; nil when nothing is touched.
    nonisolated static func readout(at time: Double?, in series: Series) -> String? {
        guard let time else { return nil }
        var parts = [clock(max(0, time))]
        if let bpm = value(at: time, in: series.hr) { parts.append("\(Int(bpm.rounded())) bpm") }
        if let pace = value(at: time, in: series.pace) { parts.append("\(clock(pace)) /km") }
        if let alt = value(at: time, in: series.altitude) { parts.append("\(Int(alt.rounded())) m") }
        return parts.joined(separator: " · ")
    }

    /// Seconds as "m:ss", or "h:mm:ss" from an hour on.
    nonisolated static func clock(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }
}
