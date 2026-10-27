import Foundation

// A program composed of several tracks (src/composition.py): two or more
// methodologies' tracks — or two of one — each running in its own phases,
// sharing the athlete's week by weight. The server places every session and
// says how the week was shared; the phone sends the tracks, reads them back
// from the round-tripped extras, and shows them. Nothing here recomputes a
// share or a placement.

/// One track of a composition request: `lanes[]` in POST /programs/generate.
struct ProgramLane: Codable, Hashable {
    let philosophyId: String
    /// nil is the track written for the athlete's level.
    var trackId: String?
    var weight: Double
    /// Where it starts (a regenerate's tail resumes each track in its own phase).
    var startPhase: String? = nil
    var periodizationWeek: Int? = nil

    var key: String? { trackId.map { "\(philosophyId)/\($0)" } }

    enum CodingKeys: String, CodingKey {
        case philosophyId = "philosophy_id"
        case trackId = "track_id"
        case weight
        case startPhase = "start_phase"
        case periodizationWeek = "periodization_week"
    }
}

/// A composed week's track: its own phase, deload and session count
/// (`week.lanes`; the week's own phase fields are the lead track's).
struct WeekLane: Hashable {
    let laneKey: String
    let trackId: String
    let phase: String
    let phaseId: String?
    let phaseName: String?
    let weekInPhase: Int?
    let framework: String?
    let isDeload: Bool
    let sessions: Int

    var philosophyId: String { String(laneKey.split(separator: "/").first ?? "") }
}

/// How a composed program shared the week: `composition.lanes[]`.
struct CompositionLane: Hashable {
    let key: String
    let kind: String
    let philosophyId: String
    let trackId: String
    let name: String
    let weight: Double
    let days: Int
    let reservedDays: [Int]
}

fileprivate extension JSONValue {
    var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
    var arrayValue: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    var intValue: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d): return Int(d)
        default: return nil
        }
    }
    var doubleValue: Double? {
        switch self {
        case .int(let i): return Double(i)
        case .double(let d): return d
        default: return nil
        }
    }
    var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
}

extension ProgramWeek {
    /// The week's tracks, in the program's order; empty for one track.
    var lanes: [WeekLane] {
        (extra["lanes"]?.arrayValue ?? []).compactMap { value in
            guard let o = value.objectValue, let key = o["lane_key"]?.stringValue else { return nil }
            return WeekLane(laneKey: key, trackId: o["track_id"]?.stringValue ?? "",
                            phase: o["phase"]?.stringValue ?? phase,
                            phaseId: o["phase_id"]?.stringValue, phaseName: o["phase_name"]?.stringValue,
                            weekInPhase: o["week_in_phase"]?.intValue, framework: o["framework"]?.stringValue,
                            isDeload: o["is_deload"]?.boolValue ?? false, sessions: o["sessions"]?.intValue ?? 0)
        }
    }
}

extension ProgramSession {
    /// A composed program's session's track (`<philosophy>/<track>`), and the
    /// phase, framework and phase week it runs in — its own, not the week's.
    var laneKey: String? { extra["lane_key"]?.stringValue }
    var lanePhase: String? { extra["phase"]?.stringValue }
    var lanePhaseId: String? { extra["phase_id"]?.stringValue }
    var laneFramework: String? { extra["framework"]?.stringValue }
    var laneWeekInPhase: Int? { extra["week_in_phase"]?.intValue }
}

extension GeneratedProgram {
    /// How the week was shared between the tracks; empty for one track.
    var compositionLanes: [CompositionLane] {
        guard let lanes = extra["composition"]?.objectValue?["lanes"]?.arrayValue else { return [] }
        return lanes.compactMap { value in
            guard let o = value.objectValue, let key = o["key"]?.stringValue,
                  let pid = o["philosophy_id"]?.stringValue, let tid = o["track_id"]?.stringValue else { return nil }
            return CompositionLane(key: key, kind: o["kind"]?.stringValue ?? "", philosophyId: pid, trackId: tid,
                                   name: o["name"]?.stringValue ?? pid, weight: o["weight"]?.doubleValue ?? 0,
                                   days: o["days"]?.intValue ?? 0,
                                   reservedDays: (o["reserved_days"]?.arrayValue ?? []).compactMap(\.intValue))
        }
    }

    /// The tracks a regenerate from `weekIndex` asks for, each resuming in
    /// its own phase and phase week; nil for one track.
    func regenerateLanes(from weekIndex: Int) -> [ProgramLane]? {
        let lanes = compositionLanes
        guard lanes.count > 1 else { return nil }
        let week = weeks.indices.contains(weekIndex) ? weeks[weekIndex] : nil
        return lanes.map { lane in
            let at = week?.lanes.first { $0.laneKey == lane.key }
            return ProgramLane(philosophyId: lane.philosophyId, trackId: lane.trackId, weight: lane.weight,
                               startPhase: at?.phaseId, periodizationWeek: at?.phaseId == nil ? nil : at?.weekInPhase)
        }
    }

    /// The program's lines that say what a track gave up to fit beside the others.
    func cuts(of lane: CompositionLane) -> [String] {
        compromises.filter { $0.hasPrefix("\(lane.name): ") && $0.contains("to fit beside") }
            .map { String($0.dropFirst(lane.name.count + 2)) }
    }
}

extension TrackEntryRequirements {
    /// What every one of several tracks asks before it runs, as one track's:
    /// the levels all are written for, every movement any needs mastered at
    /// `level`, the most bells, every lift any may start from a known weight.
    static func merged(_ all: [TrackEntryRequirements], level: String) -> TrackEntryRequirements? {
        guard let first = all.first else { return nil }
        if all.count == 1 { return first }
        var mastered: [String] = []
        var loads: [StartingLoad] = []
        var names: [String: String] = [:]
        for r in all {
            for id in r.masteredExercisesByLevel?[level] ?? r.masteredExercises where !mastered.contains(id) {
                mastered.append(id)
            }
            for l in r.startingLoads ?? [] where !loads.contains(where: { $0.id == l.id }) { loads.append(l) }
            names.merge(r.exerciseNames ?? [:]) { a, _ in a }
        }
        let levels = all.dropFirst().reduce(first.trainingLevels) { acc, r in acc.filter(r.trainingLevels.contains) }
        return TrackEntryRequirements(trainingLevels: levels, masteredExercises: mastered,
                                      masteredExercisesByLevel: [level: mastered], exerciseNames: names,
                                      kettlebellCount: all.map(\.kettlebellCount).max() ?? 1,
                                      startingLoads: loads)
    }
}
