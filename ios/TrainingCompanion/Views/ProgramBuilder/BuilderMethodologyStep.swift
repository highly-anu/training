import SwiftUI

// MARK: - Step 1: Methodology

/// Picks the philosophy the program is generated from.
///
/// This was a "goal" grid fed by `GET /api/goals`, a route removed on
/// 2026-04-25 when programs became philosophy-driven. The grid never
/// populated, so Next stayed disabled and no program could be generated from
/// the phone. The request has sent `philosophy_id` all along; this is the
/// picker that matches it.
struct BuilderStep1PhilosophyView: View {
    @ObservedObject var builder: BuilderState
    @EnvironmentObject var appState: AppState
    @State private var detail: PhilosophyCard? = nil
    @State private var loadFailed = false

    let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Choose a methodology")
                        .font(.headline)
                    Text("The training philosophy the program is built from — or up to four, blended into one program that shares your week. Tap ⓘ to read what each believes and how it trains.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                if appState.philosophies.isEmpty {
                    if loadFailed {
                        AppFailedState(title: "Couldn't load methodologies",
                                       message: "Check the connection and try again.") { await load() }
                    } else {
                        AppLoadingState(shape: .cards, label: "Loading methodologies")
                            .padding(.horizontal)
                    }
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(appState.philosophies) { philosophy in
                            philosophyCard(philosophy)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .task { await load() }
        .sheet(item: $detail) { philosophy in
            PhilosophyDetailSheet(philosophy: philosophy)
        }
    }

    private func load() async {
        loadFailed = false
        await appState.loadPhilosophiesIfNeeded()
        loadFailed = appState.philosophies.isEmpty
        await appState.loadPhilosophyGlanceIfNeeded()
    }

    private func philosophyCard(_ philosophy: PhilosophyCard) -> some View {
        let selected = builder.lanes.contains { $0.philosophyId == philosophy.id }
        let topModality = philosophy.bias?.first

        return Button {
            AppHaptics.light()
            builder.toggle(philosophy)
        } label: {
            VStack(alignment: .leading, spacing: AppMetrics.gapSmall) {
                HStack {
                    if let mod = topModality {
                        Image(systemName: ModalityStyle.icon(for: mod))
                            .foregroundStyle(ModalityStyle.color(for: mod))
                    }
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? AnyShapeStyle(AppColor.accent) : AnyShapeStyle(.tertiary))
                        .accessibilityHidden(true)
                }
                .padding(.trailing, 28)   // room for the ⓘ overlay
                Text(philosophy.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)
                // The same facts for every methodology, so two cards compare.
                if let facts = appState.philosophyGlance[philosophy.id]?.facts, !facts.isEmpty {
                    Text(facts.joined(separator: " · "))
                        .font(.caption).fontWeight(.medium).monospacedDigit()
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                }
                Text(philosophy.summary ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .appCard(compact: true, border: selected ? AppColor.accent : nil,
                     tint: selected ? AppColor.accent : nil)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .overlay(alignment: .topTrailing) {
            Button {
                detail = philosophy
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .appTapTarget()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("About \(philosophy.name)")
        }
    }
}
