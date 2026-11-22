import Foundation

/// What a training-contract session's answer earns. A module moves on only
/// on a clean session at or below its own RPE (`training_contract.clean_shortfall`
/// on the server, the one reading); this is that rule for the words the phone
/// writes beside a log — the verdict on a session, the log form's footer —
/// with the ceiling read from the session's module record, never a literal.
/// The web's `lib/moduleVerdict.ts` says the same; change both.
enum ModuleVerdict {
    enum Reading: Equatable {
        /// Clean, and at or below the module's RPE: it moves the module on.
        case clean
        /// Clean, but harder than the module allows: the cycle holds.
        case overRpe(ceiling: Int)
        case notClean
    }

    /// The RPE at or below which a clean session moves on the module this
    /// exercise's progress rides on; nil when the session carries no record
    /// for it (an older stored program, a block that earns nothing).
    static func ceiling(of session: ProgramSession, exercise id: String) -> Int? {
        guard case .array(let modules)? = session.extra["modules"] else { return nil }
        for module in modules {
            guard case .object(let record) = module,
                  case .array(let ids)? = record["exercise_ids"],
                  ids.contains(where: { $0.stringValue == id }) else { continue }
            switch record["max_rpe"] {
            case .int(let whole)?: return whole
            case .double(let number)?: return Int(number)
            default: continue
            }
        }
        return nil
    }

    static func read(clean: Bool, rpe: Int?, ceiling: Int?) -> Reading {
        guard clean else { return .notClean }
        if let rpe, let ceiling, rpe > ceiling { return .overRpe(ceiling: ceiling) }
        return .clean
    }

    /// The verdict in one line, as the session's Progress row says it.
    static func words(clean: Bool, rpe: Int?, ceiling: Int?) -> String {
        switch read(clean: clean, rpe: rpe, ceiling: ceiling) {
        case .clean: return "Clean, as written" + (rpe.map { " · RPE \($0)" } ?? "")
        case .overRpe(let ceiling): return "Clean · RPE \(rpe ?? 0) — over RPE \(ceiling), the cycle holds here"
        case .notClean: return "Not clean — the cycle holds here"
        }
    }

    /// "RPE 7 or below", in the module's own number.
    static func below(_ ceiling: Int?) -> String {
        ceiling.map { "RPE \($0) or below" } ?? "the module's RPE or below"
    }
}
