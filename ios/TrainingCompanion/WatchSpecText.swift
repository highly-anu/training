import Foundation

// The Apple Watch's reading of a package's screen spec — the port of the
// Garmin's ScreenSpec.mc and SpecRenderer.mc (docs/watch.md). Compiled into
// the app and the watch, so TrainingCompanionTests runs it against
// data/watch_fixtures.json, the cases the Garmin's generated SpecFixtures.mc
// runs too: one table of expected screens, two renderers.
//
// Every id is a vocabulary id (WatchVocab, generated from
// data/commons/watch_vocabulary.json) and every switch over one is
// exhaustive, so an id added to the vocabulary does not build until this
// file draws it.

// MARK: - The spec as the server sends it

/// One resolved screen from a session's `screens` (src/watch_spec.py), ids
/// as strings: an id this build does not know falls back, field by field.
struct WatchScreenSpec: Codable, Hashable {
    var template: String? = nil
    var title: [String]? = nil
    var a: String? = nil
    var b: String? = nil
    var gauge: String? = nil
    var lines: String? = nil
    var lap: String? = nil
    var phases: [String]? = nil
    var behaviours: WatchBehaviours? = nil
}

/// A package's behaviours (the vocabulary's `behaviours`); each is read on
/// its own, so a malformed one costs only itself.
struct WatchBehaviours: Codable, Hashable {
    var sideTracked: Bool? = nil
    var cumulativeTarget: Int? = nil
    var ladderPeak: Int? = nil
    var loadWave: [Int]? = nil
    var metronomeRpm: Int? = nil

    enum CodingKeys: String, CodingKey {
        case sideTracked = "side_tracked", cumulativeTarget = "cumulative_target", ladder
        case loadWave = "load_wave", metronomeRpm = "metronome_rpm"
    }
    private struct Ladder: Codable { var peak: Int? }

    init(sideTracked: Bool? = nil, cumulativeTarget: Int? = nil, ladderPeak: Int? = nil,
         loadWave: [Int]? = nil, metronomeRpm: Int? = nil) {
        self.sideTracked = sideTracked; self.cumulativeTarget = cumulativeTarget
        self.ladderPeak = ladderPeak; self.loadWave = loadWave; self.metronomeRpm = metronomeRpm
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sideTracked = try? c.decodeIfPresent(Bool.self, forKey: .sideTracked)
        cumulativeTarget = c.lenientInt(.cumulativeTarget)
        ladderPeak = (try? c.decodeIfPresent(Ladder.self, forKey: .ladder))?.peak
        loadWave = try? c.decodeIfPresent([Int].self, forKey: .loadWave)
        metronomeRpm = c.lenientInt(.metronomeRpm)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(sideTracked, forKey: .sideTracked)
        try c.encodeIfPresent(cumulativeTarget, forKey: .cumulativeTarget)
        try c.encodeIfPresent(ladderPeak.map { Ladder(peak: $0) }, forKey: .ladder)
        try c.encodeIfPresent(loadWave, forKey: .loadWave)
        try c.encodeIfPresent(metronomeRpm, forKey: .metronomeRpm)
    }
}

// MARK: - The screen a step is drawn with

/// A spec with every id known to this build (ScreenSpec.mc).
struct WatchScreen: Hashable {
    let template: WatchVocab.Template
    let title: [WatchVocab.TitlePart]
    let a: WatchVocab.Field?
    let b: WatchVocab.Field?
    let gauge: WatchVocab.Field?
    let lines: WatchVocab.Line?
    let lap: WatchVocab.Action
    var phases: [String] = []
    var behaviours = WatchBehaviours()

    /// The vocabulary's default for a slot type: a payload without specs (a
    /// cached day, an older server) draws what the slot type always did.
    static func synthesise(slotType: String?) -> WatchScreen {
        let t = slotType.flatMap { WatchVocab.slotTypes[$0] } ?? WatchVocab.fallbackTemplate
        return defaults(t)
    }

    static func defaults(_ t: WatchVocab.Template) -> WatchScreen {
        let d = WatchVocab.templateDefaults[t]!
        return WatchScreen(template: t, title: d.title, a: d.a, b: d.b, gauge: d.gauge, lines: d.lines, lap: d.lap)
    }

    /// The exercise's spec from the session's table, every unknown id
    /// replaced by its template's default (a newer server never blanks a
    /// screen); no spec, or an unknown template, gets the slot type's.
    static func forExercise(slotType: String?, key: String?,
                            screens: [String: WatchScreenSpec]?) -> WatchScreen {
        guard let key, let spec = screens?[key],
              let t = spec.template.flatMap(WatchVocab.Template.init(rawValue:)) else {
            return synthesise(slotType: slotType)
        }
        let base = defaults(t)
        func field(_ s: String?, _ fallback: WatchVocab.Field?) -> WatchVocab.Field? {
            s.flatMap(WatchVocab.Field.init(rawValue:)) ?? fallback
        }
        let lap = spec.lap.flatMap(WatchVocab.Action.init(rawValue:))
            .flatMap { WatchVocab.actions[t]?.contains($0) == true ? $0 : nil } ?? base.lap
        return WatchScreen(
            template: t,
            title: spec.title.map { $0.compactMap(WatchVocab.TitlePart.init(rawValue:)) } ?? base.title,
            a: field(spec.a, base.a), b: field(spec.b, base.b), gauge: field(spec.gauge, base.gauge),
            // A line this build does not know reads as the next step, as on the Garmin.
            lines: spec.lines.map { WatchVocab.Line(rawValue: $0) ?? .nextStep } ?? base.lines,
            lap: lap, phases: spec.phases ?? [], behaviours: spec.behaviours ?? WatchBehaviours())
    }
}

// MARK: - What the engine knows at this moment

/// The live state a screen reads: what the Garmin's renderer asks its
/// WorkoutController. The engine fills it; the renderer only reads it, so a
/// screen is a pure function of (exercise, spec, state).
struct WatchStepState: Codable, Equatable {
    /// The working set: reps, weight (nil on a bodyweight set) and RPE, as
    /// Edit Set leaves them.
    var reps: Int = 0
    var weightKg: Double? = nil
    var rpe: Double = 0
    /// Sets logged for this exercise, and whether a rest is running.
    var setsDone: Int = 0
    var resting: Bool = false
    var sideIsLeft: Bool = true
    /// Rounds or laps logged; reps so far toward a cumulative target.
    var rounds: Int = 0
    var repsDone: Int = 0
    /// The cap left, and the time on this step.
    var capLeftSec: Int = 0
    var elapsedSec: Int = 0
    var distanceKm: Double = 0
    var holdRunning: Bool = false
    var holdLeftSec: Int = 0
    /// An interval: which phase, round n of N, the time left in the phase,
    /// the work and rest lengths, and an HR-gated rest.
    var intervalWorking: Bool = true
    var intervalRound: Int = 1
    var intervalTotal: Int = 0
    var intervalLeftSec: Int = 0
    var intervalWorkSec: Int = 0
    var intervalRestSec: Int = 0
    var gateRest: Bool = false
    var restPhaseElapsedSec: Int = 0
    var heartRate: Int? = nil
    /// The step after this one ("Rest" 2:00, "Bench Press" 5x5…), worked
    /// out by the engine from the whole session.
    var nextTitle: String = "Finish"
    var nextValue: String? = nil
    /// The movements of the current round (an AMRAP's components).
    var components: [Component] = []

    struct Component: Codable, Equatable {
        var name: String
        var repsPerRound: Int? = nil
        /// Reps round by round (Fran's [21, 15, 9]): the round's own is shown.
        var repScheme: [Int]? = nil

        /// This round's reps: the scheme's entry for the rounds logged (its
        /// last once past it), else the one count.
        func reps(inRound logged: Int) -> Int? {
            guard let scheme = repScheme, !scheme.isEmpty else { return repsPerRound }
            return scheme[min(max(logged, 0), scheme.count - 1)]
        }
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WatchStepState()
        reps = try c.decodeIfPresent(Int.self, forKey: .reps) ?? d.reps
        weightKg = try c.decodeIfPresent(Double.self, forKey: .weightKg)
        rpe = try c.decodeIfPresent(Double.self, forKey: .rpe) ?? d.rpe
        setsDone = try c.decodeIfPresent(Int.self, forKey: .setsDone) ?? d.setsDone
        resting = try c.decodeIfPresent(Bool.self, forKey: .resting) ?? d.resting
        sideIsLeft = try c.decodeIfPresent(Bool.self, forKey: .sideIsLeft) ?? d.sideIsLeft
        rounds = try c.decodeIfPresent(Int.self, forKey: .rounds) ?? d.rounds
        repsDone = try c.decodeIfPresent(Int.self, forKey: .repsDone) ?? d.repsDone
        capLeftSec = try c.decodeIfPresent(Int.self, forKey: .capLeftSec) ?? d.capLeftSec
        elapsedSec = try c.decodeIfPresent(Int.self, forKey: .elapsedSec) ?? d.elapsedSec
        distanceKm = try c.decodeIfPresent(Double.self, forKey: .distanceKm) ?? d.distanceKm
        holdRunning = try c.decodeIfPresent(Bool.self, forKey: .holdRunning) ?? d.holdRunning
        holdLeftSec = try c.decodeIfPresent(Int.self, forKey: .holdLeftSec) ?? d.holdLeftSec
        intervalWorking = try c.decodeIfPresent(Bool.self, forKey: .intervalWorking) ?? d.intervalWorking
        intervalRound = try c.decodeIfPresent(Int.self, forKey: .intervalRound) ?? d.intervalRound
        intervalTotal = try c.decodeIfPresent(Int.self, forKey: .intervalTotal) ?? d.intervalTotal
        intervalLeftSec = try c.decodeIfPresent(Int.self, forKey: .intervalLeftSec) ?? d.intervalLeftSec
        intervalWorkSec = try c.decodeIfPresent(Int.self, forKey: .intervalWorkSec) ?? d.intervalWorkSec
        intervalRestSec = try c.decodeIfPresent(Int.self, forKey: .intervalRestSec) ?? d.intervalRestSec
        gateRest = try c.decodeIfPresent(Bool.self, forKey: .gateRest) ?? d.gateRest
        restPhaseElapsedSec = try c.decodeIfPresent(Int.self, forKey: .restPhaseElapsedSec) ?? d.restPhaseElapsedSec
        heartRate = try c.decodeIfPresent(Int.self, forKey: .heartRate)
        nextTitle = try c.decodeIfPresent(String.self, forKey: .nextTitle) ?? d.nextTitle
        nextValue = try c.decodeIfPresent(String.self, forKey: .nextValue)
        components = try c.decodeIfPresent([Component].self, forKey: .components) ?? d.components
    }
}

/// What the primary button (the Garmin's LAP) does, worked out like the
/// Garmin's `onLap`: the engine carries it out.
enum WatchLapOutcome: String, Codable {
    case completeSet = "complete_set"
    case startHold = "start_hold"
    case stopHold = "stop_hold"
    case logRound = "log_round"
    /// Count the round; it was the last, so move on.
    case logRoundAndNext = "log_round_and_next"
    case next
    case nextSide = "next_side"
}

// MARK: - The data page

/// Title line, two fields (a label over a value), the two lines under the
/// rule, and LAP — SpecRenderer.mc, line for line.
enum WatchSpecText {
    typealias Field = (label: String, value: String)

    /// The title parts that have something to say, two spaces apart; the
    /// exercise's name when none has.
    static func title(_ ex: WatchExercise, _ screen: WatchScreen, _ st: WatchStepState) -> String {
        let parts = screen.title.compactMap { titlePart($0, ex, screen, st) }
        return parts.isEmpty ? ex.name : parts.joined(separator: "  ")
    }

    /// The movement of the round in progress: an alternating interval's even
    /// rounds are its alternate (`alternateName`: Option C's hand-to-hand
    /// swings), as the Garmin's `WorkoutController.roundName` draws them.
    static func roundName(_ ex: WatchExercise, _ screen: WatchScreen, _ st: WatchStepState) -> String {
        guard let alt = ex.alternateName, screen.template == .interval, st.intervalRound % 2 == 0 else { return ex.name }
        return alt
    }

    private static func titlePart(_ id: WatchVocab.TitlePart, _ ex: WatchExercise, _ screen: WatchScreen,
                                  _ st: WatchStepState) -> String? {
        switch id {
        case .name:
            return roundName(ex, screen, st)
        case .load:
            // Sets show the working weight (Edit Set changes it); the rest the plan's.
            let w = screen.template == .sets ? st.weightKg : ex.weightKg
            return w.map { loadText(ex, $0) + " kg" }
        case .side:
            return sideTracked(ex, screen) ? (st.sideIsLeft ? "Left" : "Right") : nil
        case .switchSide:
            return ex.switchAtSec != nil ? (st.sideIsLeft ? "Left" : "Right") : nil
        case .wavePct:
            guard let wave = screen.behaviours.loadWave else { return nil }
            let i = st.intervalRound - 1
            return (i >= 0 && i < wave.count) ? "\(wave[i])%" : nil
        case .zoneOrLoad:
            if let z = ex.prescribedZoneLower {
                let hi = ex.prescribedZoneUpper
                return "Z\(z)" + ((hi != nil && hi != z) ? "-\(hi!)" : "")
            }
            return ex.weightKg.map { loadText(ex, $0) + " kg" }
        case .pack:
            return ex.packLoadKg.map { "pack \(kg($0)) kg" }
        }
    }

    static func fieldA(_ ex: WatchExercise, _ screen: WatchScreen, _ st: WatchStepState) -> Field? {
        field(screen.a, ex, screen, st)
    }
    static func fieldB(_ ex: WatchExercise, _ screen: WatchScreen, _ st: WatchStepState) -> Field? {
        field(screen.b, ex, screen, st)
    }
    static func gauge(_ ex: WatchExercise, _ screen: WatchScreen, _ st: WatchStepState) -> Field? {
        field(screen.gauge, ex, screen, st)
    }

    static func field(_ id: WatchVocab.Field?, _ ex: WatchExercise, _ screen: WatchScreen,
                      _ st: WatchStepState) -> Field? {
        guard let id else { return nil }
        switch id {
        case .reps:
            return ("REPS", "\(st.reps)")
        case .set:
            return setField(ex, screen, st)
        case .rpeOrSet:
            if ex.targetRpe != nil && st.weightKg == nil { return ("RPE", kg(st.rpe)) }
            return setField(ex, screen, st)
        case .cumulative:
            let done = "\(st.repsDone)"
            return ("TOTAL", screen.behaviours.cumulativeTarget.map { "\(done)/\($0)" } ?? done)
        case .rounds:
            return ("ROUNDS", "\(st.rounds)")
        case .roundsOfTarget:
            return ("ROUNDS", "\(st.rounds)" + (ex.targetRounds.map { "/\($0)" } ?? ""))
        case .rung:
            return ("RUNG", "\(Ladder.rung(st.rounds, peak: peak(screen)))")
        case .capLeft:
            return ("LEFT", mmss(st.capLeftSec))
        case .elapsed:
            return ("TIME", mmss(st.elapsedSec))
        case .timeLeft:
            // A timed step counts down and ends itself, as Garmin's do.
            if let mins = ex.durationMinutes, mins > 0 {
                return ("TIME LEFT", mmss(max(0, mins * 60 - st.elapsedSec)))
            }
            return ("TIME", mmss(st.elapsedSec))
        case .zoneOrTime:
            if let lo = ex.prescribedZoneLower {
                let hi = ex.prescribedZoneUpper
                return ("ZONE", (hi != nil && hi != lo) ? "\(lo)-\(hi!)" : "\(lo)")
            }
            // Counting down on the left, the time spent on the right; an open
            // block already shows its time on the left.
            return ex.durationMinutes != nil ? ("TIME", mmss(st.elapsedSec)) : nil
        case .distance:
            if isShortDistance(ex, screen) { return ("LAPS", "\(st.rounds)/\(setCount(ex, screen))") }
            return ("KM", kg(st.distanceKm))
        case .distanceTarget:
            if isShortDistance(ex, screen), let m = ex.distanceM { return ("METRES", "\(m)") }
            if let km = ex.distanceKm { return ("OF KM", kg(km)) }
            return ("TIME", mmss(st.elapsedSec))
        case .distanceKm:
            return ("KM", kg(st.distanceKm))
        case .hold:
            return ("HOLD", secs(st.holdRunning ? st.holdLeftSec : (ex.holdSeconds ?? 30)))
        case .interval:
            if !st.intervalWorking && st.intervalRestSec > 0 {
                if st.gateRest { return ("REST", mmss(st.restPhaseElapsedSec)) }
                return (restLabel(ex, screen).uppercased(), intervalRounds(st))
            }
            if let r = rpm(ex, screen) { return ("RPM", "\(r)") }
            return (isRunInterval(ex, screen) ? "INTERVAL" : "ROUND", intervalRounds(st))
        case .intervalLeft:
            if st.gateRest && !st.intervalWorking, let gate = ex.restUntilHr {
                return ("HR TO \(gate)", st.heartRate.map(String.init) ?? "--")
            }
            return ("TIME LEFT", secs(st.intervalLeftSec))
        case .intervalRound:
            return (isRunInterval(ex, screen) ? "INTERVAL" : "ROUND", intervalRounds(st))
        case .blockLeft:
            if let l = blockLeft(ex, st) { return ("LEFT", mmss(l)) }
            return ("TIME", mmss(st.elapsedSec))
        case .rpm:
            return ("RPM", rpm(ex, screen).map(String.init) ?? "--")
        case .packKg:
            return ("PACK KG", ex.packLoadKg.map(kg) ?? "--")
        case .hr:
            return ("HR", st.heartRate.map(String.init) ?? "--")
        }
    }

    /// The two lines under the rule; the second may be empty. The Garmin's
    /// prompt says "Press LAP"; the Apple Watch passes its own button's word.
    static func lines(_ ex: WatchExercise, _ screen: WatchScreen, _ st: WatchStepState,
                      lapWord: String = "LAP") -> (String, String?) {
        let next = "Next: \(st.nextTitle)"
        let byDefault = (next, st.nextValue)
        guard let id = screen.lines else { return byDefault }
        switch id {
        case .nextStep:
            return byDefault
        case .focus:
            return ex.focus.map { ($0, next) } ?? byDefault
        case .lastThenNext:
            // What was done last time, to beat — until this exercise's first
            // set is done (and never over a rest, which says what comes next).
            if let last = ex.lastTime, st.setsDone == 0, !st.resting { return ("Last time", last) }
            return byDefault
        case .components:
            // The step's own movement leads when it has a count (Fran's
            // thrusters, Cindy's pull-ups), then the movements folded into it.
            let own = WatchStepState.Component(name: ex.name, repsPerRound: ex.repsPerRound,
                                               repScheme: ex.repScheme)
            let all = (own.reps(inRound: 0) != nil ? [own] : []) + st.components
            guard !st.components.isEmpty || own.reps(inRound: 0) != nil else { return byDefault }
            let round = all.prefix(3)
                .map { c in (c.reps(inRound: st.rounds).map { "\($0) " } ?? "") + c.name }
                .joined(separator: "  ")
            return (round, next)
        case .ladderTotal:
            return ("\(Ladder.total(st.rounds, peak: peak(screen))) reps total", next)
        case .holdPrompt:
            return st.holdRunning ? ("Holding", "\(lapWord) ends early") : ("Press \(lapWord)", "to start the hold")
        case .intervalNext:
            let more = st.intervalTotal <= 0 || st.intervalRound < st.intervalTotal
            if st.intervalWorking && st.intervalRestSec > 0 {
                return ("Next: \(restLabel(ex, screen))", restValue(ex, st))
            }
            if more { return ("Next: \(workLabel(ex, screen))", workValue(ex, screen, st)) }
            return byDefault
        case .phases:
            guard !screen.phases.isEmpty else { return byDefault }
            return (screen.phases.joined(separator: " > "), next)
        case .standardTarget:
            // A test step: the best to beat and the number for the next level.
            guard let st0 = ex.standard else { return byDefault }
            return (st0.best.map { "Best \($0)" } ?? "First result", st0.target ?? next)
        }
    }

    /// What LAP does now (SpecRenderer.onLap and its logRound).
    static func lap(_ ex: WatchExercise, _ screen: WatchScreen, _ st: WatchStepState) -> WatchLapOutcome {
        switch screen.lap {
        case .skip:
            return .next
        case .completeSet:
            return .completeSet
        case .toggleHold:
            return st.holdRunning ? .stopHold : .startHold
        case .nextSide:
            return .nextSide
        case .logRound:
            switch screen.template {
            case .rounds:
                let cap = ex.timeMinutes ?? 0
                return (cap > 0 && st.capLeftSec <= 0) ? .next : .logRound
            case .forTime:
                // A test over a distance with no rounds to count (2 km, 3
                // miles): LAP stops the clock, which is the result.
                if ex.targetRounds == nil && ex.standard != nil && (ex.distanceKm != nil || ex.distanceM != nil) {
                    return .next
                }
                if let t = ex.targetRounds, st.rounds + 1 >= t { return .logRoundAndNext }
                return .logRound
            case .distance:
                guard isShortDistance(ex, screen) else { return .next }
                return st.rounds + 1 >= setCount(ex, screen) ? .logRoundAndNext : .logRound
            case .roundTimer:
                if let l = blockLeft(ex, st), l == 0 { return .next }
                return .logRound
            case .sets, .hold, .interval, .timed:
                return .logRound
            }
        }
    }

    // MARK: helpers (Steps.mc, WorkoutController.mc)

    /// Counted per side: a unilateral movement, or a package that says so (a
    /// get-up is bilateral in the library but trained one side at a time).
    static func sideTracked(_ ex: WatchExercise, _ screen: WatchScreen) -> Bool {
        ex.bilateral == false || screen.behaviours.sideTracked == true
    }

    /// The exercise's pace, else the package's metronome default.
    static func rpm(_ ex: WatchExercise, _ screen: WatchScreen) -> Int? {
        ex.targetRpm ?? screen.behaviours.metronomeRpm
    }

    /// Bells held at once: 2 for a double (the exercise's `bells`, sent by
    /// the server), else 1.
    static func bells(_ ex: WatchExercise) -> Int {
        ex.bells ?? 1
    }

    /// "2x24" for a double, else "24": weights are per bell.
    static func loadText(_ ex: WatchExercise, _ w: Double) -> String {
        let b = bells(ex)
        return b > 1 ? "\(b)x\(kg(w))" : kg(w)
    }

    static func isShortDistance(_ ex: WatchExercise, _ screen: WatchScreen) -> Bool {
        screen.template == .distance && ex.distanceM != nil && ex.distanceKm == nil
    }

    static func setCount(_ ex: WatchExercise, _ screen: WatchScreen) -> Int {
        let setBased = screen.template == .sets || screen.template == .hold
        guard setBased || isShortDistance(ex, screen) else { return 1 }
        return max(ex.sets ?? 1, 1)
    }

    private static func setField(_ ex: WatchExercise, _ screen: WatchScreen, _ st: WatchStepState) -> Field {
        let n = setCount(ex, screen)
        return ("SET", "\(min(st.setsDone + 1, n))/\(n)")
    }

    private static func intervalRounds(_ st: WatchStepState) -> String {
        "\(st.intervalRound)" + (st.intervalTotal > 0 ? "/\(st.intervalTotal)" : "")
    }

    private static func blockLeft(_ ex: WatchExercise, _ st: WatchStepState) -> Int? {
        ex.durationMinutes.map { max(0, $0 * 60 - st.elapsedSec) }
    }

    private static func peak(_ screen: WatchScreen) -> Int { screen.behaviours.ladderPeak ?? 20 }

    /// A run's intervals say Run / Recover; anything else Work / Rest.
    static func isRunInterval(_ ex: WatchExercise, _ screen: WatchScreen) -> Bool {
        ex.prescribedZoneLower != nil && rpm(ex, screen) == nil && isLocomotion(ex, screen)
    }

    private static func isLocomotion(_ ex: WatchExercise, _ screen: WatchScreen) -> Bool {
        if ex.category == "aerobic" { return true }
        if ex.movementPattern == "aerobic_monostructural" || ex.movementPattern == "locomotion" { return true }
        return screen.template == .distance && ex.distanceKm != nil
    }

    private static func workLabel(_ ex: WatchExercise, _ screen: WatchScreen) -> String {
        isRunInterval(ex, screen) ? "Run" : "Work"
    }
    private static func restLabel(_ ex: WatchExercise, _ screen: WatchScreen) -> String {
        isRunInterval(ex, screen) ? "Recover" : "Rest"
    }

    private static func workValue(_ ex: WatchExercise, _ screen: WatchScreen, _ st: WatchStepState) -> String {
        let t = mmss(st.intervalWorkSec)
        if let r = rpm(ex, screen) { return "\(t)  \(r) RPM" }
        if let z = ex.prescribedZoneLower {
            let hi = ex.prescribedZoneUpper
            return "\(t)  Zone \(z)" + ((hi != nil && hi != z) ? "-\(hi!)" : "")
        }
        return t
    }

    private static func restValue(_ ex: WatchExercise, _ st: WatchStepState) -> String {
        ex.restUntilHr.map { "until HR \($0)" } ?? mmss(st.intervalRestSec)
    }

    // MARK: text (Text.mc)

    /// "4:07" / "1:02:33"
    static func mmss(_ sec: Int) -> String {
        let s = max(0, sec)
        let h = s / 3600, m = (s % 3600) / 60, r = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, r) : String(format: "%d:%02d", m, r)
    }

    /// ":47" — a bare seconds countdown, for intervals and holds.
    static func secs(_ sec: Int) -> String {
        let s = max(0, sec)
        return s >= 60 ? mmss(s) : String(format: ":%02d", s)
    }

    /// 82.5 -> "82.5", 80.0 -> "80"
    static func kg(_ v: Double) -> String {
        v == v.rounded() ? String(format: "%d", Int(v)) : String(format: "%.1f", v)
    }
}

/// Rungs climb 1..peak and come back down to 1.
enum Ladder {
    /// The rung for a completed-round index (0-based).
    static func rung(_ roundIdx: Int, peak: Int) -> Int {
        let r = roundIdx + 1
        if r <= peak { return r }
        return max(1, peak - (r - peak))
    }

    /// Cumulative reps after n completed rungs.
    static func total(_ rounds: Int, peak: Int) -> Int {
        (0..<max(0, rounds)).reduce(0) { $0 + rung($1, peak: peak) }
    }
}
