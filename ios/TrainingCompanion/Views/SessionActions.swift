import SwiftUI
import TipKit

/// What a program day or one of its sessions can do (design-system §6.43):
/// per session Move, Replace and — for one the athlete added and has not done —
/// Remove; for today or a later day, Add Session (an extra, counted once done).
/// One set of items, three ways in: the long press (`sessionActions`), the
/// visible "…" (`SessionActionsMenu`) and a rest day's `SessionAddButton`.
/// Today's cards and Program ▸ Calendar's day rows share them; the session
/// detail screen carries none of these.
struct SessionActionSet {
    let appState: AppState
    let weekIndex: Int
    let dayName: String
    /// One session's actions; nil for the whole day (a calendar row, a rest
    /// card), whose every session is offered.
    var sessionIndex: Int? = nil

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
    var canAdd: Bool {
        appState.api != nil && appState.canAddSession(weekIndex: weekIndex, dayName: dayName)
    }
    /// Nothing to offer: a past rest day.
    var isEmpty: Bool { indices.isEmpty && !canAdd }

    @ViewBuilder
    func items(_ sheet: Binding<SheetKind?>) -> some View {
        ForEach(indices, id: \.self) { i in
            if indices.count > 1 {
                Section(title(i)) { items(i, sheet) }
            } else {
                items(i, sheet)
            }
        }
        if canAdd {
            Button { sheet.wrappedValue = .add } label: { Label("Add Session", systemImage: "plus") }
        }
    }

    private func title(_ i: Int) -> String {
        sessions[i].archetype?.name ?? ModalityStyle.label(for: sessions[i].modality)
    }

    @ViewBuilder
    private func items(_ i: Int, _ sheet: Binding<SheetKind?>) -> some View {
        Button { sheet.wrappedValue = .move(i) } label: { Label("Move to Another Day", systemImage: "arrow.left.arrow.right") }
        if appState.api != nil {
            Button { sheet.wrappedValue = .replace(i) } label: { Label("Replace", systemImage: "arrow.2.circlepath") }
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
    func sheetView(_ kind: SheetKind) -> some View {
        switch kind {
        case .add:
            if let api = appState.api {
                ReplaceWorkoutSheet(api: api, weekIndex: weekIndex, dayName: dayName, mode: .add)
            }
        case .move(let i):
            if let week {
                MoveWorkoutSheet(weekIndex: weekIndex, fromDay: dayName, sessionIndex: i, weekSchedule: week.schedule)
                    .appSheet(.compact)
            }
        case .replace(let i):
            if let api = appState.api, let session = sessions[safe: i] {
                ReplaceWorkoutSheet(api: api, weekIndex: weekIndex, dayName: dayName, sessionIndex: i, session: session)
            }
        }
    }
}

// MARK: - Long press

/// The shortcut: the same items on a long press of the card or row.
struct SessionActions: ViewModifier {
    let weekIndex: Int
    let dayName: String
    var sessionIndex: Int? = nil

    @EnvironmentObject var appState: AppState
    @State private var sheet: SessionActionSet.SheetKind?

    func body(content: Content) -> some View {
        let set = SessionActionSet(appState: appState, weekIndex: weekIndex, dayName: dayName, sessionIndex: sessionIndex)
        if set.isEmpty {
            content
        } else {
            content
                .contextMenu { set.items($sheet) }
                .sheet(item: $sheet) { kind in
                    set.sheetView(kind).environmentObject(appState)
                }
        }
    }
}

extension View {
    /// Long-press Move / Replace / Remove for a session (or every session of the
    /// day), and Add Session for today or a later day (`SessionActionSet`).
    func sessionActions(weekIndex: Int, dayName: String, sessionIndex: Int? = nil) -> some View {
        modifier(SessionActions(weekIndex: weekIndex, dayName: dayName, sessionIndex: sessionIndex))
    }
}

// MARK: - Visible controls

/// The "…" at the trailing edge of a session card or a day row: the same
/// items as the long press. Draws nothing when the day offers none.
struct SessionActionsMenu: View {
    let weekIndex: Int
    let dayName: String
    var sessionIndex: Int? = nil
    /// Whether this one may carry the tip (one per screen: today's first card).
    var showsTip = false

    @EnvironmentObject var appState: AppState
    @State private var sheet: SessionActionSet.SheetKind?
    private let tip = SessionActionsTip()

    var body: some View {
        let set = SessionActionSet(appState: appState, weekIndex: weekIndex, dayName: dayName, sessionIndex: sessionIndex)
        if !set.isEmpty {
            Menu {
                set.items($sheet)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Session actions")
            .popoverTip(showsTip ? tip : nil, arrowEdge: .trailing)
            .sheet(item: $sheet) { kind in
                set.sheetView(kind).environmentObject(appState)
            }
        }
    }
}

/// A rest day's quiet "+ Add session", for today or a later day; nothing on
/// a day already behind the athlete.
struct SessionAddButton: View {
    let weekIndex: Int
    let dayName: String
    var title = "Add session"

    @EnvironmentObject var appState: AppState
    @State private var sheet: SessionActionSet.SheetKind?

    var body: some View {
        let set = SessionActionSet(appState: appState, weekIndex: weekIndex, dayName: dayName)
        if set.canAdd {
            Button {
                AppHaptics.light()
                sheet = .add
            } label: {
                Label(title, systemImage: "plus")
                    .font(.subheadline.weight(.medium))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppColor.accent)
            .accessibilityLabel("Add session")
            .sheet(item: $sheet) { kind in
                set.sheetView(kind).environmentObject(appState)
            }
        }
    }
}

/// Shown once, on today's first session.
struct SessionActionsTip: Tip {
    var title: Text { Text("Move, replace or add") }
    var message: Text? { Text("A session's actions are here. A long press on it opens the same menu.") }
    var image: Image? { Image(systemName: "hand.tap") }
    var options: [any TipOption] { [MaxDisplayCount(1)] }
}
