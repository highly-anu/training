import SwiftUI

/// Every plan the athlete has trained, and the dates each was in force.
///
/// The server kept one program per athlete and overwrote it, so a finished block
/// left nothing behind — and a workout dated inside one could never be matched
/// to what had actually been planned for that day. `src/program_history.py`
/// archives each version with its interval; this reads that archive.
///
/// Read-only by construction: these rows are the record of what was prescribed
/// on each date, and editing them would destroy the thing the screen exists to
/// show.
struct ProgramHistoryView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.programHistory.isEmpty && appState.isLoadingHistory {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appState.programHistory.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .task { await appState.loadProgramHistory() }
        .refreshable { await appState.loadProgramHistory() }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No history yet")
                .font(.headline)
            Text("Your programs are recorded from the moment you first open or save one.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            ForEach(appState.programHistory) { entry in
                NavigationLink {
                    ProgramVersionDetailView(entry: entry)
                } label: {
                    ProgramHistoryRow(entry: entry)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct ProgramHistoryRow: View {
    let entry: ProgramHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(entry.displayName)
                    .font(.subheadline).fontWeight(.semibold)
                    .lineLimit(1)
                if entry.isActive {
                    Text("Active")
                        .font(.caption2).fontWeight(.semibold)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule())
                }
            }

            Text(ProgramHistoryFormat.span(entry))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Label("\(entry.weekCount) wk", systemImage: "calendar")
                Label("\(entry.sessionCount)", systemImage: "list.bullet")
                if entry.matchedCount > 0 {
                    Label("\(entry.matchedCount)", systemImage: "link")
                }
                if entry.loggedCount > 0 {
                    Label("\(entry.loggedCount)", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
        }
        .padding(.vertical, 2)
    }
}

/// One archived program, exactly as it was planned.
private struct ProgramVersionDetailView: View {
    let entry: ProgramHistoryEntry
    @EnvironmentObject var appState: AppState

    @State private var detail: ProgramHistoryDetail? = nil
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail {
                weekList(detail)
            } else {
                Text("Could not load this program.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(entry.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            detail = try? await appState.api?.fetchProgramVersion(entry.versionId)
            isLoading = false
        }
    }

    private func weekList(_ detail: ProgramHistoryDetail) -> some View {
        // Grouped by array position, not by the stored week number: a program
        // regenerated from an event date is numbered by its absolute week, so
        // the same number can appear at two positions.
        let byWeek = Dictionary(grouping: detail.sessions, by: \.weekIndex)
        let never = detail.sessions.filter { $0.wasEffective == false }.count

        return List {
            if never > 0 {
                Section {
                    Text("\(never) sessions were planned for weeks this program never reached — it was replaced first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(byWeek.keys.sorted(), id: \.self) { weekIndex in
                Section {
                    ForEach(byWeek[weekIndex] ?? []) { session in
                        PlannedSessionRow(session: session)
                    }
                } header: {
                    Text(ProgramHistoryFormat.weekHeader(
                        index: weekIndex, stored: byWeek[weekIndex]?.first?.weekNumber))
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct PlannedSessionRow: View {
    let session: PlannedSessionRecord

    private var ghost: Bool { session.wasEffective == false }

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 1)
                .fill(ModalityStyle.color(for: session.modality))
                .frame(width: 3, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.archetypeName ?? ModalityStyle.label(for: session.modality))
                    .font(.subheadline).fontWeight(.medium)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(ModalityStyle.label(for: session.modality))
                        .foregroundStyle(ModalityStyle.color(for: session.modality))
                    Text("· \(session.durationMinutes) min")
                        .foregroundStyle(.secondary)
                    if session.isDeload {
                        Text("· Deload").foregroundStyle(.secondary)
                    }
                }
                .font(.caption2)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(ProgramHistoryFormat.shortDate(session.date))
                    .font(.caption2).foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    if session.completedAt != nil {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    if session.matchedWorkoutId != nil {
                        Image(systemName: "link").foregroundStyle(.secondary)
                    }
                    if ghost {
                        Image(systemName: "slash.circle").foregroundStyle(.secondary)
                    }
                }
                .font(.caption2)
            }
        }
        .padding(.vertical, 2)
        .opacity(ghost ? 0.45 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    /// Colour and a glyph are never the only carriers of meaning.
    private var accessibilityText: String {
        var parts = [session.archetypeName ?? ModalityStyle.label(for: session.modality),
                     ModalityStyle.label(for: session.modality),
                     "\(session.durationMinutes) minutes",
                     ProgramHistoryFormat.shortDate(session.date)]
        if session.completedAt != nil { parts.append("logged") }
        if session.matchedWorkoutId != nil { parts.append("has a matched workout") }
        if ghost { parts.append("this plan was replaced before this week") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Formatting

enum ProgramHistoryFormat {
    private static let iso: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private static let display: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    private static let shortDisplay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        return f
    }()

    static func date(_ value: String) -> String {
        guard let d = iso.date(from: String(value.prefix(10))) else { return value }
        return display.string(from: d)
    }

    static func shortDate(_ value: String) -> String {
        guard let d = iso.date(from: String(value.prefix(10))) else { return value }
        return shortDisplay.string(from: d)
    }

    static func span(_ entry: ProgramHistoryEntry) -> String {
        let from = date(entry.effectiveFrom)
        guard let to = entry.effectiveTo else { return "\(from) — now" }
        return "\(from) — \(date(to))"
    }

    /// The stored week number can differ from the position; show both when they
    /// disagree rather than picking one and being wrong half the time.
    static func weekHeader(index: Int, stored: Int??) -> String {
        let position = index + 1
        if let stored = stored ?? nil, stored != position {
            return "Week \(position) (numbered \(stored))"
        }
        return "Week \(position)"
    }
}
