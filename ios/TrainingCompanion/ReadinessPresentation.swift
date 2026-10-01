import SwiftUI

/// Colour and label helpers for the two readiness shapes: the on-device
/// heuristic sent to the watch (`ReadinessInfo`) and the API-computed score
/// (`ReadinessResult`). Lived in the dead LogView until it was removed.

// MARK: - ReadinessInfo color helpers (used by Watch connectivity display)

extension ReadinessInfo {
    var signalColor: Color {
        switch signal {
        case "green":  return .green
        case "yellow": return .yellow
        default:       return .red
        }
    }
    var signalIcon: String {
        switch signal {
        case "green":  return "bolt.heart.fill"
        case "yellow": return "exclamationmark.heart.fill"
        default:       return "heart.slash.fill"
        }
    }
}

// MARK: - ReadinessResult display helpers (API-computed score)

extension ReadinessResult {
    var statusColor: Color {
        switch status {
        case "green":  return .green
        case "yellow": return .yellow
        default:       return .red
        }
    }
    var statusLabel: String {
        switch status {
        case "green":  return "Ready"
        case "yellow": return "Moderate"
        default:       return "Low"
        }
    }
}
