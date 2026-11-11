import SwiftUI

/// What a screen shows before, instead of and after its content
/// (design-system §6.3, §7.3). One answer for every screen: until 1.36 a
/// failed program load said "No Program", ten screens drew their own empty
/// state and none had a placeholder.
enum AppLoadPhase: Equatable {
    case content
    case loading
    case failed(String)
    case empty

    /// Content wins: what is already on screen stays while a reload runs or
    /// fails. Then a load in flight, then the failure, and only a load that
    /// finished and found nothing is empty.
    static func resolve(hasContent: Bool, isLoading: Bool, error: String?) -> AppLoadPhase {
        if hasContent { return .content }
        if isLoading { return .loading }
        if let error { return .failed(error) }
        return .empty
    }
}

/// Nothing here yet, and the way forward when there is one.
struct AppEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionLabel: String? = nil
    /// The screen's one action (§6.6 `.primary`) rather than a way round.
    var prominent = false
    var action: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(message)
        } actions: {
            if let actionLabel, let action {
                Button(actionLabel) {
                    AppHaptics.light()
                    action()
                }
                .appButton(prominent ? .primary : .secondary)
            }
        }
    }
}

/// A load that failed with nothing to show in its place.
struct AppFailedState: View {
    var title = "Could not load"
    let message: String
    let retry: () async -> Void

    var body: some View {
        AppEmptyState(icon: "exclamationmark.triangle", title: title, message: message,
                      actionLabel: "Try again") { Task { await retry() } }
    }
}

/// A failed reload while the screen still has something to show: one row,
/// above the content, never in its place.
struct AppErrorBanner: View {
    let message: String
    let retry: () async -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppMetrics.gapSmall) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(AppColor.warning)
            Text(message).font(.footnote).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Try again") { Task { await retry() } }
                .font(.footnote.weight(.semibold))
        }
        .appCard(compact: true, tint: AppColor.warning)
        .accessibilityElement(children: .combine)
    }
}

/// The screen's own shape, redacted, while its first load runs (§7.3).
struct AppLoadingState: View {
    enum Shape { case cards, list }
    var shape: Shape = .cards
    /// What VoiceOver says; the placeholder itself is hidden from it.
    var label = "Loading"

    var body: some View {
        ScrollView {
            VStack(spacing: shape == .cards ? AppMetrics.gapLarge : AppMetrics.gapSmall) {
                switch shape {
                case .cards:
                    card(lines: 2)
                    card(lines: 4)
                    card(lines: 3)
                case .list:
                    ForEach(0..<7, id: \.self) { _ in row }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, AppMetrics.gapMedium)
        }
        .scrollDisabled(true)
        .redacted(reason: .placeholder)
        .modifier(Shimmer())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private func card(lines: Int) -> some View {
        VStack(alignment: .leading, spacing: AppMetrics.gapSmall) {
            Text("Section title").font(.caption).fontWeight(.semibold)
            Text("A headline for the card").font(.title3).fontWeight(.semibold)
            ForEach(0..<lines, id: \.self) { i in
                Text(i.isMultiple(of: 2) ? "A line of the card's content, about this long"
                                         : "A shorter line of content")
                    .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private var row: some View {
        HStack(spacing: AppMetrics.gapMedium) {
            RoundedRectangle(cornerRadius: AppMetrics.radiusControl, style: .continuous)
                .fill(.quaternary).frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: AppMetrics.gapTight) {
                Text("A row's title, this long").font(.subheadline).fontWeight(.medium)
                Text("Its caption, a little shorter").font(.caption)
            }
            Spacer()
        }
        .appCard(compact: true)
    }
}

/// A slow pulse over a placeholder; still under Reduce Motion.
private struct Shimmer: ViewModifier {
    func body(content: Content) -> some View {
        if AppAnimation.reduceMotion {
            content
        } else {
            content.phaseAnimator([false, true]) { view, dim in
                view.opacity(dim ? AppColor.Opacity.ghost : 1)
            } animation: { _ in AppAnimation.shimmer }
        }
    }
}
