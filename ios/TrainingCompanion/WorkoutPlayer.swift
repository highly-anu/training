import Combine
import Foundation
import UIKit

/// The phone's workout player (design-system §6.44): any session of the
/// program, step by step, on the engine the Apple Watch runs
/// (WorkoutSessionState), drawn from the screens the server writes for both
/// watches. The athlete records with a band; the phone shows what to do,
/// times it, and logs what was done.
///
/// The clock is the wall clock: the phone may lock, or the app go to the
/// background, so a second is never counted by a timer that might not fire —
/// on every tick, and on coming back, the engine catches up to the time it
/// is (`catchUp`). What it was doing is saved as it goes (ActiveWorkoutStore),
/// so a workout outlives the app.
@MainActor
final class WorkoutPlayerModel: ObservableObject {

    /// The session to run: where it sits in the program and on which day.
    struct Target: Codable, Equatable, Identifiable {
        var id: String { sessionKey }
        let sessionKey: String
        /// The day it falls on (yyyy-MM-dd), what `today-session?date=` reads.
        let date: String
        let title: String
    }

    enum LoadState: Equatable {
        case loading, ready, failed(String)
    }

    let target: Target
    let engine = WorkoutSessionState()
    @Published private(set) var loadState: LoadState = .loading
    @Published private(set) var session: WatchSession?
    /// Started: the first step is up and the clock runs.
    @Published private(set) var startedAt: Date?
    /// The athlete ended it: the completion screen is up.
    @Published var finished = false
    @Published var notes = ""
    @Published private(set) var saving = false

    private var timer: Timer?
    private var bag = Set<AnyCancellable>()

    /// The player for a target, carrying on where the kept workout stopped
    /// when it is this one (ActiveWorkoutStore).
    static func resumingIfKept(_ target: Target) -> WorkoutPlayerModel {
        let player = WorkoutPlayerModel(target: target)
        if let kept = ActiveWorkoutStore.load(),
           kept.target.sessionKey == target.sessionKey, kept.target.date == target.date {
            player.resume(kept)
        }
        return player
    }

    init(target: Target) {
        self.target = target
        engine.cues = PhoneCueOutput.shared
        // Every move of the engine re-draws the player, is said aloud with
        // Voice on, and is saved.
        engine.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bag)
        engine.$phase
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.phaseChanged() }
            }
            .store(in: &bag)
    }

    // MARK: - Loading

    /// The session as the server words it for the watches, on its own day;
    /// without the server, the stored program's (`PlayerFallback`), which has
    /// no last times.
    func load(api: APIClient?, fallback: ProgramSession?) async {
        loadState = .loading
        if let api, let data = try? await api.fetchWatchDay(date: target.date),
           let day = try? JSONDecoder().decode(WatchDay.self, from: data),
           let found = day.sessions?.first(where: { $0.sessionId == target.sessionKey }) {
            session = found
            loadState = .ready
            return
        }
        if let fallback, let built = PlayerFallback.session(fallback, key: target.sessionKey) {
            session = built
            loadState = .ready
            return
        }
        loadState = .failed("The workout could not be loaded. Check the connection and try again.")
    }

    // MARK: - Running

    func begin() {
        guard let session, startedAt == nil else { return }
        let now = Date()
        startedAt = now
        engine.startSession(session)
        engine.lastTickAt = now
        startClock()
        save()
    }

    /// A workout the store kept, back where it was and caught up to now.
    func resume(_ record: ActiveWorkoutStore.Record) {
        session = record.session
        loadState = .ready
        startedAt = record.startedAt
        notes = record.notes
        engine.restore(record.snapshot, session: record.session)
        finished = record.finished
        if !finished {
            engine.muted = true
            engine.catchUp(to: Date())
            engine.muted = false
            startClock()
        }
    }

    private func startClock() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.engine.catchUp(to: Date()) }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func stopClock() {
        timer?.invalidate()
        timer = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// Back in the foreground: the seconds the phone was away, caught up
    /// silently; the moment it is now sounds once.
    func cameToForeground() {
        guard startedAt != nil, !finished else { return }
        engine.catchUp(to: Date())
        WorkoutLockScreen.shared.cancelCues()
        startClock()
    }

    /// To the background: the clock's moments ahead become notifications and
    /// the Live Activity's countdown (WorkoutLockScreen).
    func wentToBackground() {
        guard startedAt != nil, !finished else { return }
        save()
        WorkoutLockScreen.shared.scheduleCues(engine.forecast(), session: target.title)
        WorkoutLockScreen.shared.update(self)
    }

    private func phaseChanged() {
        guard startedAt != nil else { return }
        if engine.phase == .sessionComplete {
            finished = true
            stopClock()
        } else if !engine.muted {
            PhoneCueOutput.shared.announce(engine.cueText)
        }
        WorkoutLockScreen.shared.update(self)
        save()
    }

    /// End: the completion screen, where the results, notes and Save are.
    func finish() {
        // The clock up to this second, so the time and the last step's
        // window end now, not at the last tick.
        engine.catchUp(to: Date())
        engine.completeSession()
    }

    /// Jump to any step from the step list.
    func go(to index: Int) {
        guard let session, index < session.exercises.count else { return }
        engine.advance(to: index)
    }

    // MARK: - Saving the workout

    /// What the session produced, as the watches send it
    /// (WatchUpload.sessionLog), with each step's window by the wall clock —
    /// what lines it up with the band's heart rate once the band's workout
    /// links — and the notes.
    func sessionLog() -> [String: Any]? {
        guard let session, let startedAt else { return nil }
        let iso = ISO8601DateFormatter()
        let end = Date()
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let summary = WatchWorkoutSummary(
            sessionId: session.sessionId, date: target.date,
            startedAt: iso.string(from: startedAt), endedAt: iso.string(from: end),
            durationMinutes: max(1, engine.elapsedSeconds / 60), avgHR: nil, peakHR: nil,
            setLogs: engine.setLogs, exercisesCompleted: engine.completedExerciseIds.count,
            source: Self.source, hrSamples: nil, gpsTrack: nil, distanceMeters: nil,
            elevationGainMeters: nil, cadenceAvg: nil, paceSecsPerKm: nil,
            exerciseTimeline: engine.exerciseTimeline(startedAt: startedAt),
            outcomes: engine.outcomes.isEmpty ? nil : engine.outcomes,
            standardResults: engine.standardDecisions(session))
        var log = WatchUpload.sessionLog(summary: summary)
        log["notes"] = notes
        if let timeline = summary.exerciseTimeline,
           let data = try? JSONEncoder().encode(timeline),
           let json = try? JSONSerialization.jsonObject(with: data) {
            log["exerciseTimeline"] = json
        }
        if let uid = session.sessionUid { log["sessionUid"] = uid }
        return log
    }

    /// The log's source: the phone ran the steps.
    static let source = "phone"

    /// The Results answer (a test day) and the upload; the store is cleared
    /// once the server has it. False when the upload failed (the workout is
    /// kept, to try again).
    func save(decision: String?, appState: AppState) async -> Bool {
        engine.resultDecision = decision
        guard let log = sessionLog() else { return false }
        saving = true
        defer { saving = false }
        let ok = await appState.finishWorkout(sessionKey: target.sessionKey, sessionUid: session?.sessionUid, log: log)
        if ok {
            ActiveWorkoutStore.clear()
            WorkoutLockScreen.shared.end()
        } else {
            save()
        }
        return ok
    }

    /// Leave without saving anything.
    func discard() {
        stopClock()
        ActiveWorkoutStore.clear()
        WorkoutLockScreen.shared.end()
    }

    /// Leave, keeping the workout to resume (Today offers it).
    func leaveForLater() {
        save()
        stopClock()
        WorkoutLockScreen.shared.end()
    }

    private func save() {
        guard let session, let startedAt else { return }
        ActiveWorkoutStore.save(.init(target: target, session: session, startedAt: startedAt,
                                      snapshot: engine.snapshot(), finished: finished, notes: notes))
    }

    deinit {
        timer?.invalidate()
    }
}

/// The workout in progress, kept in Application Support so it outlives the
/// app: a relaunch offers it again on Today.
enum ActiveWorkoutStore {
    struct Record: Codable {
        let target: WorkoutPlayerModel.Target
        let session: WatchSession
        let startedAt: Date
        let snapshot: WorkoutSessionState.Snapshot
        let finished: Bool
        let notes: String
    }

    private static var url: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("active-workout.json")
    }

    static func save(_ record: Record) {
        guard let url, let data = try? JSONEncoder().encode(record) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// The workout kept, unless it is more than a day old.
    static func load() -> Record? {
        guard let url, let data = try? Data(contentsOf: url),
              let record = try? JSONDecoder().decode(Record.self, from: data) else { return nil }
        guard Date().timeIntervalSince(record.startedAt) < 24 * 3600 else { clear(); return nil }
        return record
    }

    static func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

/// A session built from the stored program when the server's day cannot be
/// read (no connection): the step data the watch payload carries, from the
/// program's own fields, and each step drawn with its slot type's screen.
enum PlayerFallback {
    static func session(_ s: ProgramSession, key: String) -> WatchSession? {
        let exercises: [WatchExercise] = s.exercises.compactMap { ea in
            guard let ex = ea.exercise else { return nil }
            var e: [String: Any] = [
                "exerciseId": ex.id, "name": ex.name,
                "slotType": LoadFormat.resolvedSlotType(ea), "slotRole": ea.slotRole ?? "",
                "isMeta": ea.meta, "loadDescription": LoadFormat.describe(ea),
            ]
            let l = ea.load
            if let v = l.sets { e["sets"] = v }
            if let v = l.reps?.displayString { e["reps"] = v }
            if let v = l.weightKg { e["weightKg"] = v }
            if let v = l.targetRpe { e["targetRpe"] = v }
            if let v = l.durationMinutes { e["durationMinutes"] = v }
            if let v = l.timeMinutes { e["timeMinutes"] = v }
            if let v = l.targetRounds { e["targetRounds"] = v }
            if let v = l.holdSeconds { e["holdSeconds"] = v }
            if let v = l.distanceKm { e["distanceKm"] = v }
            if let v = l.zoneTarget { e["zoneTarget"] = v }
            if let v = ea.restSec { e["restSeconds"] = v }
            if let v = ea.loadNote { e["loadNote"] = v }
            if let v = ea.notes ?? ex.notes { e["coachingCue"] = v }
            for (key, wire) in [("work_sec", "workSec"), ("rest_sec", "intervalRestSec"),
                                ("reps_per_round", "repsPerRound"), ("switch_at_sec", "switchAtSec")] {
                if case .int(let n)? = l.extra[key] { e[wire] = n }
            }
            if case .array(let items)? = l.extra["rep_scheme"] {
                e["repScheme"] = items.compactMap { item -> Int? in if case .int(let n) = item { return n }; return nil }
            }
            guard let data = try? JSONSerialization.data(withJSONObject: e) else { return nil }
            return try? JSONDecoder().decode(WatchExercise.self, from: data)
        }
        guard !exercises.isEmpty else { return nil }
        return WatchSession(sessionId: key, modalityId: s.modality, archetypeName: s.archetype?.name ?? s.modality,
                            estimatedMinutes: s.archetype?.durationEstimateMinutes ?? 45, isDeload: s.isDeload,
                            exercises: exercises)
    }
}
