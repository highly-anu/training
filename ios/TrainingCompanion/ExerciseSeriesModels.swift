import Foundation

/// `exerciseSeries` on `GET /api/analytics/program` (src/analytics/exercise_series.py):
/// every exercise of the program, session by session — the stored
/// prescription and, once logged, what was done — for Analytics ▸ Progress's
/// one chart. `measures` names the progress entries the chart also draws.
/// The web's `lib/progressChart.ts` lines it up the same way.
extension ProgramAnalytics {
    struct ExerciseSeries: Decodable {
        struct Metric: Decodable, Identifiable, Hashable {
            let id: String
            let label: String
            let unit: String
        }

        struct SetDone: Decodable, Hashable {
            let weightKg: Double?
            let reps: Double?
            let seconds: Double?
            let rpe: Double?
        }

        struct Point: Decodable, Identifiable {
            let date: String?
            let week: Int?
            let x: Int
            let isDeload: Bool
            let elapsed: Bool
            /// "log" | "workout", nil when nothing was logged.
            let source: String?
            let sessionName: String?
            let done: [String: Double]
            let prescribed: [String: Double]
            let doneText: String?
            let prescribedText: String?
            let setsDone: [SetDone]
            var id: Int { x }

            private enum CodingKeys: String, CodingKey {
                case date, week, x, isDeload, elapsed, source, sessionName, done, prescribed, doneText,
                     prescribedText, setsDone
            }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                date = try? c.decodeIfPresent(String.self, forKey: .date)
                week = try? c.decodeIfPresent(Int.self, forKey: .week)
                x = (try? c.decodeIfPresent(Int.self, forKey: .x)) ?? 0
                isDeload = (try? c.decodeIfPresent(Bool.self, forKey: .isDeload)) ?? false
                elapsed = (try? c.decodeIfPresent(Bool.self, forKey: .elapsed)) ?? false
                source = try? c.decodeIfPresent(String.self, forKey: .source)
                sessionName = try? c.decodeIfPresent(String.self, forKey: .sessionName)
                // A metric with no value is null on the wire: dropped here.
                done = Self.values(c, .done)
                prescribed = Self.values(c, .prescribed)
                doneText = try? c.decodeIfPresent(String.self, forKey: .doneText)
                prescribedText = try? c.decodeIfPresent(String.self, forKey: .prescribedText)
                setsDone = ((try? c.decodeIfPresent([Lossy<SetDone>].self, forKey: .setsDone)) ?? [])?.compactMap(\.value) ?? []
            }

            private static func values(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> [String: Double] {
                let raw = ((try? c.decodeIfPresent([String: Double?].self, forKey: key)) ?? nil) ?? [:]
                return raw.compactMapValues { $0 }
            }
        }

        struct Exercise: Decodable, Identifiable {
            let exerciseId: String
            let name: String
            let modality: String?
            let metrics: [String]
            let defaultMetric: String
            let scheduled: Int
            let logged: Int
            let points: [Point]
            var id: String { exerciseId }

            private enum CodingKeys: String, CodingKey {
                case exerciseId, name, modality, metrics, defaultMetric, scheduled, logged, points
            }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                exerciseId = try c.decode(String.self, forKey: .exerciseId)
                name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? exerciseId
                modality = try? c.decodeIfPresent(String.self, forKey: .modality)
                metrics = ((try? c.decodeIfPresent([String].self, forKey: .metrics)) ?? nil) ?? []
                defaultMetric = (try? c.decodeIfPresent(String.self, forKey: .defaultMetric)) ?? metrics.first ?? "weight"
                scheduled = (try? c.decodeIfPresent(Int.self, forKey: .scheduled)) ?? 0
                logged = (try? c.decodeIfPresent(Int.self, forKey: .logged)) ?? 0
                points = ((try? c.decodeIfPresent([Lossy<Point>].self, forKey: .points)) ?? [])?.compactMap(\.value) ?? []
            }
        }

        struct Measure: Decodable, Identifiable {
            let id: String
            let label: String
            let unit: String?
            let philosophy: String
            let primitive: String
        }

        let metrics: [Metric]
        let exercises: [Exercise]
        let measures: [Measure]

        private enum CodingKeys: String, CodingKey { case metrics, exercises, measures }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            metrics = ((try? c.decodeIfPresent([Lossy<Metric>].self, forKey: .metrics)) ?? [])?.compactMap(\.value) ?? []
            exercises = ((try? c.decodeIfPresent([Lossy<Exercise>].self, forKey: .exercises)) ?? [])?.compactMap(\.value) ?? []
            measures = ((try? c.decodeIfPresent([Lossy<Measure>].self, forKey: .measures)) ?? [])?.compactMap(\.value) ?? []
        }

        func metric(_ id: String) -> Metric? { metrics.first { $0.id == id } }
    }
}

/// The chart's selection and its points on one date axis: the phone's copy of
/// the web's `lib/progressChart.ts` (pure, `ProgressChartModelTests`).
enum ProgressChartModel {
    enum Selection: Hashable {
        case exercise(id: String, metric: String)
        case measure(id: String)

        var id: String {
            switch self {
            case .exercise(let id, _), .measure(let id): return id
            }
        }
    }

    struct Point: Identifiable {
        let date: Date
        let done: Double?
        let planned: Double?
        let isDeload: Bool
        let elapsed: Bool
        let sessionName: String?
        let doneText: String?
        let prescribedText: String?
        let id: Int
    }

    struct Series {
        let label: String
        let unit: String
        /// "Prescribed" for an exercise, "Expected" for a measure.
        let plannedLabel: String
        let points: [Point]
    }

    /// The progress entries the chart can draw: those the server names.
    static func chartableMeasures(_ doc: ProgramAnalytics) -> [ProgramAnalytics.ProgressEntry] {
        let named = Set((doc.exerciseSeries?.measures ?? []).map { "\($0.philosophy):\($0.id)" })
        return doc.progress.filter { named.contains("\($0.philosophy):\($0.id)") }
    }

    /// What a link asked for, read against what the document has; else the
    /// first logged exercise, else the first measure, else the first exercise.
    static func resolve(exercise: String? = nil, measure: String? = nil, metric: String? = nil,
                        in doc: ProgramAnalytics) -> Selection? {
        let exercises = doc.exerciseSeries?.exercises ?? []
        let measures = chartableMeasures(doc)
        func metricFor(_ ex: ProgramAnalytics.ExerciseSeries.Exercise) -> String {
            if let metric, ex.metrics.contains(metric) { return metric }
            return ex.defaultMetric
        }
        if let exercise, let ex = exercises.first(where: { $0.exerciseId == exercise }) {
            return .exercise(id: ex.exerciseId, metric: metricFor(ex))
        }
        if let measure, measures.contains(where: { $0.id == measure }) { return .measure(id: measure) }
        if let ex = exercises.first(where: { $0.logged > 0 }) { return .exercise(id: ex.exerciseId, metric: metricFor(ex)) }
        if let m = measures.first { return .measure(id: m.id) }
        if let ex = exercises.first { return .exercise(id: ex.exerciseId, metric: metricFor(ex)) }
        return nil
    }

    static func series(_ selection: Selection, in doc: ProgramAnalytics) -> Series? {
        switch selection {
        case .exercise(let id, let metric):
            guard let section = doc.exerciseSeries,
                  let ex = section.exercises.first(where: { $0.exerciseId == id }) else { return nil }
            let points = ex.points.compactMap { p -> Point? in
                guard let date = p.date.flatMap(day) else { return nil }
                return Point(date: date, done: p.done[metric], planned: p.prescribed[metric], isDeload: p.isDeload,
                             elapsed: p.elapsed, sessionName: p.sessionName, doneText: p.doneText,
                             prescribedText: p.prescribedText, id: p.x)
            }
            return Series(label: ex.name, unit: section.metric(metric)?.unit ?? "", plannedLabel: "Prescribed",
                          points: points)
        case .measure(let id):
            guard let entry = doc.progress.first(where: { $0.id == id }) else { return nil }
            let lead = entry.leadExercise
            var byX: [Double: Point] = [:]
            for p in lead?.series ?? entry.series {
                guard let date = p.date.flatMap(day) else { continue }
                byX[p.x] = Point(date: date, done: p.value, planned: nil, isDeload: p.isDeload, elapsed: true,
                                 sessionName: nil, doneText: nil, prescribedText: nil, id: Int(p.x))
            }
            for e in lead?.expected ?? entry.expected {
                guard let date = e.date.flatMap(day) else { continue }
                let had = byX[e.x]
                byX[e.x] = Point(date: had?.date ?? date, done: had?.done, planned: e.value,
                                 isDeload: had?.isDeload ?? false, elapsed: true, sessionName: nil,
                                 doneText: nil, prescribedText: nil, id: Int(e.x))
            }
            return Series(label: lead.map { "\(entry.label) · \($0.name)" } ?? entry.label,
                          unit: lead?.unit ?? entry.unit, plannedLabel: "Expected",
                          points: byX.values.sorted { $0.date < $1.date })
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func day(_ iso: String) -> Date? { dayFormatter.date(from: String(iso.prefix(10))) }
}
