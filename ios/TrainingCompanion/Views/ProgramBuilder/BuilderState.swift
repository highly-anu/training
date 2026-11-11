import SwiftUI
import Combine

// MARK: - Builder State

@MainActor
final class BuilderState: ObservableObject {
    // Step 1
    @Published var selectedPhilosophyId: String? = nil {
        didSet {
            guard oldValue != selectedPhilosophyId else { return }
            selectedTrackId = nil
            startPhaseId = nil
            lengthSetFor = nil
        }
    }

    // Step 2
    /// The track to run; nil is the methodology's primary track.
    @Published var selectedTrackId: String? = nil
    /// The phase to start at; nil is the track's first.
    @Published var startPhaseId: String? = nil
    @Published var numWeeks: Int = 12
    /// The track whose length `numWeeks` was last set from, so the default
    /// is applied once per track and never over the athlete's own choice.
    var lengthSetFor: String? = nil
    @Published var eventDate: Date? = nil
    @Published var startDate: Date = Date()

    // Step 3
    @Published var constraints = GenerateConstraints()

    // Generation
    @Published var isGenerating = false
    @Published var generationError: String? = nil
    @Published var didSucceed = false
    /// The generated draft, pushed as Program ▸ Preview; started from there.
    @Published var preview: PreviewDraft? = nil

    /// A blend: two or more tracks composed into one program
    /// (ProgramComposition.swift). One lane is the single-methodology path
    /// above, kept in `selectedPhilosophyId`.
    @Published var lanes: [BuilderLane] = [] {
        didSet {
            let single = lanes.count == 1 ? lanes[0].philosophyId : nil
            if selectedPhilosophyId != single { selectedPhilosophyId = single }
        }
    }
    var isComposed: Bool { lanes.count > 1 }

    var isStep1Valid: Bool { !lanes.isEmpty }

    /// What the chosen track asks before it runs — any of them, in a blend.
    func requirements(in philosophies: [PhilosophyCard]) -> TrackEntryRequirements? {
        if isComposed {
            return .merged(lanes.compactMap { track(of: $0, in: philosophies)?.entryRequirements },
                           level: constraints.trainingLevel)
        }
        return track(in: philosophies.first { $0.id == selectedPhilosophyId })?.entryRequirements
    }

    func requiredSkills(in philosophies: [PhilosophyCard]) -> [String] {
        let r = requirements(in: philosophies)
        return r?.masteredExercisesByLevel?[constraints.trainingLevel] ?? r?.masteredExercises ?? []
    }

    /// Whether the athlete meets them: the review step says what is missing,
    /// and the builder's bar offers no preview until nothing is.
    func entryReady(in philosophies: [PhilosophyCard]) -> Bool {
        guard let r = requirements(in: philosophies) else { return true }
        return r.trainingLevels.contains(constraints.trainingLevel)
            && Set(requiredSkills(in: philosophies)).isSubset(of: Set(constraints.masteredExercises))
            && r.neededImplements.allSatisfy { constraints.count(for: $0.countKey) >= $0.count }
    }
    var isStep3Valid: Bool { !constraints.equipment.isEmpty }

    /// Up to four methodologies; picking one again removes it (and any
    /// further track of it).
    func toggle(_ philosophy: PhilosophyCard) {
        if lanes.contains(where: { $0.philosophyId == philosophy.id }) {
            lanes.removeAll { $0.philosophyId == philosophy.id }
        } else if Set(lanes.map(\.philosophyId)).count < 4 {
            lanes.append(BuilderLane(philosophyId: philosophy.id))
        }
    }

    /// The track a lane runs: its pick, else the one for the athlete's level.
    func track(of lane: BuilderLane, in philosophies: [PhilosophyCard]) -> PhilosophyTrack? {
        philosophies.first { $0.id == lane.philosophyId }?.track(lane.trackId, level: constraints.trainingLevel)
    }

    /// A composition runs as long as its longest track.
    func applyLength(ofLanes philosophies: [PhilosophyCard]) {
        let key = "lanes:" + lanes.map { "\($0.philosophyId)/\(track(of: $0, in: philosophies)?.id ?? "")" }.joined(separator: ",")
        guard lengthSetFor != key else { return }
        lengthSetFor = key
        let longest = lanes.compactMap { track(of: $0, in: philosophies)?.totalWeeks }.max()
        if let longest, longest > 0 { numWeeks = longest }
    }

    /// The track the program will run: the picked one, else the one written
    /// for the athlete's level, else the primary — as the server picks it.
    func track(in philosophy: PhilosophyCard?) -> PhilosophyTrack? {
        philosophy?.track(selectedTrackId, level: constraints.trainingLevel)
    }

    /// A multi-phase track runs all its phases, so its length becomes the
    /// default duration — once per track. A single repeatable block keeps the
    /// athlete's choice.
    func applyLength(of track: PhilosophyTrack?) {
        guard let track, lengthSetFor != track.id else { return }
        lengthSetFor = track.id
        if track.phases.count > 1 { numWeeks = track.totalWeeks }
    }
}

/// One track of a blend in the builder: a methodology's track, its weight
/// (5–95, normalised when sent) and where it starts.
struct BuilderLane: Identifiable, Hashable {
    let id = UUID()
    let philosophyId: String
    var trackId: String? = nil
    var weight: Double = 50
    var startPhaseId: String? = nil
}

/// A generated program not yet started, and the request that made it —
/// what the builder and the settings sheet push as the preview.
struct PreviewDraft: Identifiable, Hashable {
    let id = UUID()
    let request: GenerateProgramRequest
    let draft: GeneratedProgram
    static func == (a: PreviewDraft, b: PreviewDraft) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}
