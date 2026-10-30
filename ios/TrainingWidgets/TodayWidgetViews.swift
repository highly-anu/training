import WidgetKit
import SwiftUI

// MARK: - Root Entry View

struct TodayWidgetEntryView: View {
    var entry: TodayEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if let data = entry.todayData {
            switch family {
            case .systemSmall:  SmallTodayView(sessions: data.sessions)
            case .systemMedium: MediumTodayView(sessions: data.sessions)
            case .systemLarge:  LargeTodayView(sessions: data.sessions)
            default:            SmallTodayView(sessions: data.sessions)
            }
        } else {
            NoDataView()
        }
    }
}

// MARK: - Small Widget

struct SmallTodayView: View {
    let sessions: [WidgetSession]

    var body: some View {
        if sessions.isEmpty {
            restDayView
        } else if sessions.count == 1, let s = sessions.first {
            singleSessionLink(s)
        } else {
            multiSessionLink
        }
    }

    private var restDayView: some View {
        Link(destination: URL(string: "trainingcompanion://today")!) {
            VStack(spacing: 6) {
                Image(systemName: "battery.100.bolt")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                Text("Rest Day")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("Recovery is training.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func singleSessionLink(_ s: WidgetSession) -> some View {
        Link(destination: URL(string: "trainingcompanion://session?key=\(s.id)")!) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(symbol: WidgetModalityStyle.symbol(for: s))
                        .foregroundStyle(WidgetModalityStyle.color(for: s.modalityId))
                    Spacer()
                    Text(todayShortLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if s.isDeload {
                    Text("Deload")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Text(s.archetypeName)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text("\(s.estimatedMinutes) min · \(WidgetModalityStyle.label(for: s.modalityId))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(2)
        }
    }

    private var multiSessionLink: some View {
        Link(destination: URL(string: "trainingcompanion://today")!) {
            VStack(alignment: .leading, spacing: 4) {
                Text(todayShortLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(sessions.count) Sessions")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                ForEach(sessions.prefix(3)) { s in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(WidgetModalityStyle.color(for: s.modalityId))
                            .frame(width: 7, height: 7)
                        Text(s.archetypeName)
                            .font(.caption2)
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .padding(2)
        }
    }
}

// MARK: - Medium Widget

struct MediumTodayView: View {
    let sessions: [WidgetSession]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Today")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(todayShortLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 6)

            if sessions.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "battery.100.bolt")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Rest Day")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Recovery is training.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(sessions.prefix(2)) { s in
                        Link(destination: URL(string: "trainingcompanion://session?key=\(s.id)")!) {
                            SessionRowView(session: s)
                        }
                    }
                    if sessions.count > 2 {
                        Link(destination: URL(string: "trainingcompanion://today")!) {
                            Text("+ \(sessions.count - 2) more session\(sessions.count - 2 == 1 ? "" : "s")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .padding(2)
    }
}

// MARK: - Large Widget

struct LargeTodayView: View {
    let sessions: [WidgetSession]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Today's Training")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(todayShortLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 10)

            if sessions.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "battery.100.bolt")
                            .font(.largeTitle)
                            .foregroundStyle(.green)
                        Text("Rest Day")
                            .font(.headline)
                        Text("Recovery is training.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Spacer()
            } else {
                VStack(spacing: 8) {
                    ForEach(sessions) { s in
                        Link(destination: URL(string: "trainingcompanion://session?key=\(s.id)")!) {
                            LargeSessionRowView(session: s)
                        }
                    }
                }
            }
        }
        .padding(2)
    }
}

// MARK: - Reusable Row Views

struct SessionRowView: View {
    let session: WidgetSession

    var body: some View {
        HStack(spacing: 10) {
            Image(symbol: WidgetModalityStyle.symbol(for: session))
                .foregroundStyle(WidgetModalityStyle.color(for: session.modalityId))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.archetypeName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text("\(session.estimatedMinutes) min\(session.isDeload ? " · Deload" : "")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

struct LargeSessionRowView: View {
    let session: WidgetSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(symbol: WidgetModalityStyle.symbol(for: session))
                    .foregroundStyle(WidgetModalityStyle.color(for: session.modalityId))
                Text(session.archetypeName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Spacer()
                Text("\(session.estimatedMinutes) min")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !session.exerciseNames.isEmpty {
                Text(session.exerciseNames.prefix(3).joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(WidgetModalityStyle.color(for: session.modalityId).opacity(0.1))
        )
    }
}

struct NoDataView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "app.connected.to.app.below.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Open the app to sync your program")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Helpers

private var todayShortLabel: String {
    let f = DateFormatter()
    f.dateFormat = "EEE, MMM d"
    return f.string(from: Date())
}

// MARK: - Widget Modality Style
// Mirrors ModalityStyle.swift from the main target (cannot import across extensions)

/// The widgets' copy of the phone's ModalityStyle, from the same generated
/// table (ClientVocab.swift, tools/gen_client_vocab.py).
enum WidgetModalityStyle {
    static func color(for id: String) -> Color {
        ClientVocab.modalities[id].map { ClientVocab.color($0.hex) } ?? .secondary
    }

    static func label(for id: String) -> String {
        ClientVocab.modalities[id]?.label ?? id.replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// A session's workout icon (design-system §6.40), else its modality's.
    static func symbol(for session: WidgetSession) -> String {
        if let icon = session.icon, AppSymbol.custom.contains(icon) { return icon }
        return icon(for: session.modalityId)
    }

    static func icon(for id: String) -> String {
        ClientVocab.modalities[id]?.icon ?? "figure.strengthtraining.traditional"
    }
}
