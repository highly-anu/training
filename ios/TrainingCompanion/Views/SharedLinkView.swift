import SwiftUI

/// A shared link, opened in the app (design-system §6.63; docs/roadmap.md
/// item 25): `trainingcompanion://share?token=…`, what the web's
/// `/s/<token>` page offers as "Open in the app". A session reads as planned
/// for whoever shared it; a method can be saved to the athlete's own; a
/// program is built for them from its recipe once they have its methods.
/// Every sentence about what they have is the server's (`availability`).
struct SharedLinkView: View {
    let token: String

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var doc: ShareDocument? = nil
    @State private var isLoading = true
    @State private var gone = false
    @State private var error: String? = nil
    @State private var isSaving = false
    @State private var saved: [String] = []
    @State private var refusal: String? = nil
    @State private var different: [String]? = nil
    @State private var building: BuilderStart? = nil

    var body: some View {
        NavigationStack {
            Group {
                if let doc {
                    content(doc)
                } else if gone {
                    AppEmptyState(icon: "link.badge.plus", title: "No longer shared", message: ShareWords.gone)
                } else if isLoading {
                    ProgressView("Opening the link")
                } else {
                    AppFailedState(title: "Could not open the link", message: error ?? "Try again.") { await load() }
                }
            }
            .navigationTitle(doc.map { ShareWords.kind($0.kind) } ?? "Shared link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .navigationDestination(for: SharedMethodDescribe.Session.self) { session in
                MethodSessionView(session: session)
            }
        }
        .task { await load() }
        .fullScreenCover(item: $building) { start in
            ProgramBuilderFlow(start: start).environmentObject(appState)
        }
    }

    private func load() async {
        guard let api = appState.api else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await api.fetchShare(token)
            doc = fetched
            gone = fetched == nil
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    @ViewBuilder
    private func content(_ doc: ShareDocument) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppMetrics.gapLarge) {
                if let session = doc.session {
                    SharedSessionBody(doc: session)
                } else if let method = doc.method {
                    methodsNeeded(doc, saveLabel: "Save to your methods")
                    SharedMethodBody(method: method)
                } else if let program = doc.program {
                    SharedProgramBody(title: doc.title, program: program)
                    SectionLabel("Methods it needs")
                    methodsNeeded(doc, saveLabel: "Save the methods it needs")
                    buildIt(doc)
                }
            }
            .padding(AppMetrics.gapLarge)
        }
    }

    // MARK: What the athlete has, and Save

    private func methodsNeeded(_ doc: ShareDocument, saveLabel: String) -> some View {
        let a = doc.availability
        return VStack(alignment: .leading, spacing: AppMetrics.gapMedium) {
            ForEach(a?.methods ?? []) { method in
                let done = method.state == "have" || method.state == "shipped"
                HStack(alignment: .firstTextBaseline, spacing: AppMetrics.gapSmall) {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(done ? AppColor.complete : .secondary)
                        .accessibilityHidden(true)
                    Text(method.name).font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(ShareWords.state(method.state)).font(.caption).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            if a?.yours == true {
                Text("This is your own link.").font(.caption).foregroundStyle(.secondary)
            } else if let a, a.toSave > 0 {
                if !a.canSave {
                    Text("Saving methods is not available for this account.").font(.caption).foregroundStyle(.secondary)
                } else if let names = different {
                    Text("You already have another version of \(names.isEmpty ? "this method" : names.joined(separator: ", ")) — one you saved earlier or changed since. Replacing it keeps nothing of yours.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button { Task { await save(replace: true) } } label: {
                        saveLabelView("Replace my version")
                    }
                    .appButton(.secondary)
                    .disabled(isSaving)
                } else {
                    Button { Task { await save(replace: false) } } label: { saveLabelView(saveLabel) }
                        .appButton(.primary)
                        .disabled(isSaving)
                }
            }
            if let refusal {
                Text(refusal).font(.caption).foregroundStyle(AppColor.warning)
            }
            if !saved.isEmpty {
                Label("Saved \(saved.joined(separator: ", ")) to your methods.", systemImage: "checkmark")
                    .font(.caption).foregroundStyle(AppColor.complete)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private func saveLabelView(_ text: String) -> some View {
        Group {
            if isSaving { ProgressView() } else { Text(text).fontWeight(.semibold) }
        }
        .frame(maxWidth: .infinity)
    }

    private func save(replace: Bool) async {
        guard let api = appState.api else { return }
        isSaving = true
        defer { isSaving = false }
        refusal = nil
        do {
            switch try await api.saveShare(token, replace: replace) {
            case .saved(let names):
                saved = names
                different = nil
                AppHaptics.success()
                // Every list of methods was read before this one existed.
                await appState.methodsChanged()
                await load()
            case .different(let names):
                different = names
            case .refused(let why):
                refusal = why
            }
        } catch {
            refusal = error.localizedDescription
        }
    }

    // MARK: A program, built for the athlete

    @ViewBuilder
    private func buildIt(_ doc: ShareDocument) -> some View {
        if doc.availability?.ready == true, let start = BuilderStart(recipe: doc.recipe) {
            VStack(alignment: .leading, spacing: AppMetrics.gapSmall) {
                Button { building = start } label: {
                    Label("Build it for me", systemImage: "wand.and.stars")
                        .fontWeight(.semibold).frame(maxWidth: .infinity)
                }
                .appButton(.primary)
                Text("Opens the program builder with this as its source. Your level, equipment and schedule make it yours, and you see it before it starts.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else if doc.availability?.ready == false {
            Text("Save the methods first; then it can be built for you.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - A session

private struct SharedSessionBody: View {
    let doc: SharedSessionDoc

    @State private var opened: OpenedExercise? = nil

    private struct OpenedExercise: Identifiable {
        let id: String
        let name: String
        let assignment: ProgramExerciseAssignment
    }

    var body: some View {
        let session = doc.session
        let color = ModalityStyle.color(for: session.modality)
        let byRole = Dictionary(session.exercises.compactMap { ea in ea.slotRole.map { ($0, ea) } },
                                uniquingKeysWith: { first, _ in first })
        VStack(alignment: .leading, spacing: AppMetrics.gapLarge) {
            HStack(alignment: .top, spacing: AppMetrics.gapMedium) {
                Image(symbol: SessionIcon.symbol(icon: session.icon, modality: session.modality))
                    .font(.title2).foregroundStyle(color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: AppMetrics.gapTight) {
                    Text(ModalityStyle.label(for: session.modality)).font(.caption).foregroundStyle(color)
                    Text(doc.name).font(.headline)
                    Text(facts).font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)

            let blocks = session.blocks
            if blocks.isEmpty {
                // A link from before blocks, or a coach-led session: its exercises in order.
                VStack(alignment: .leading, spacing: AppMetrics.gapSmall) {
                    ForEach(Array(session.exercises.enumerated()), id: \.offset) { _, ea in plannedRow(ea) }
                }
                .appCard()
            } else {
                SessionBlocksView(blocks: blocks, accent: color, showsLoad: false) { movement, _ in
                    if let ea = byRole[movement.role] {
                        plannedRow(ea)
                    } else {
                        BlockMovementRow(movement: movement)
                    }
                }
            }
            Text("The numbers are the ones planned for the person who shared it. Tap a movement for what it is and how to do it.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .sheet(item: $opened) { open in
            ExerciseDetailSheet(exerciseId: open.id, name: open.name, assignment: open.assignment)
        }
    }

    private var facts: String {
        var parts = [ShareWords.place(week: doc.week?.weekNumber, day: doc.day)]
        if let minutes = doc.session.archetype?.durationEstimateMinutes, minutes > 0 { parts.append("~\(minutes) min") }
        if let phase = doc.week?.phaseName { parts.append(phase) }
        if let method = doc.method?.name { parts.append("From \(method)") }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    @ViewBuilder
    private func plannedRow(_ ea: ProgramExerciseAssignment) -> some View {
        if let exercise = ea.exercise, !ea.meta, !ea.injurySkip {
            Button {
                opened = OpenedExercise(id: exercise.id, name: exercise.name, assignment: ea)
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                        Text(LoadFormat.describe(ea)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        if let note = ea.loadNote ?? ea.notes, !note.isEmpty {
                            Text(note).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("What it is and how to do it")
        } else {
            Text(ea.exercise?.name ?? (ea.slotRole ?? "Movement").replacingOccurrences(of: "_", with: " ").capitalized)
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

// MARK: - A method

private struct SharedMethodBody: View {
    let method: SharedMethodDoc

    var body: some View {
        if let d = method.describe {
            VStack(alignment: .leading, spacing: AppMetrics.gapLarge) {
                VStack(alignment: .leading, spacing: AppMetrics.gapSmall) {
                    Text(d.name).font(.title3.weight(.semibold))
                    if let summary = d.summary, !summary.isEmpty {
                        Text(summary).font(.subheadline).foregroundStyle(.secondary)
                    }
                    let facts = [ShareWords.span(d.glance?.weeks, unit: "weeks"),
                                 ShareWords.span(d.glance?.daysPerWeek, unit: "days a week"),
                                 ShareWords.span(d.glance?.sessionMinutes, unit: "min")].compactMap { $0 }
                    if !facts.isEmpty {
                        Text(facts.joined(separator: " · ")).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }

                ForEach(d.tracks ?? []) { track in
                    AppCard(header: track.name ?? "Program") {
                        VStack(alignment: .leading, spacing: AppMetrics.gapSmall) {
                            if let text = track.description, !text.isEmpty {
                                Text(text).font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(Array((track.phases ?? []).enumerated()), id: \.offset) { _, phase in
                                HStack(alignment: .firstTextBaseline, spacing: AppMetrics.gapSmall) {
                                    Circle().fill(PhaseStyle.color(for: phase.kind ?? "")).frame(width: 8, height: 8)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(phase.name ?? "Phase").font(.subheadline)
                                        if let focus = phase.focus, !focus.isEmpty {
                                            Text(focus).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    if let weeks = phase.weeks {
                                        Text("\(weeks) wk").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    }
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }

                let sessions = d.sessions ?? [:]
                ForEach(d.groups ?? []) { group in
                    let listed = group.sessions.compactMap { sessions[$0] }
                    if !listed.isEmpty {
                        AppCard(header: group.name ?? ModalityStyle.label(for: group.modality ?? group.id)) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(listed) { session in
                                    NavigationLink(value: session) {
                                        HStack(spacing: AppMetrics.gapSmall) {
                                            Image(symbol: SessionIcon.symbol(icon: session.icon, modality: session.modality ?? ""))
                                                .foregroundStyle(ModalityStyle.color(for: session.modality ?? ""))
                                                .accessibilityHidden(true)
                                            Text(session.name).font(.subheadline).foregroundStyle(.primary)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .multilineTextAlignment(.leading)
                                            if let minutes = session.minutes {
                                                Text("\(minutes) min").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                            }
                                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                                .accessibilityHidden(true)
                                        }
                                        .padding(.vertical, AppMetrics.gapSmall)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
        } else {
            Text("\(method.name) is in the app: find it in the program builder.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

/// One session of a shared method, as written: its blocks.
private struct MethodSessionView: View {
    let session: SharedMethodDescribe.Session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppMetrics.gapLarge) {
                if let note = session.note, !note.isEmpty {
                    Text(note).font(.subheadline).foregroundStyle(.secondary)
                }
                SessionBlocksView(blocks: session.blocks ?? [],
                                  accent: ModalityStyle.color(for: session.modality ?? "")) { movement, _ in
                    BlockMovementRow(movement: movement)
                }
            }
            .padding(AppMetrics.gapLarge)
        }
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - A program

private struct SharedProgramBody: View {
    let title: String?
    let program: SharedProgramSummary

    var body: some View {
        VStack(alignment: .leading, spacing: AppMetrics.gapMedium) {
            Text(program.name ?? title ?? "Program").font(.title3.weight(.semibold))
            Text(facts).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            if !program.phases.isEmpty {
                GeometryReader { geo in
                    HStack(spacing: 1) {
                        ForEach(Array(program.phases.enumerated()), id: \.offset) { _, phase in
                            Rectangle().fill(PhaseStyle.color(for: phase.kind ?? ""))
                                .frame(width: max(2, geo.size.width * CGFloat(phase.weeks) / CGFloat(max(program.weeks, 1)) - 1))
                        }
                    }
                }
                .frame(height: 8)
                .clipShape(Capsule())
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: AppMetrics.gapTight) {
                    ForEach(Array(program.phases.enumerated()), id: \.offset) { _, phase in
                        HStack(spacing: AppMetrics.gapSmall) {
                            Circle().fill(PhaseStyle.color(for: phase.kind ?? "")).frame(width: 8, height: 8)
                                .accessibilityHidden(true)
                            Text("\(phase.name ?? phase.kind ?? "Phase") · \(phase.weeks) wk").font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var facts: String {
        var parts = ["\(program.weeks) weeks"]
        if let days = program.daysPerWeek { parts.append("\(days) days a week") }
        let tracks = program.tracks.compactMap(\.name)
        if tracks.count > 1 { parts.append("\(tracks.count) tracks") } else if let only = tracks.first { parts.append(only) }
        return parts.joined(separator: " · ")
    }
}
