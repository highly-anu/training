import SwiftUI

// MARK: - Step 2: Schedule

struct BuilderStep2ScheduleView: View {
    @ObservedObject var builder: BuilderState
    @EnvironmentObject var appState: AppState

    private let dayOptions = Array(2...7)

    private var philosophy: PhilosophyCard? {
        appState.philosophies.first { $0.id == builder.selectedPhilosophyId }
    }

    /// The standard lengths plus the track's own and the current choice, so
    /// a 31-week track is selectable.
    private var weekOptions: [Int] {
        var options: Set<Int> = [4, 6, 8, 10, 12, 16, 20, 24, builder.numWeeks]
        if let track = builder.track(in: philosophy) { options.insert(track.totalWeeks) }
        for lane in builder.lanes {
            if let t = builder.track(of: lane, in: appState.philosophies) { options.insert(t.totalWeeks) }
        }
        return options.sorted()
    }

    var body: some View {
        Form {
            if builder.isComposed {
                LaneSections(builder: builder)
            } else if let tracks = philosophy?.tracks, !tracks.isEmpty {
                trackSection(tracks)
            }

            Section("Duration") {
                Picker("Number of Weeks", selection: $builder.numWeeks) {
                    ForEach(weekOptions, id: \.self) { w in
                        Text("\(w) weeks").tag(w)
                    }
                }

                DatePicker("Start Date", selection: $builder.startDate, displayedComponents: .date)
            }

            Section("Training Days") {
                Stepper(
                    "Days per Week: \(builder.constraints.daysPerWeek)",
                    value: Binding(
                        get: { builder.constraints.daysPerWeek },
                        set: { builder.constraints.daysPerWeek = $0 }
                    ),
                    in: 2...7
                )
                Stepper(
                    "Session Duration: \(builder.constraints.sessionTimeMinutes) min",
                    value: Binding(
                        get: { builder.constraints.sessionTimeMinutes },
                        set: { builder.constraints.sessionTimeMinutes = $0 }
                    ),
                    in: 20...180, step: 10
                )
            }

            Section("Event Target (optional)") {
                Toggle("Has Target Event", isOn: Binding(
                    get: { builder.eventDate != nil },
                    set: { if $0 { builder.eventDate = Date().addingTimeInterval(60 * 60 * 24 * 84) } else { builder.eventDate = nil } }
                ))
                if builder.eventDate != nil {
                    DatePicker("Event Date", selection: Binding(
                        get: { builder.eventDate ?? Date() },
                        set: { builder.eventDate = $0 }
                    ), displayedComponents: .date)
                }
            }
        }
        .onAppear {
            if builder.isComposed { builder.applyLength(ofLanes: appState.philosophies) }
            else { builder.applyLength(of: builder.track(in: philosophy)) }
        }
    }

    /// The methodology's tracks, each with its own phases. One track is shown
    /// for what it is; two or more are a choice.
    private func trackSection(_ tracks: [PhilosophyTrack]) -> some View {
        let active = builder.track(in: philosophy)
        return Section {
            ForEach(tracks) { track in
                if tracks.count > 1 {
                    Button {
                        AppHaptics.light()
                        builder.selectedTrackId = track.id
                        builder.startPhaseId = nil
                        builder.applyLength(of: track)
                    } label: {
                        TrackChoiceRow(track: track, selected: track.id == active?.id,
                                       primary: track.id == philosophy?.primaryTrack?.id)
                    }
                    .buttonStyle(.plain)
                } else {
                    TrackChoiceRow(track: track, selected: false, primary: false)
                }
            }
        } header: {
            Text(tracks.count > 1 ? "Track" : "Phases")
        } footer: {
            if tracks.count > 1 {
                Text("Each track is one way to follow this methodology, in its own phases.")
            }
        }
    }
}

/// One track of a methodology as a choice: its name, description and phases
/// (TrackPhaseList). The builder's track list and a blend's tracks.
struct TrackChoiceRow: View {
    let track: PhilosophyTrack
    let selected: Bool
    let primary: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(track.name)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(.primary)
                if primary {
                    Text("Primary")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(AppColor.accent)
                }
            }
            if let text = track.description, !text.isEmpty {
                Text(text)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            if track.invention != nil {
                // A track the app made up, not the method's own program.
                Label("The app's own track, not the method's", systemImage: "info.circle")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            TrackPhaseList(track: track)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A blend's tracks (step 2): each methodology runs one of its tracks in its
/// own phases at its weight, and may add another of its tracks. The server
/// composes them into one week; the preview says how the days were shared
/// and what gave way (design-system §6.22).
struct LaneSections: View {
    @ObservedObject var builder: BuilderState
    @EnvironmentObject var appState: AppState

    private var total: Double { max(builder.lanes.reduce(0) { $0 + $1.weight }, 1) }

    var body: some View {
        ForEach($builder.lanes) { $lane in
            laneSection($lane)
        }
        let addable = addableTracks
        if !addable.isEmpty {
            Section {
                ForEach(addable, id: \.0.id) { philosophy, track in
                    Button {
                        AppHaptics.light()
                        builder.lanes.append(BuilderLane(philosophyId: philosophy.id, trackId: track.id))
                        builder.applyLength(ofLanes: appState.philosophies)
                    } label: {
                        Label("Add another \(philosophy.name) track", systemImage: "plus.circle")
                    }
                }
            } footer: {
                Text("Every track runs in its own phases on your week together; its weight is its share of your days.")
            }
        }
    }

    /// A methodology in the blend with a track not in it yet, and that track.
    private var addableTracks: [(PhilosophyCard, PhilosophyTrack)] {
        var seen: [String] = []
        var out: [(PhilosophyCard, PhilosophyTrack)] = []
        for lane in builder.lanes where !seen.contains(lane.philosophyId) {
            seen.append(lane.philosophyId)
            guard let phil = appState.philosophies.first(where: { $0.id == lane.philosophyId }) else { continue }
            let used = Set(builder.lanes.filter { $0.philosophyId == phil.id }
                .compactMap { builder.track(of: $0, in: appState.philosophies)?.id })
            if let next = (phil.tracks ?? []).first(where: { !used.contains($0.id) }) { out.append((phil, next)) }
        }
        return out
    }

    private func laneSection(_ lane: Binding<BuilderLane>) -> some View {
        let phil = appState.philosophies.first { $0.id == lane.wrappedValue.philosophyId }
        let active = builder.track(of: lane.wrappedValue, in: appState.philosophies)
        let siblings = builder.lanes.filter { $0.id != lane.wrappedValue.id && $0.philosophyId == lane.wrappedValue.philosophyId }
            .compactMap { builder.track(of: $0, in: appState.philosophies)?.id }
        let tracks = phil?.tracks ?? []
        return Section {
            ForEach(tracks.count > 1 ? tracks : (active.map { [$0] } ?? [])) { track in
                let taken = siblings.contains(track.id)
                Button {
                    AppHaptics.light()
                    lane.wrappedValue.trackId = track.id
                    lane.wrappedValue.startPhaseId = nil
                    builder.applyLength(ofLanes: appState.philosophies)
                } label: {
                    TrackChoiceRow(track: track, selected: tracks.count > 1 && track.id == active?.id, primary: false)
                }
                .buttonStyle(.plain)
                .disabled(tracks.count < 2 || taken)
                .opacity(taken ? 0.4 : 1)
            }
            HStack {
                Text("Weight")
                Slider(value: lane.weight, in: 5...95, step: 5)
                Text("\(Int((lane.wrappedValue.weight / total * 100).rounded())) %")
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            if !siblings.isEmpty {
                Button("Remove this track", role: .destructive) {
                    builder.lanes.removeAll { $0.id == lane.wrappedValue.id }
                }
            }
        } header: {
            Text(phil?.name ?? lane.wrappedValue.philosophyId)
        }
    }
}
