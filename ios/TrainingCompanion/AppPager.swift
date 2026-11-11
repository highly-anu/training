import SwiftUI

// Pages the athlete swipes between — Today's days, Calendar's weeks
// (design-system §6.49). The swipe is the shortcut; `AppPagerHeader` is the
// control that says the pages are there.

// MARK: - Model

/// Which pages there are and where a step lands. Pure: `PagingTests`.
enum Paging {
    /// The days Today can show, as offsets from today: the program's span,
    /// at most `reach` days either way, always with today in it.
    static func dayRange(today: Date, programStart: Date?, weeks: Int,
                         calendar: Calendar = .current, reach: Int = 56) -> ClosedRange<Int> {
        guard let programStart, weeks > 0 else { return -7...7 }
        let from = calendar.startOfDay(for: today)
        let first = calendar.dateComponents([.day], from: from, to: calendar.startOfDay(for: programStart)).day ?? 0
        let last = first + weeks * 7 - 1
        return max(min(first, 0), -reach)...min(max(last, 0), reach)
    }

    /// The Monday-to-Sunday week `offset` falls in, as offsets from today.
    static func week(around offset: Int, today: Date, calendar: Calendar = .current) -> [Int] {
        let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: today)) ?? today
        // Calendar's weekday: 1 is Sunday. Monday first, as the program's weeks.
        let fromMonday = (calendar.component(.weekday, from: date) + 5) % 7
        return (0..<7).map { offset - fromMonday + $0 }
    }

    /// The page `delta` away, or nil at the end.
    static func step(_ page: Int, by delta: Int, in pages: ClosedRange<Int>) -> Int? {
        let next = page + delta
        return pages.contains(next) ? next : nil
    }
}

// MARK: - Pager

/// One page at a time, full width, swiped sideways. `selection` is the page
/// shown; setting it from outside (a chevron, a day dot) scrolls there.
struct AppPager<Page: View>: View {
    let pages: ClosedRange<Int>
    @Binding var selection: Int
    /// The screen's side margin, kept inside each page so a page slides
    /// edge to edge.
    var inset: CGFloat = AppMetrics.gapLarge
    /// The pager is as tall as the page on show, not as the tallest page:
    /// for pages of very different heights (a rest day beside three
    /// sessions), so what follows the pager sits under the page.
    var fitsPage = false
    @ViewBuilder let page: (Int) -> Page

    @State private var position: Int?
    @State private var heights: [Int: CGFloat] = [:]

    init(pages: ClosedRange<Int>, selection: Binding<Int>, inset: CGFloat = AppMetrics.gapLarge,
         fitsPage: Bool = false, @ViewBuilder page: @escaping (Int) -> Page) {
        self.pages = pages
        self._selection = selection
        self.inset = inset
        self.fitsPage = fitsPage
        self.page = page
        self._position = State(initialValue: selection.wrappedValue)
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 0) {
                ForEach(Array(pages), id: \.self) { index in
                    measured(index)
                        .padding(.horizontal, inset)
                        .containerRelativeFrame(.horizontal)
                        .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $position)
        .frame(height: fitsPage ? heights[selection] : nil, alignment: .top)
        .animation(AppAnimation.layoutChange, value: fitsPage ? heights[selection] : nil)
        .onChange(of: position) {
            guard let position, position != selection else { return }
            AppHaptics.soft()
            selection = position
        }
        .onChange(of: selection) {
            guard position != selection else { return }
            withAnimation(AppAnimation.springStandard) { position = selection }
        }
    }
}

extension AppPager {
    /// A page at its own height, reported when the pager fits its page.
    @ViewBuilder
    fileprivate func measured(_ index: Int) -> some View {
        if fitsPage {
            page(index)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[index] = $0 }
        } else {
            page(index)
        }
    }
}

// MARK: - Header

/// The pager's visible control: a chevron either side of a title that says
/// which page this is. The title is a button when `onTitle` is given — back
/// to today, back to the current week.
struct AppPagerHeader<Title: View>: View {
    let pages: ClosedRange<Int>
    @Binding var selection: Int
    /// What a chevron moves by, for VoiceOver: "day", "week".
    let unit: String
    var onTitle: (() -> Void)? = nil
    @ViewBuilder let title: () -> Title

    var body: some View {
        HStack(spacing: AppMetrics.gapSmall) {
            chevron(-1, symbol: "chevron.left", label: "Previous \(unit)")
            if let onTitle {
                Button {
                    AppHaptics.light()
                    onTitle()
                } label: {
                    title().frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                title().frame(maxWidth: .infinity, alignment: .leading)
            }
            chevron(1, symbol: "chevron.right", label: "Next \(unit)")
        }
    }

    private func chevron(_ delta: Int, symbol: String, label: String) -> some View {
        let target = Paging.step(selection, by: delta, in: pages)
        return Button {
            guard let target else { return }
            selection = target
        } label: {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(width: 36, height: 36)
                .background(.fill.tertiary, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(target == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(AppColor.accent))
        .disabled(target == nil)
        .accessibilityLabel(label)
    }
}
