import SwiftUI

/// Monday to Sunday of the week on show, one dot a day: done, planned (in its
/// session's modality colour) or rest. A tap selects the day, so the strip is
/// the day pager's second control (design-system §6.50).
struct WeekStrip: View {
    enum Status: Equatable { case done, planned, rest }

    struct Day: Identifiable {
        let offset: Int
        let date: Date
        let status: Status
        /// The first session's modality colour, for a planned day.
        let color: Color?
        let isToday: Bool
        /// Whether the pager reaches this day.
        let isEnabled: Bool
        var id: Int { offset }
    }

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
                .accessibilityLabel(label(day))
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
        }
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
            (symbol, font, style) = ("circle.fill", .caption2, AnyShapeStyle(day.color ?? AppColor.accent))
        case .rest:
            (symbol, font, style) = ("minus", .caption2.weight(.semibold), AnyShapeStyle(.tertiary))
        }
        return Image(systemName: symbol)
            .font(font)
            .foregroundStyle(style)
            .appSymbolReplace(value: day.status)
    }

    private func label(_ day: Day) -> String {
        let what: String
        switch day.status {
        case .done: what = "done"
        case .planned: what = "planned"
        case .rest: what = "rest"
        }
        return "\(Self.spoken.string(from: day.date)), \(what)\(day.isToday ? ", today" : "")"
    }
}
