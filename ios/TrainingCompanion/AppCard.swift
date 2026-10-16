import SwiftUI

/// The analytics card: an uppercase caption header over content, on the
/// secondary background with the app's card radius (design-system §6.15).
/// Overview and Recovery each carried a private copy of this; the Program
/// section is the third user, which is the §1.7 threshold for extracting it.
/// The header may carry a trailing view — a status badge — so a card's
/// verdict sits beside its name rather than on a row of its own.
struct AnalyticsCard<Content: View, Trailing: View>: View {
    let header: String
    @ViewBuilder let trailing: () -> Trailing
    @ViewBuilder let content: () -> Content

    init(header: String, @ViewBuilder content: @escaping () -> Content) where Trailing == EmptyView {
        self.header = header
        self.trailing = { EmptyView() }
        self.content = content
    }

    init(header: String, @ViewBuilder trailing: @escaping () -> Trailing,
         @ViewBuilder content: @escaping () -> Content) {
        self.header = header
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(header)
                    .font(.footnote).fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .lineLimit(2)
                Spacer(minLength: 0)
                trailing()
            }
            content()
        }
        .padding(AppMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius))
    }
}
