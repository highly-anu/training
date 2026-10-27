import SwiftUI

/// A composed program's tracks (ProgramComposition.swift, design-system
/// §6.22): each with its share of the week, the days it keeps, its own phases
/// across the program as a bar coloured by kind, and what it gave up to fit
/// beside the others — the server's words. Nothing for one track. Used by
/// Program ▸ Overview and the preview, so a composition reads the same in both.
struct CompositionTracks: View {
    let program: GeneratedProgram

    private static let dayShort = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        let lanes = program.compositionLanes
        if lanes.count > 1 {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(lanes, id: \.key) { lane in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(lane.name).font(.subheadline).fontWeight(.semibold)
                            Spacer()
                            Text(caption(lane)).font(.caption).foregroundStyle(.secondary)
                        }
                        phaseBar(lane)
                        ForEach(program.cuts(of: lane), id: \.self) { cut in
                            Label(cut, systemImage: "scissors")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
    }

    private func caption(_ lane: CompositionLane) -> String {
        var parts = ["\(Int((lane.weight * 100).rounded())) %", "\(lane.days) days"]
        if !lane.reservedDays.isEmpty {
            parts.append("keeps " + lane.reservedDays.compactMap { (1...7).contains($0) ? Self.dayShort[$0 - 1] : nil }
                .joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }

    /// The lane's weeks grouped by its own phase, as bar segments.
    private func phaseBar(_ lane: CompositionLane) -> some View {
        var segments: [(kind: String, name: String, weeks: Int)] = []
        for week in program.weeks {
            guard let at = week.lanes.first(where: { $0.laneKey == lane.key }) else { continue }
            let name = at.phaseName ?? at.phase.replacingOccurrences(of: "_", with: " ").capitalized
            if let last = segments.last, last.name == name { segments[segments.count - 1].weeks += 1 }
            else { segments.append((at.phase, name, 1)) }
        }
        return VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(PhaseStyle.color(for: seg.kind))
                            .frame(width: max(4, geo.size.width * CGFloat(seg.weeks) / CGFloat(max(program.weeks.count, 1)) - 2))
                    }
                }
            }
            .frame(height: 8)
            Text(segments.map { "\($0.name) \($0.weeks) wk" }.joined(separator: " · "))
                .font(.caption2).foregroundStyle(.secondary)
                .accessibilityLabel("Phases: " + segments.map { "\($0.name), \($0.weeks) weeks" }.joined(separator: "; "))
        }
    }
}

/// Which track of a composed program a session is: its methodology's short
/// name, and the track when the methodology offers several. Nothing for a
/// session of a one-track program.
struct TrackBadge: View {
    @EnvironmentObject var appState: AppState
    let session: ProgramSession

    var body: some View {
        if let key = session.laneKey {
            let parts = key.split(separator: "/").map(String.init)
            let phil = appState.philosophies.first { $0.id == parts.first }
            let name = (phil?.name ?? parts.first ?? key)
                .components(separatedBy: " /").first?.components(separatedBy: " —").first ?? key
            let track = (phil?.tracks?.count ?? 0) > 1 ? phil?.tracks?.first { $0.id == parts.last }?.name : nil
            Text(track.map { "\(name) · \($0)" } ?? name)
                .font(.caption2).foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .overlay(Capsule().stroke(Color.secondary.opacity(0.4)))
        }
    }
}
