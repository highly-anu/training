import Foundation

/// `GET /api/analytics/program` — how the athlete is doing against what the
/// active program is *for*, per methodology, in that methodology's own
/// currency. The same document the web's Analytics ▸ Program tab lays out;
/// the engine is `src/analytics/`, nothing is computed on the phone.
///
/// Every section is decoded on its own and may be nil: the server answers a
/// section that failed with `{"error": "..."}` rather than failing the whole
/// document, and a field the engine adds later must not blank the screen.
struct ProgramAnalytics: Decodable {
    let status: String                 // "ok" | "no_program"
    let revision: String?
    let generatedAt: String?
    let frame: Frame?
    let scorecard: Scorecard?
    let intensity: Intensity?
    let methodologies: [Methodology]
    let progress: [ProgressEntry]
    let movement: Movement?
    let load: Load?
    /// Sections the server could not compute, by name, with its reason.
    let sectionErrors: [String: String]

    var hasProgram: Bool { status != "no_program" }

    private enum CodingKeys: String, CodingKey {
        case status, revision, generatedAt, frame, scorecard, intensity, methodologies, progress, movement, load
    }

    private struct SectionError: Decodable { let error: String }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "ok"
        revision = try? c.decodeIfPresent(String.self, forKey: .revision)
        generatedAt = try? c.decodeIfPresent(String.self, forKey: .generatedAt)
        var errors: [String: String] = [:]
        // The error shape is checked first: every section type decodes
        // tolerantly, so `{"error": "..."}` would otherwise read as an empty
        // section instead of a failed one — the same rule as the web's
        // `sectionErr`.
        func section<T: Decodable>(_ type: T.Type, _ key: CodingKeys) -> T? {
            if let failed = try? c.decodeIfPresent(SectionError.self, forKey: key), !failed.error.isEmpty {
                errors[key.stringValue] = failed.error
                return nil
            }
            return try? c.decodeIfPresent(T.self, forKey: key)
        }
        frame = section(Frame.self, .frame)
        scorecard = section(Scorecard.self, .scorecard)
        intensity = section(Intensity.self, .intensity)
        movement = section(Movement.self, .movement)
        load = section(Load.self, .load)
        methodologies = ((try? c.decodeIfPresent([Lossy<Methodology>].self, forKey: .methodologies)) ?? [])?.compactMap(\.value) ?? []
        progress = ((try? c.decodeIfPresent([Lossy<ProgressEntry>].self, forKey: .progress)) ?? [])?.compactMap(\.value) ?? []
        sectionErrors = errors
    }

    // MARK: Frame — what the program is, and where in it the athlete stands

    struct Frame: Decodable {
        struct Philosophy: Decodable {
            let id: String
            let name: String
            let weight: Double?
            let analytics: String?        // "declared" | "default"
        }
        struct Framework: Decodable {
            let id: String
            let name: String
            let progressionModel: String?
        }
        struct Phase: Decodable {
            let name: String
            let weekInPhase: Int?
            let weekInProgram: Int
            let totalWeeks: Int
            let focus: String?
            let isDeload: Bool
        }
        struct Fidelity: Decodable, Identifiable {
            let field: String
            let ideal: Double
            let minimum: Double?
            let actual: Double
            let unit: String
            let status: String            // below_minimum | below_ideal | meets_ideal
            var id: String { field }
        }
        let status: String                // not_started | active | complete
        let startDate: String?
        let plannedWeeks: Int?
        let elapsedWeeks: Int?
        let deloadWeeks: [Int]
        let philosophies: [Philosophy]
        let framework: Framework?
        let phase: Phase?
        let planFidelity: [Fidelity]

        private enum CodingKeys: String, CodingKey {
            case status, startDate, plannedWeeks, elapsedWeeks, deloadWeeks, philosophies, framework, phase, planFidelity
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "active"
            startDate = try? c.decodeIfPresent(String.self, forKey: .startDate)
            plannedWeeks = try? c.decodeIfPresent(Int.self, forKey: .plannedWeeks)
            elapsedWeeks = try? c.decodeIfPresent(Int.self, forKey: .elapsedWeeks)
            deloadWeeks = (try? c.decodeIfPresent([Int].self, forKey: .deloadWeeks)) ?? []
            philosophies = ((try? c.decodeIfPresent([Lossy<Philosophy>].self, forKey: .philosophies)) ?? [])?.compactMap(\.value) ?? []
            framework = try? c.decodeIfPresent(Framework.self, forKey: .framework)
            phase = try? c.decodeIfPresent(Phase.self, forKey: .phase)
            planFidelity = ((try? c.decodeIfPresent([Lossy<Fidelity>].self, forKey: .planFidelity)) ?? [])?.compactMap(\.value) ?? []
        }
    }

    // MARK: Scorecard — did you train what this program is for

    struct Scorecard: Decodable {
        struct Tier: Decodable {
            let planned: Int
            let completed: Int
            let pct: Double?
        }
        struct Row: Decodable, Identifiable {
            let modality: String
            let family: String?
            let tier: String              // committed | core | supplementary | unscheduled
            let priority: Double?
            let plannedSessions: Int
            let completedSessions: Int
            let completionPct: Double?
            let weeklyPlannedMinutes: Double?
            let weeklyActualMinutes: Double?
            let minWeeklyMinutes: Double?
            let maxWeeklyMinutes: Double?
            let doseStatus: String?       // under | on | over | unknown
            let planDoseStatus: String?
            var id: String { modality }
        }
        let headline: String              // on_plan | off_plan | not_started
        let overallPct: Double?
        let tiers: [String: Tier]
        let elapsedWeeks: Int
        let modalities: [Row]

        private enum CodingKeys: String, CodingKey { case headline, overallPct, tiers, elapsedWeeks, modalities }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            headline = (try? c.decodeIfPresent(String.self, forKey: .headline)) ?? "not_started"
            overallPct = try? c.decodeIfPresent(Double.self, forKey: .overallPct)
            tiers = (try? c.decodeIfPresent([String: Tier].self, forKey: .tiers)) ?? [:]
            elapsedWeeks = (try? c.decodeIfPresent(Int.self, forKey: .elapsedWeeks)) ?? 0
            modalities = ((try? c.decodeIfPresent([Lossy<Row>].self, forKey: .modalities)) ?? [])?.compactMap(\.value) ?? []
        }
    }

    // MARK: Shared pieces

    struct Coverage: Decodable {
        let inScope: Int
        let measured: Int
        let pct: Double
        let reason: String?
    }

    struct Trend: Decodable {
        let direction: String             // improving | stable | declining | insufficient_data
        let slopePct: Double
        let pointsUsed: Int
    }

    struct SeriesPoint: Decodable, Identifiable {
        let x: Double
        let week: Int?
        let value: Double?
        let date: String?
        let isDeload: Bool
        var id: Double { x }

        private enum CodingKeys: String, CodingKey { case x, week, value, date, isDeload }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            x = (try? c.decodeIfPresent(Double.self, forKey: .x)) ?? 0
            week = try? c.decodeIfPresent(Int.self, forKey: .week)
            value = try? c.decodeIfPresent(Double.self, forKey: .value)
            date = try? c.decodeIfPresent(String.self, forKey: .date)
            isDeload = (try? c.decodeIfPresent(Bool.self, forKey: .isDeload)) ?? false
        }
    }

    struct ExpectedPoint: Decodable, Identifiable {
        let x: Double
        let week: Int?
        let value: Double?
        var id: Double { x }
    }

    // MARK: Progress — one methodology metric, in its own currency

    struct ExerciseResult: Decodable, Identifiable {
        let exerciseId: String
        let name: String
        let series: [SeriesPoint]
        let expected: [ExpectedPoint]
        let trend: Trend?
        let status: String
        let stalled: Bool
        let prescribedNow: Double?
        let bestEst1rm: Double?
        var id: String { exerciseId }

        private enum CodingKeys: String, CodingKey {
            case exerciseId, name, series, expected, trend, status, stalled, prescribedNow, bestEst1rm
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            exerciseId = try c.decode(String.self, forKey: .exerciseId)
            name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? exerciseId
            series = ((try? c.decodeIfPresent([Lossy<SeriesPoint>].self, forKey: .series)) ?? [])?.compactMap(\.value) ?? []
            expected = ((try? c.decodeIfPresent([Lossy<ExpectedPoint>].self, forKey: .expected)) ?? [])?.compactMap(\.value) ?? []
            trend = try? c.decodeIfPresent(Trend.self, forKey: .trend)
            status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "insufficient_data"
            stalled = (try? c.decodeIfPresent(Bool.self, forKey: .stalled)) ?? false
            prescribedNow = try? c.decodeIfPresent(Double.self, forKey: .prescribedNow)
            bestEst1rm = try? c.decodeIfPresent(Double.self, forKey: .bestEst1rm)
        }
    }

    struct Practised: Decodable, Identifiable {
        let exerciseId: String
        let name: String
        let sessions: Int?
        var id: String { exerciseId }
    }

    struct BenchmarkRow: Decodable, Identifiable {
        let benchmarkId: String
        let name: String?
        let unit: String?
        let latest: Double?
        let target: String?
        let targetValue: Double?
        let met: Bool?
        let level: String?
        let next: String?
        let missing: Bool
        var id: String { benchmarkId }

        private enum CodingKeys: String, CodingKey {
            case benchmarkId, name, unit, latest, target, targetValue, met, level, next, missing
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            benchmarkId = try c.decode(String.self, forKey: .benchmarkId)
            name = try? c.decodeIfPresent(String.self, forKey: .name)
            unit = try? c.decodeIfPresent(String.self, forKey: .unit)
            latest = try? c.decodeIfPresent(Double.self, forKey: .latest)
            target = try? c.decodeIfPresent(String.self, forKey: .target)
            targetValue = try? c.decodeIfPresent(Double.self, forKey: .targetValue)
            met = try? c.decodeIfPresent(Bool.self, forKey: .met)
            level = try? c.decodeIfPresent(String.self, forKey: .level)
            next = try? c.decodeIfPresent(String.self, forKey: .next)
            missing = (try? c.decodeIfPresent(Bool.self, forKey: .missing)) ?? false
        }
    }

    struct ProgressEntry: Decodable, Identifiable {
        let id: String
        let label: String
        let primitive: String
        let philosophy: String
        let headline: Bool
        let source: String?               // declared | default
        let metric: String
        let unit: String
        let status: String
        let trend: Trend?
        let coverage: Coverage?
        let evidence: [String]
        let series: [SeriesPoint]
        let expected: [ExpectedPoint]
        let exercises: [ExerciseResult]
        let leadExerciseId: String?
        let practised: [Practised]
        let available: [Practised]
        let benchmarks: [BenchmarkRow]

        private enum CodingKeys: String, CodingKey {
            case id, label, primitive, philosophy, headline, source, metric, unit, status, trend, coverage,
                 evidence, series, expected, exercises, leadExerciseId, practised, available, benchmarks
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            label = (try? c.decodeIfPresent(String.self, forKey: .label)) ?? id
            primitive = (try? c.decodeIfPresent(String.self, forKey: .primitive)) ?? ""
            philosophy = (try? c.decodeIfPresent(String.self, forKey: .philosophy)) ?? ""
            headline = (try? c.decodeIfPresent(Bool.self, forKey: .headline)) ?? false
            source = try? c.decodeIfPresent(String.self, forKey: .source)
            metric = (try? c.decodeIfPresent(String.self, forKey: .metric)) ?? ""
            unit = (try? c.decodeIfPresent(String.self, forKey: .unit)) ?? ""
            status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "insufficient_data"
            trend = try? c.decodeIfPresent(Trend.self, forKey: .trend)
            coverage = try? c.decodeIfPresent(Coverage.self, forKey: .coverage)
            evidence = (try? c.decodeIfPresent([String].self, forKey: .evidence)) ?? []
            series = ((try? c.decodeIfPresent([Lossy<SeriesPoint>].self, forKey: .series)) ?? [])?.compactMap(\.value) ?? []
            expected = ((try? c.decodeIfPresent([Lossy<ExpectedPoint>].self, forKey: .expected)) ?? [])?.compactMap(\.value) ?? []
            exercises = ((try? c.decodeIfPresent([Lossy<ExerciseResult>].self, forKey: .exercises)) ?? [])?.compactMap(\.value) ?? []
            leadExerciseId = try? c.decodeIfPresent(String.self, forKey: .leadExerciseId)
            practised = ((try? c.decodeIfPresent([Lossy<Practised>].self, forKey: .practised)) ?? [])?.compactMap(\.value) ?? []
            available = ((try? c.decodeIfPresent([Lossy<Practised>].self, forKey: .available)) ?? [])?.compactMap(\.value) ?? []
            benchmarks = ((try? c.decodeIfPresent([Lossy<BenchmarkRow>].self, forKey: .benchmarks)) ?? [])?.compactMap(\.value) ?? []
        }

        /// The exercise whose series the card opens on — the lead lift, else the first.
        var leadExercise: ExerciseResult? {
            exercises.first { $0.exerciseId == leadExerciseId } ?? exercises.first
        }
    }

    struct Methodology: Decodable, Identifiable {
        let philosophy: String
        let weight: Double
        let analytics: String             // declared | default
        let headlineId: String?
        let entryIds: [String]
        let measurable: Int
        let total: Int
        var id: String { philosophy }

        private enum CodingKeys: String, CodingKey { case philosophy, weight, analytics, headlineId, entryIds, measurable, total }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            philosophy = try c.decode(String.self, forKey: .philosophy)
            weight = (try? c.decodeIfPresent(Double.self, forKey: .weight)) ?? 1
            analytics = (try? c.decodeIfPresent(String.self, forKey: .analytics)) ?? "default"
            headlineId = try? c.decodeIfPresent(String.self, forKey: .headlineId)
            entryIds = (try? c.decodeIfPresent([String].self, forKey: .entryIds)) ?? []
            measurable = (try? c.decodeIfPresent(Int.self, forKey: .measurable)) ?? 0
            total = (try? c.decodeIfPresent(Int.self, forKey: .total)) ?? 0
        }
    }

    // MARK: Intensity — the planned distribution against the actual one

    struct Intensity: Decodable {
        struct Week: Decodable, Identifiable {
            let week: Int
            let isDeload: Bool
            let zone12Pct: Double
            let zone3Pct: Double
            let zone45Pct: Double
            let maxEffortPct: Double
            let sessions: Int
            let classifiedMinutes: Double
            let plannedPct: [String: Double]?
            var id: Int { week }

            private enum CodingKeys: String, CodingKey {
                case week, isDeload, sessions, classifiedMinutes, plannedPct
                case zone12Pct = "zone1_2_pct"
                case zone3Pct = "zone3_pct"
                case zone45Pct = "zone4_5_pct"
                case maxEffortPct = "max_effort_pct"
            }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                week = try c.decode(Int.self, forKey: .week)
                isDeload = (try? c.decodeIfPresent(Bool.self, forKey: .isDeload)) ?? false
                zone12Pct = (try? c.decodeIfPresent(Double.self, forKey: .zone12Pct)) ?? 0
                zone3Pct = (try? c.decodeIfPresent(Double.self, forKey: .zone3Pct)) ?? 0
                zone45Pct = (try? c.decodeIfPresent(Double.self, forKey: .zone45Pct)) ?? 0
                maxEffortPct = (try? c.decodeIfPresent(Double.self, forKey: .maxEffortPct)) ?? 0
                sessions = (try? c.decodeIfPresent(Int.self, forKey: .sessions)) ?? 0
                classifiedMinutes = (try? c.decodeIfPresent(Double.self, forKey: .classifiedMinutes)) ?? 0
                plannedPct = try? c.decodeIfPresent([String: Double].self, forKey: .plannedPct)
            }
        }
        let status: String
        let coverage: Coverage?
        let maxHr: Int?
        let weeks: [Week]
        let maxDeviationPts: Double?

        private enum CodingKeys: String, CodingKey { case status, coverage, maxHr, weeks, maxDeviationPts }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "insufficient_data"
            coverage = try? c.decodeIfPresent(Coverage.self, forKey: .coverage)
            maxHr = try? c.decodeIfPresent(Int.self, forKey: .maxHr)
            weeks = ((try? c.decodeIfPresent([Lossy<Week>].self, forKey: .weeks)) ?? [])?.compactMap(\.value) ?? []
            maxDeviationPts = try? c.decodeIfPresent(Double.self, forKey: .maxDeviationPts)
        }
    }

    // MARK: Movement — pattern balance

    struct Movement: Decodable {
        struct Balance: Decodable, Identifiable {
            let a: String
            let b: String
            let ratio: Double?
            let min: Double
            let max: Double
            let level: String              // info | warning
            let outside: Bool
            let declared: Bool
            var id: String { "\(a)/\(b)" }
        }
        let balance: [Balance]

        private enum CodingKeys: String, CodingKey { case balance }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            balance = ((try? c.decodeIfPresent([Lossy<Balance>].self, forKey: .balance)) ?? [])?.compactMap(\.value) ?? []
        }
    }

    // MARK: Load — the stress balance read in the phase's terms

    struct Load: Decodable {
        struct Readiness: Decodable {
            let score: Int
            let status: String
        }
        let readiness: Readiness?
        let phase: String?
        let isDeload: Bool
        let tsb: Double?
        let reading: String?
        let note: String?

        private enum CodingKeys: String, CodingKey { case readiness, phase, isDeload, tsb, reading, note }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            readiness = try? c.decodeIfPresent(Readiness.self, forKey: .readiness)
            phase = try? c.decodeIfPresent(String.self, forKey: .phase)
            isDeload = (try? c.decodeIfPresent(Bool.self, forKey: .isDeload)) ?? false
            tsb = try? c.decodeIfPresent(Double.self, forKey: .tsb)
            reading = try? c.decodeIfPresent(String.self, forKey: .reading)
            note = try? c.decodeIfPresent(String.self, forKey: .note)
        }
    }
}
