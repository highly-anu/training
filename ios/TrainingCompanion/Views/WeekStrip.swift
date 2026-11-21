import SwiftUI

/// Monday to Sunday of the week on show, one mark a day: done, planned (in its
/// session's modality colour) or rest, over a bar with one segment per session
/// in that session's colour, so a done day still says what it was. A tap
/// selects the day, so the strip is the day pager's second control
/// (design-system §6.50).
struct WeekStrip: View {
    enum Status: Equatable { case done, planned, rest }

    struct Day: Identifiable {
        let offset: Int
        let date: Date
        let status: Status
        /// The day's sessions in order: each one's modality colour and name.
        let sessions: [Session]
        let isToday: Bool
        /// Whether the pager reaches this day.
        let isEnabled: Bool
        var id: Int { offset }
    }

    struct Session: Equatable {
        let color: Color
        let label: String
    }

    /// The bar under a day's mark: its height, its whole width, the gap between segments.
    private static let barHeight: CGFloat = 3
    private static let barWidth: CGFloat = 20
    private static let barGap: CGFloat = 2

    let days: [Day]
    @Binding var selection: Int

    private static let letter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEEE"; return f
    }()
    private static let spoken: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE d MMMM"; return f
    }()

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days) { day in
                Button {
                    AppHaptics.selection()
                    selection = day.offset
                } label: {
                    cell(day)
                }
                .buttonStyle(.plain)
                .disabled(!day.isEnabled)
                .accessibilityLabel(Self.label(day))
                .accessibilityAddTraits(day.offset == selection ? .isSelected : [])
            }
        }
    }

    private func cell(_ day: Day) -> some View {
        let selected = day.offset == selection
        return VStack(spacing: AppMetrics.gapTight) {
            Text(Self.letter.string(from: day.date))
                .font(.caption2.weight(day.isToday ? .bold : .medium))
                .foregroundStyle(day.isToday ? AnyShapeStyle(AppColor.accent) : AnyShapeStyle(.secondary))
            mark(day)
                .frame(height: 16)
            bar(day)
        }
        .padding(.vertical, AppMetrics.gapTight)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(selected ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: AppMetrics.radiusControl))
        .opacity(day.isEnabled ? 1 : 0.4)
        .contentShape(Rectangle())
    }

    /// One image whose symbol follows the day, so a day done fills its dot in
    /// place (§6.56) rather than swapping one view for another.
    private func mark(_ day: Day) -> some View {
        let symbol: String, font: Font, style: AnyShapeStyle
        switch day.status {
        case .done:
            (symbol, font, style) = ("checkmark.circle.fill", .footnote, AnyShapeStyle(AppColor.complete))
        case .planned:
            (symbol, font, style) = ("circle.fill", .caption2, AnyShapeStyle(day.sessions.first?.color ?? AppColor.accent))
        case .rest:
            (symbol, font, style) = ("minus", .caption2.weight(.semibold), AnyShapeStyle(.tertiary))
        }
        return Image(systemName: symbol)
            .font(font)
            .foregroundStyle(style)
            .appSymbolReplace(value: day.status)
    }

    /// One segment a session, in its colour; a rest day keeps the space so the
    /// marks stay on one line.
    private func bar(_ day: Day) -> some View {
        HStack(spacing: Self.barGap) {
            ForEach(Array(day.sessions.enumerated()), id: \.offset) { _, session in
                Capsule().fill(session.color)
            }
        }
        .frame(width: Self.barWidth, height: Self.barHeight)
        .accessibilityHidden(true)
    }

    /// "Friday 20 November, Power, done" — the bar's colours in words.
    static func label(_ day: Day) -> String {
        let what: String
        switch day.status {
        case .done: what = "done"
        case .planned: what = "planned"
        case .rest: what = "rest"
        }
        var names: [String] = []
        for session in day.sessions where !names.contains(session.label) { names.append(session.label) }
        let kinds = names.isEmpty ? "" : ", " + names.joined(separator: " and ")
        return "\(Self.spoken.string(from: day.date))\(kinds), \(what)\(day.isToday ? ", today" : "")"
    }
}
