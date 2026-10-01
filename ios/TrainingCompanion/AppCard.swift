import SwiftUI

/// The analytics card: an uppercase caption header over content, on the
/// secondary background with the app's card radius (design-system §6.15).
/// Overview and Recovery each carried a private copy of this; the Program
/// section is the third user, which is the §1.7 threshold for extracting it.
struct AnalyticsCard<Content: View>: View {
    let header: String
    @ViewBuilder let content: () -> Content

    init(header: String, @ViewBuilder content: @escaping () -> Content) {
        self.header = header
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(header)
                .font(.footnote).fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            content()
        }
        .padding(AppMetrics.cardPadding)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius))
    }
}
