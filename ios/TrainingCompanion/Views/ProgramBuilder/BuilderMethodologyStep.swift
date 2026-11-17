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
    /// The describe form or a build, pushed over this step.
    @State private var methodRoute: MethodRoute? = nil
    @State private var deleting: PhilosophyCard? = nil
    @State private var deleteRefusal: String? = nil

    /// The methodologies that are the athlete's own methods, and the rest.
    private var ownIds: Set<String> { Set(appState.methods?.methods.map(\.id) ?? []) }
    private var own: [PhilosophyCard] { appState.philosophies.filter { ownIds.contains($0.id) } }
    private var shipped: [PhilosophyCard] { appState.philosophies.filter { !ownIds.contains($0.id) } }
    /// The group is there when the account may build, or has methods already.
    private var showsMethods: Bool {
        guard let methods = appState.methods, methods.isShown else { return false }
        return methods.available || !own.isEmpty || methods.openBuild != nil
    }

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
                    if showsMethods {
                        yourMethods
                        SectionLabel("Methodologies", inset: false).padding(.horizontal)
                    }
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(shipped) { philosophy in
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
        .navigationDestination(item: $methodRoute) { destination in
            switch destination {
            case .describe(let revises):
                MethodDescribeView(revises: revises, builder: builder, route: $methodRoute)
            case .build(let id):
                MethodBuildView(buildId: id, builder: builder, route: $methodRoute)
            }
        }
        .onChange(of: methodRoute) { _, now in
            // Back from a build: it may have ended while its screen was not asking.
            if now == nil { Task { await appState.loadMethods() } }
        }
        .confirmationDialog("Delete \(deleting?.name ?? "this method")?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete method", role: .destructive) {
                if let method = deleting { Task { await delete(method) } }
            }
        } message: {
            Text("The method is removed from your methods. Programs already built from it stay in Program ▸ History.")
        }
    }

    private func load() async {
        loadFailed = false
        await appState.loadPhilosophiesIfNeeded()
        loadFailed = appState.philosophies.isEmpty
        await appState.loadPhilosophyGlanceIfNeeded()
        // The athlete's own methods, and any build still running. A method
        // built elsewhere since the list was read is not in it yet.
        if await appState.loadMethods(), !ownIds.isSubset(of: Set(appState.philosophies.map(\.id))) {
            await appState.methodsChanged()
        }
        #if DEBUG
        if methodRoute == nil, let launch = MethodRoute.debugLaunch { methodRoute = launch }
        #endif
    }

    // MARK: Your methods

    /// The athlete's own methods before the shipped ones (design-system
    /// §6.60): the build in progress, each method as a card with its actions,
    /// and the way to make another.
    private var yourMethods: some View {
        VStack(alignment: .leading, spacing: AppMetrics.gapMedium) {
            SectionLabel("Your methods", inset: false)
            if let open = appState.methods?.openBuild {
                Button {
                    methodRoute = .build(open.id)
                } label: {
                    HStack(spacing: AppMetrics.gapMedium) {
                        ProgressView().accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(open.revise == nil ? "Building your method" : "Building a revision")
                                .font(.subheadline).fontWeight(.medium)
                                .foregroundStyle(.primary)
                            Text(MethodBuildWords.headline(open))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .appCard(compact: true)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the build")
            }
            if !own.isEmpty {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(own) { philosophy in
                        philosophyCard(philosophy, yours: true)
                    }
                }
            }
            if appState.methods?.available == true, appState.methods?.openBuild == nil {
                Button {
                    methodRoute = .describe(revises: nil)
                } label: {
                    HStack(spacing: AppMetrics.gapMedium) {
                        Image(systemName: "sparkles").foregroundStyle(AppColor.accent)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Create your own")
                                .font(.subheadline).fontWeight(.medium)
                                .foregroundStyle(.primary)
                            Text("Describe how you want to train and it is written as a method you can build programs from.")
                                .font(.caption).foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .appCard(compact: true)
                }
                .buttonStyle(.plain)
            }
            if let deleteRefusal {
                Label(deleteRefusal, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(AppColor.destructive)
            }
        }
        .padding(.horizontal)
    }

    private func delete(_ method: PhilosophyCard) async {
        deleteRefusal = nil
        guard let api = appState.api else { return }
        do {
            if let refusal = try await api.deleteMethod(method.id) {
                deleteRefusal = refusal
                return
            }
        } catch {
            deleteRefusal = "The method could not be deleted. Check the connection and try again."
            return
        }
        builder.lanes.removeAll { $0.philosophyId == method.id }
        await appState.methodsChanged()
        // A deleted method's card goes with it even when the list could not be read again.
        appState.philosophies.removeAll { $0.id == method.id }
    }

    private func philosophyCard(_ philosophy: PhilosophyCard, yours: Bool = false) -> some View {
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
            if yours {
                // A method of the athlete's own: its actions, visible (§6.51).
                Menu {
                    Button { detail = philosophy } label: { Label("About", systemImage: "info.circle") }
                    if appState.methods?.available == true, appState.methods?.openBuild == nil {
                        Button { methodRoute = .describe(revises: philosophy.id) } label: {
                            Label("Revise", systemImage: "pencil")
                        }
                    }
                    Button(role: .destructive) { deleting = philosophy } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                        .appTapTarget()
                }
                .accessibilityLabel("\(philosophy.name) actions")
            } else {
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
}
