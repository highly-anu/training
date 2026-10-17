import SwiftUI
import Charts

/// What a standard sheet shows: one standard, or the bodyweight series the
/// ×BW standards read.
enum StandardSubject: Identifiable {
    case standard(AppBenchmark)
    case bodyweight

    var id: String {
        switch self {
        case .standard(let b): return b.id
        case .bodyweight: return "bodyweight_kg"
        }
    }
    var benchmark: AppBenchmark? {
        if case .standard(let b) = self { return b }
        return nil
    }
    var name: String { benchmark?.name ?? "Bodyweight" }
}

/// One standard — or the bodyweight series — and every result on it
/// (design-system §6.30; the web's `StandardDetailSheet`): where the athlete
/// stands, the ladder, the history across programs, and each result to
/// correct or delete. A result belongs to the athlete, not a program.
struct StandardDetailSheet: View {
    let subject: StandardSubject

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var logging = false
    @State private var editing: StandardResult.Entry? = nil
    @State private var deleting: StandardResult.Entry? = nil
    @State private var problem: String? = nil

    private var result: StandardResult? {
        subject.benchmark.flatMap { appState.standardResults?.standards[$0.id] }
    }
    private var entries: [StandardResult.Entry] {
        subject.benchmark == nil ? (appState.standardResults?.bodyweight?.entries ?? []) : (result?.entries ?? [])
    }

    var body: some View {
        NavigationStack {
            List {
                if let b = subject.benchmark {
                    Section {
                        if let result {
                            HStack(spacing: 6) {
                                Text(result.current.valueText).font(.headline).monospacedDigit()
                                StandardLevelBadge(level: result.current.level, domain: b.domain)
                                Spacer(minLength: 0)
                            }
                            Text(summary(result)).font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("No result yet.").font(.caption).foregroundStyle(.secondary)
                        }
                        StandardLadder(thresholds: b.thresholdTexts, levelIndex: result?.current.levelIndex, domain: b.domain)
                            .padding(.vertical, 2)
                        if let how = b.testProtocol {
                            Text("How to test: \(how)").font(.caption).foregroundStyle(.secondary)
                        }
                        if let notes = b.notes {
                            Text(notes).font(.caption).foregroundStyle(.secondary)
                        }
                        if let effort = b.bestEffort {
                            Text("Imported runs with recorded speed (a FIT file, Garmin Connect) suggest a result here when their fastest \(effort.label) beats your best, or whenever the run is linked to a test of it. Apple Health and live watch runs carry no speed, so they do not.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section {
                        Text("Every weight you have logged. The ×BW standards read the one on or before each result's day.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if !entries.isEmpty {
                    Section("History") {
                        StandardHistoryChart(entries: entries, benchmark: subject.benchmark,
                                             blocks: appState.standardResults?.blocks ?? [])
                            .frame(height: 190)
                            .padding(.vertical, 4)
                    }
                }

                Section {
                    Button { logging = true } label: { Label("Log a result", systemImage: "plus.circle") }
                    if let problem {
                        Text(problem).font(.caption).foregroundStyle(.red)
                    }
                }

                if !entries.isEmpty {
                    Section("\(entries.count) result\(entries.count == 1 ? "" : "s")") {
                        ForEach(entries.reversed()) { entry in
                            EntryRow(entry: entry, domain: subject.benchmark?.domain, showsLevel: subject.benchmark != nil)
                                .contentShape(Rectangle())
                                .onTapGesture { editing = entry }
                                .swipeActions {
                                    Button(role: .destructive) { deleting = entry } label: { Label("Delete", systemImage: "trash") }
                                    Button { editing = entry } label: { Label("Edit", systemImage: "pencil") }
                                }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(subject.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $logging) { StandardResultSheet(subject: subject, editing: nil) }
            .sheet(item: $editing) { entry in StandardResultSheet(subject: subject, editing: entry) }
            .confirmationDialog("Delete this result?", isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }
            ), titleVisibility: .visible, presenting: deleting) { entry in
                Button("Delete \(entry.valueText)", role: .destructive) { delete(entry) }
            } message: { entry in
                Text("\(entry.valueText) on \(StandardLevel.day(entry.date) ?? "") — the rest of the history stays.")
            }
        }
    }

    private func summary(_ r: StandardResult) -> String {
        var parts: [String] = []
        if let day = StandardLevel.day(r.current.date) { parts.append(day) }
        if r.best.value != r.current.value { parts.append("best \(r.best.valueText)") }
        if let next = r.current.next, let gap = r.current.gapText { parts.append("\(gap) to \(next)") }
        return parts.joined(separator: " · ")
    }

    private func delete(_ entry: StandardResult.Entry) {
        guard let id = entry.entryId else { return }
        Task {
            problem = await appState.deleteResult(id: id)
            if problem == nil { AppHaptics.success() } else { AppHaptics.error() }
        }
    }
}

private struct EntryRow: View {
    let entry: StandardResult.Entry
    let domain: String?
    let showsLevel: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(entry.valueText).font(.subheadline).fontWeight(.semibold).monospacedDigit()
                if showsLevel { StandardLevelBadge(level: entry.level, domain: domain) }
                Spacer(minLength: 4)
                Text(StandardLevel.day(entry.date) ?? "").font(.caption).foregroundStyle(.secondary)
            }
            Text([entry.sourceText, entry.block?.name, entry.inputText].compactMap { $0 }.joined(separator: " · "))
                .font(.caption2).foregroundStyle(.secondary)
            if let note = entry.note {
                Text(note).font(.caption)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - History chart

/// One result as the chart draws it — a Profile entry or a Blocks history point.
struct StandardChartPoint: Identifiable {
    let id: String
    let date: Date
    let value: Double
    let valueText: String
    let level: String?

    init?(id: String, day: String?, value: Double, valueText: String, level: String?) {
        guard let date = StandardLevel.date(day) else { return nil }
        self.id = id; self.date = date; self.value = value; self.valueText = valueText; self.level = level
    }
}

/// A level's dashed line: its word, threshold and the server's text for it.
struct StandardChartLevel {
    let level: String
    let value: Double
    let text: String

    static func from(standards: [String: Double], texts: [String: String]) -> [StandardChartLevel] {
        StandardLevel.all.compactMap { l in standards[l].map { StandardChartLevel(level: l, value: $0, text: texts[l] ?? "") } }
    }
}

/// A program block, as a band behind the line.
struct StandardChartBand {
    let from: String
    let to: String?
}

/// A standard's results over time (the web's `StandardHistoryChart`): one
/// series in the modality's colour, each level a dashed line labelled with its
/// word and value (the server's text, so no value axis), and the program blocks
/// as bands. Drag across it for a result's day, value and level.
struct StandardHistoryChart: View {
    let points: [StandardChartPoint]
    let levels: [StandardChartLevel]
    let domain: String?
    let bands: [StandardChartBand]

    @State private var selected: Date? = nil

    private var color: Color { domain.map { ModalityStyle.color(for: $0) } ?? .accentColor }

    var body: some View {
        let pts = points
        let first = pts.first?.date ?? Date()
        let last = pts.last?.date ?? Date()
        let pad = max(last.timeIntervalSince(first) * 0.06, 10 * 86_400)
        let xDomain = first.addingTimeInterval(-pad)...last.addingTimeInterval(pad)
        let values = pts.map(\.value) + levels.map(\.value)
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let span = (hi - lo) == 0 ? max(abs(hi), 1) : (hi - lo)
        let yDomain = max(0, lo - span * 0.08)...(hi + span * 0.08)
        let nearest = selected.flatMap { s in pts.min { abs($0.date.timeIntervalSince(s)) < abs($1.date.timeIntervalSince(s)) } }

        Chart {
            ForEach(Array(bandRanges(in: xDomain).enumerated()), id: \.offset) { i, band in
                RectangleMark(xStart: .value("From", band.from), xEnd: .value("To", band.to))
                    .foregroundStyle(Color.primary.opacity(i % 2 == 0 ? 0.06 : 0.025))
            }
            ForEach(levels, id: \.level) { l in
                RuleMark(y: .value(l.level, l.value))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .annotation(position: .trailing, alignment: .leading) {
                        Text("\(l.level) \(l.text)").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
            }
            ForEach(pts) { p in
                LineMark(x: .value("Day", p.date), y: .value("Value", p.value))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                PointMark(x: .value("Day", p.date), y: .value("Value", p.value))
                    .foregroundStyle(color)
                    .symbolSize(p.id == nearest?.id ? 90 : 45)
            }
            if let n = nearest {
                RuleMark(x: .value("Selected", n.date))
                    .foregroundStyle(Color.secondary.opacity(0.4))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(n.valueText) · \(StandardLevel.name(n.level).lowercased())")
                                .font(.caption2).fontWeight(.semibold)
                            Text(n.date.formatted(.dateTime.day().month(.abbreviated).year()))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(6)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    }
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartYAxis(.hidden)
        // One tick per whole month (every few months over a long history), so
        // no label repeats and none is cut at the edge.
        .chartXAxis {
            if monthStride(xDomain) == 0 {
                // Under two months: a tick a week, by day.
                AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated), collisionResolution: .greedy)
                }
            } else {
                AxisMarks(values: .stride(by: .month, count: monthStride(xDomain))) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits), collisionResolution: .greedy)
                }
            }
        }
        .chartXSelection(value: $selected)
        // Room inside the chart's frame for the level labels at the trailing edge.
        .chartPlotStyle { plot in plot.padding(.trailing, levels.isEmpty ? 0 : 92) }
        .accessibilityLabel("\(pts.count) results over time")
    }

    /// Months between ticks, or 0 for a span too short for month ticks.
    private func monthStride(_ domain: ClosedRange<Date>) -> Int {
        let months = domain.upperBound.timeIntervalSince(domain.lowerBound) / (30.4 * 86_400)
        return months < 2 ? 0 : max(1, Int((months / 4).rounded(.up)))
    }

    private func bandRanges(in domain: ClosedRange<Date>) -> [(from: Date, to: Date)] {
        bands.compactMap { b in
            guard let start = StandardLevel.date(b.from) else { return nil }
            let end = b.to.flatMap(StandardLevel.date).map { $0.addingTimeInterval(86_400) } ?? domain.upperBound
            let from = max(start, domain.lowerBound), to = min(end, domain.upperBound)
            return from < to ? (from, to) : nil
        }
    }
}

extension StandardHistoryChart {
    /// A standard's (or the bodyweight's) Profile entries.
    init(entries: [StandardResult.Entry], benchmark: AppBenchmark?, blocks: [StandardResults.Block]) {
        self.init(
            points: entries.compactMap { StandardChartPoint(id: $0.id, day: $0.date, value: $0.value,
                                                           valueText: $0.valueText, level: $0.level) },
            levels: benchmark.map { b in
                StandardChartLevel.from(standards: [
                    "entry": b.standards?.entry, "intermediate": b.standards?.intermediate,
                    "advanced": b.standards?.advanced, "elite": b.standards?.elite,
                ].compactMapValues { $0 }, texts: b.thresholdTexts)
            } ?? [],
            domain: benchmark?.domain,
            bands: blocks.map { StandardChartBand(from: $0.from, to: $0.to) })
    }
}

// MARK: - Log or correct a result

/// Logs a new result, or corrects one: the value as the athlete would write
/// it ("4:58"; for a ×BW standard the load and reps lifted), the day it was
/// done and a note. The server reads and converts it; what it cannot read
/// comes back in its own words.
struct StandardResultSheet: View {
    let subject: StandardSubject
    let editing: StandardResult.Entry?

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var asLoad = false
    @State private var text = ""
    @State private var kg = ""
    @State private var reps = 1
    @State private var day = Date()
    @State private var note = ""
    @State private var problem: String? = nil
    @State private var saving = false

    private var isRatio: Bool { subject.benchmark?.metricType == "bw_ratio" }
    private var hint: String { subject.benchmark.map { $0.inputHint ?? ($0.unit ?? "") } ?? "kg" }
    private var ready: Bool {
        !saving && !(asLoad ? kg : text).trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if isRatio {
                        Picker("Log as", selection: $asLoad) {
                            Text("Load lifted").tag(true)
                            Text("Ratio ×BW").tag(false)
                        }
                        .pickerStyle(.segmented)
                    }
                    if asLoad {
                        HStack {
                            TextField("Load", text: $kg).keyboardType(.decimalPad)
                            Text("kg").foregroundStyle(.secondary)
                        }
                        Stepper("\(reps) rep\(reps == 1 ? "" : "s")", value: $reps, in: 1...30)
                    } else {
                        HStack {
                            TextField(hint, text: $text)
                                .keyboardType(hint == "m:ss" || hint == "h:mm:ss" ? .numbersAndPunctuation : .decimalPad)
                            Text(hint).foregroundStyle(.secondary)
                        }
                    }
                    DatePicker("Day", selection: $day, in: ...Date(), displayedComponents: .date)
                    TextField("Note (optional)", text: $note)
                    if let problem {
                        Text(problem).font(.caption).foregroundStyle(.red)
                    }
                } header: {
                    Text(subject.name)
                } footer: {
                    if asLoad { Text("Divided by your bodyweight on that day; more than one rep is an estimate.") }
                }
                if let b = subject.benchmark {
                    Section("Standards") {
                        StandardLadder(thresholds: b.thresholdTexts,
                                       levelIndex: appState.standardResults?.standards[b.id]?.current.levelIndex,
                                       domain: b.domain)
                            .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle(editing == nil ? "Log a result" : "Edit result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save", action: save).fontWeight(.semibold).disabled(!ready)
                }
            }
            .onAppear {
                if let e = editing {
                    text = e.valueText
                    day = StandardLevel.date(e.date) ?? Date()
                    note = e.note ?? ""
                } else {
                    asLoad = isRatio
                }
            }
        }
    }

    private func save() {
        guard ready else { return }
        saving = true
        let iso = StandardLevel.isoDay(day)
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        var input = StandardResultInput()
        if asLoad {
            input.kg = Double(kg.replacingOccurrences(of: ",", with: "."))
            input.reps = reps
        } else if editing == nil || text != editing?.valueText {
            // Only what changed: re-sending the printed value would replace a
            // load's kg × reps with the ratio.
            input.text = text.trimmingCharacters(in: .whitespaces)
        }
        if editing == nil || iso != editing?.date { input.loggedOn = iso }
        if editing == nil ? !trimmedNote.isEmpty : trimmedNote != (editing?.note ?? "") { input.note = trimmedNote }
        Task {
            let failure: String?
            if let e = editing, let id = e.entryId {
                failure = await appState.updateResult(id: id, input: input)
            } else {
                failure = await appState.logResult(benchmarkId: subject.id, input: input)
            }
            saving = false
            if let failure {
                problem = failure
                AppHaptics.error()
            } else {
                AppHaptics.success()
                dismiss()
            }
        }
    }
}
