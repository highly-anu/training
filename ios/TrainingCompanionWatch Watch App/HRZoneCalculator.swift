import Foundation

struct HRZoneCalculator {
    // Friel/Coggan zones (1-indexed: Z1=recovery … Z5=VO2max)
    // Z1 <60%, Z2 60–70%, Z3 70–80%, Z4 80–90%, Z5 ≥90%

    static func zone(for bpm: Int, maxHR: Int) -> Int {
        guard maxHR > 0 else { return 1 }
        let pct = Double(bpm) / Double(maxHR)
        switch pct {
        case ..<0.60:           return 1
        case 0.60..<0.70:       return 2
        case 0.70..<0.80:       return 3
        case 0.80..<0.90:       return 4
        default:                return 5
        }
    }

    static func bpmBounds(zone: Int, maxHR: Int) -> (lower: Int, upper: Int) {
        let pcts: [(Double, Double)] = [
            (0.00, 0.60), (0.60, 0.70), (0.70, 0.80), (0.80, 0.90), (0.90, 1.00)
        ]
        let idx = max(0, min(4, zone - 1))
        return (Int(pcts[idx].0 * Double(maxHR)), Int(pcts[idx].1 * Double(maxHR)))
    }

    /// "Zone 1–2 (conversational pace)" → (lower: 1, upper: 2)
    static func parseZoneRange(_ target: String?) -> (lower: Int, upper: Int)? {
        guard let s = target else { return nil }
        let pattern = /[Zz]one\s*(\d)(?:\s*[-–]\s*(\d))?/
        guard let m = try? pattern.firstMatch(in: s),
              let lower = Int(m.output.1) else { return nil }
        let upper = m.output.2.flatMap { Int($0) } ?? lower
        return (lower, upper)
    }

    /// "Tabata 8×20/10" → (rounds: 8, workSec: 20, restSec: 10)
    static func parseEMOMFormat(_ format: String?) -> (rounds: Int, workSec: Int, restSec: Int) {
        let fallback = (rounds: 10, workSec: 60, restSec: 0)
        guard let s = format else { return fallback }
        let pattern = /(\d+)\s*[×x]\s*(\d+)\s*\/\s*(\d+)/
        guard let m = try? pattern.firstMatch(in: s),
              let rounds  = Int(m.output.1),
              let workSec = Int(m.output.2),
              let restSec = Int(m.output.3) else { return fallback }
        return (rounds, workSec, restSec)
    }
}
