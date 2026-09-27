import SwiftUI

/// The one way a screen offers "over what period".
///
/// `period` is shared state across the Analytics sub-tabs, but its only control
/// used to be inline in Overview — so the Workouts list was silently filtered
/// by a choice made on another screen, and its empty state advised "try a
/// longer period" while offering no way to do that.
///
/// See §6.11 of `ios/docs/design-system.md`. The haptic and the animation live
/// in here, not at the call site: a rule that can only be followed by
/// remembering it will eventually not be.
struct AnalyticsPeriodPicker: View {
    @Binding var period: AnalyticsPeriod

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AnalyticsPeriod.allCases) { p in
                Button {
                    AppHaptics.selection()
                    withAnimation(AppAnimation.springSnappy) { period = p }
                } label: {
                    Text(p.label)
                        .font(.subheadline).fontWeight(period == p ? .semibold : .regular)
                        .foregroundStyle(period == p ? Color.white : Color.primary)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(period == p ? Color.blue : Color(.systemGray5))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
