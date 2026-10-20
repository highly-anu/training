import Foundation

/// "Made every rep?" for a training contract's loaded lifts (Starting
/// Strength, `load_per_exposure`): which lifts the session asks about, and
/// what the confirm route gets — only the lifts that went otherwise than
/// written (a miss, a work-up's weight); every lift it does not name was made.
/// The web's `LiftProgress` (components/session/ModuleProgress.tsx) sends the
/// same body. Pure, so `LiftConfirmationTests` pins it.
enum LiftConfirmation {
    struct Lift: Identifiable, Equatable {
        let id: String
        let name: String
        /// The prescribed weight; nil on a work-up (the athlete records it).
        let weightKg: Double?
    }

    struct Answer: Equatable {
        var made = true
        var kg = ""
    }

    /// The session's lifts that move on what was made.
    static func lifts(of session: ProgramSession) -> [Lift] {
        session.exercises.compactMap { ea in
            guard let ex = ea.exercise,
                  case .bool(true)? = ea.load.extra["advances_module"],
                  case .string("load_per_exposure")? = ea.load.extra["progression_model"] else { return nil }
            return Lift(id: ex.id, name: ex.name, weightKg: ea.load.weightKg)
        }
    }

    /// (clean, lifts) for `POST /health/sessions/<key>/confirm`. `allMade` is
    /// the one-tap answer; a typed weight rides with the lift it belongs to.
    static func payload(_ lifts: [Lift], answers: [String: Answer], allMade: Bool)
        -> (clean: Bool, lifts: [String: APIClient.LiftOutcome]?) {
        var sent: [String: APIClient.LiftOutcome] = [:]
        var everyMade = true
        for lift in lifts {
            let answer = answers[lift.id] ?? Answer()
            let made = allMade || answer.made
            everyMade = everyMade && made
            let kg = Double(answer.kg.replacingOccurrences(of: ",", with: "."))
            let weight = (kg ?? 0) > 0 ? kg : nil
            if !made || weight != nil {
                sent[lift.id] = APIClient.LiftOutcome(made: made, weightKg: weight)
            }
        }
        return (everyMade, sent.isEmpty ? nil : sent)
    }

    /// What the log says: each lift made or missed, once every lift is answered.
    static func verdict(_ lifts: [Lift], log: SessionLogEntry?) -> [String: Bool]? {
        var out: [String: Bool] = [:]
        for lift in lifts {
            guard let made = log?.exercises[lift.id]?.made else { return nil }
            out[lift.id] = made
        }
        return lifts.isEmpty ? nil : out
    }
}
