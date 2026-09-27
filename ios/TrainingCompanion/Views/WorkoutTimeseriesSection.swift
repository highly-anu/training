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
struct WorkoutRouteSection: View {
    let points: [GPSPoint]

    private enum MapMode { case flat, swiss3d }
    @State private var mapMode: MapMode = .flat

    var body: some View {
        if !points.isEmpty {
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
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 8, trailing: 8))
            }
        }
    }
}

// MARK: - Charts

/// HR, elevation and pace over the workout, with a selector when more than one
/// has data.
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

                    chart
                        .frame(height: 160)
                        .animation(.easeInOut(duration: 0.2), value: selected)
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            } header: {
                Text(available.count == 1 ? available[0].label : "Activity Data")
            }
            // Keep the selection inside what the data supports — on first
            // appearance, and whenever the workout's data changes underneath.
            .task(id: available) { normalizeSelection() }
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
            HRTimelineView(samples: hrSamples, avgHR: avgHR, maxHR: maxHR, hrConfig: hrConfig)
        case .elevation:
            if let gpsTrack {
                ElevationProfileView(points: gpsTrack, gainM: elevationGain)
            }
        case .pace:
            if let gpsTrack {
                PaceTimelineView(points: gpsTrack, distanceKm: distanceKm)
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
