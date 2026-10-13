import SwiftUI

/// A track's phases in order: each with its methodology's own name, its
/// length, and its focus line (design-system §6.22). The one rendering of a
/// phase list on the phone — the builder's track picker, the Program
/// settings sheet and the methodology sheet all use it, so a phase reads the
/// same wherever it is chosen or explained.
///
/// `showsDescriptions` adds each phase's description for the reference
/// context (the methodology sheet); a picker row leaves it off.
struct TrackPhaseList: View {
    let track: PhilosophyTrack
    var showsDescriptions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhaseStrip(phases: track.phases)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(track.phases) { phase in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Circle()
                                .fill(PhaseStyle.color(for: phase.kind))
                                .frame(width: 7, height: 7)
                            Text(phase.name)
                                .font(.caption).fontWeight(.semibold)
                            Text(weeksLabel(phase))
                                .font(.caption2).monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        if let focus = phase.focus, !focus.isEmpty {
                            Text(focus)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 13)
                        }
                        if showsDescriptions, let text = phase.description, !text.isEmpty {
                            Text(text)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, 13)
                                .padding(.top, 2)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func weeksLabel(_ phase: PhilosophyPhase) -> String {
        let weeks = "\(phase.weeks) wk"
        return phase.repeatable == true ? weeks + " · repeatable" : weeks
    }
}

/// The track's phases as one proportional bar, coloured by kind.
private struct PhaseStrip: View {
    let phases: [PhilosophyPhase]

    var body: some View {
        let total = max(phases.reduce(0) { $0 + $1.weeks }, 1)
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(phases) { phase in
                    Rectangle()
                        .fill(PhaseStyle.color(for: phase.kind).opacity(0.7))
                        .frame(width: max(geo.size.width * CGFloat(phase.weeks) / CGFloat(total) - 2, 2))
                }
            }
        }
        .frame(height: 6)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .accessibilityHidden(true)
    }
}
