import SwiftUI

/// Long-press actions on a program day or one of its sessions (design-system §6.43):
/// per session Move, Replace and — for one the athlete added and has not done —
/// Remove; for today or a later day, Add Session (an extra, counted once done).
/// Today's cards and Program ▸ Calendar's day rows share it; the session
/// detail screen carries none of these, and no screen shows an Add button.
struct SessionActions: ViewModifier {
    let weekIndex: Int
    let dayName: String
    /// The session the long-pressed card shows; nil for the whole day (a
    /// calendar row, a rest card), whose every session is offered.
    var sessionIndex: Int? = nil

    @EnvironmentObject var appState: AppState
    @State private var sheet: SheetKind?

    enum SheetKind: Identifiable {
        case add, move(Int), replace(Int)
        var id: String {
            switch self {
            case .add: return "add"
            case .move(let i): return "move-\(i)"
            case .replace(let i): return "replace-\(i)"
            }
        }
    }

    private var week: ProgramWeek? { appState.allWeeks[safe: weekIndex] }
    private var sessions: [ProgramSession] { week?.schedule[dayName] ?? [] }
    private var indices: [Int] {
        if let sessionIndex { return sessions.indices.contains(sessionIndex) ? [sessionIndex] : [] }
        return Array(sessions.indices)
    }
    private var canAdd: Bool {
        appState.api != nil && appState.canAddSession(weekIndex: weekIndex, dayName: dayName)
    }

    func body(content: Content) -> some View {
        if indices.isEmpty && !canAdd {
            content
        } else {
            content
                .contextMenu {
                    ForEach(indices, id: \.self) { i in
                        if indices.count > 1 {
                            Section(title(i)) { items(i) }
                        } else {
                            items(i)
                        }
                    }
                    if canAdd {
                        Button { sheet = .add } label: { Label("Add Session", systemImage: "plus") }
                    }
                }
                .sheet(item: $sheet) { kind in
                    sheetView(kind).environmentObject(appState)
                }
        }
    }

    private func title(_ i: Int) -> String {
        sessions[i].archetype?.name ?? ModalityStyle.label(for: sessions[i].modality)
    }

    @ViewBuilder
    private func items(_ i: Int) -> some View {
        Button { sheet = .move(i) } label: { Label("Move to Another Day", systemImage: "arrow.left.arrow.right") }
        if appState.api != nil {
            Button { sheet = .replace(i) } label: { Label("Replace", systemImage: "arrow.2.circlepath") }
        }
        // Only an extra the athlete added can go, and only before it is done.
        if sessions[i].isAdded, let week,
           !appState.isSessionComplete(appState.makeSessionKey(weekNumber: week.weekNumber, dayName: dayName, index: i)) {
            Button(role: .destructive) {
                appState.removeSession(weekIndex: weekIndex, day: dayName, sessionIndex: i)
            } label: {
                Label("Remove Added Session", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func sheetView(_ kind: SheetKind) -> some View {
        switch kind {
        case .add:
            if let api = appState.api {
                ReplaceWorkoutSheet(api: api, weekIndex: weekIndex, dayName: dayName, mode: .add)
            }
        case .move(let i):
            if let week {
                MoveWorkoutSheet(weekIndex: weekIndex, fromDay: dayName, sessionIndex: i, weekSchedule: week.schedule)
            }
        case .replace(let i):
            if let api = appState.api, let session = sessions[safe: i] {
                ReplaceWorkoutSheet(api: api, weekIndex: weekIndex, dayName: dayName, sessionIndex: i, session: session)
            }
        }
    }
}

extension View {
    /// Long-press Move / Replace / Remove for a session (or every session of the
    /// day), and Add Session for today or a later day (`SessionActions`).
    func sessionActions(weekIndex: Int, dayName: String, sessionIndex: Int? = nil) -> some View {
        modifier(SessionActions(weekIndex: weekIndex, dayName: dayName, sessionIndex: sessionIndex))
    }
}
