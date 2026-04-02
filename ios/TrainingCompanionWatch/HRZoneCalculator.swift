import Foundation

/// Swift port of frontend/src/lib/hrZones.ts (Friel/Coggan 5-zone model).
/// Zones are 1-indexed (Z1–Z5) to match the frontend display labels.
enum HRZoneCalculator {

    // Friel/Coggan upper boundaries as fraction of maxHR
    // Z1: < 60%, Z2: 60–70%, Z3: 70–80%, Z4: 80–90%, Z5: 90%+
    private static let upperBounds: [Double] = [0.60, 0.70, 0.80, 0.90, Double.infinity]

    /// Returns 1–5 for zones Z1–Z5, or 0 if maxHR is zero.
    static func zone(for bpm: Int, maxHR: Int) -> Int {
        guard maxHR > 0 else { return 0 }
        let pct = Double(bpm) / Double(maxHR)
        for (i, upper) in upperBounds.enumerated() {
            if pct < upper { return i + 1 }
        }
        return 5
    }

    /// Upper BPM bound for a given 1-indexed zone (exclusive upper edge).
    static func upperBPM(zone: Int, maxHR: Int) -> Int {
        guard zone >= 1, zone <= 5 else { return maxHR }
        let fraction = upperBounds[zone - 1]
        if fraction == Double.infinity { return maxHR }
        return Int(fraction * Double(maxHR))
    }

    /// Lower BPM bound for a given 1-indexed zone (inclusive).
    static func lowerBPM(zone: Int, maxHR: Int) -> Int {
        guard zone >= 2 else { return 0 }
        let fraction = upperBounds[zone - 2]
        return Int(fraction * Double(maxHR))
    }

    /// Max HR from date of birth string "YYYY-MM-DD". Returns nil if unparseable.
    static func maxHR(from dob: String) -> Int? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        guard let date = fmt.date(from: dob) else { return nil }
        let age = Calendar.current.dateComponents([.year], from: date, to: Date()).year ?? 30
        return 220 - age
    }

    /// Stored maxHR from UserDefaults (set by iPhone when syncing profile).
    static func storedMaxHR() -> Int {
        let stored = UserDefaults.standard.integer(forKey: "maxHR")
        if stored > 0 { return stored }
        // Fallback: derive from DOB if available
        if let dob = UserDefaults.standard.string(forKey: "dateOfBirth"),
           let hr = maxHR(from: dob) { return hr }
        return 185   // conservative default
    }

    /// Name string for a zone (Z1–Z5).
    static func zoneName(_ zone: Int) -> String {
        switch zone {
        case 1: return "Zone 1 — Recovery"
        case 2: return "Zone 2 — Aerobic Base"
        case 3: return "Zone 3 — Tempo"
        case 4: return "Zone 4 — Threshold"
        case 5: return "Zone 5 — VO₂ Max"
        default: return "Unknown Zone"
        }
    }

    /// Color (as a system color name string) for a zone.
    static func zoneColorName(_ zone: Int) -> String {
        switch zone {
        case 1: return "blue"
        case 2: return "green"
        case 3: return "yellow"
        case 4: return "orange"
        case 5: return "red"
        default: return "gray"
        }
    }
}
