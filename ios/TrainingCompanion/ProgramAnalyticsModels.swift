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
    /// Per session shape: how each archetype in the block is going.
    let archetypes: [ArchetypeRow]?
    /// The standards this program is measured by, and where the athlete stands.
    let benchmarks: Benchmarks?
    let load: Load?
    /// Sections the server could not compute, by name, with its reason.
    let sectionErrors: [String: String]

    var hasProgram: Bool { status != "no_program" }

    private enum CodingKeys: String, CodingKey {
        case status, revision, generatedAt, frame, scorecard, intensity, methodologies, progress, movement,
             archetypes, benchmarks, load
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
        archetypes = section([Lossy<ArchetypeRow>].self, .archetypes)?.compactMap(\.value)
        benchmarks = section(Benchmarks.self, .benchmarks)
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
            let progressionPhilosophy: String?
            let intensityModel: String?
        }
        struct Framework: Decodable {
            let id: String
            let name: String
            let progressionModel: String?
        }
        struct Phase: Decodable {
            /// The phase kind (colour, and the label of last resort).
            let name: String
            /// The methodology's own phase id and name, and its description.
            /// Absent from servers that predate philosophy-owned phases.
            let id: String?
            let label: String?
            let weekInPhase: Int?
            let weekInProgram: Int
            let totalWeeks: Int
            let focus: String?
            let description: String?
            let isDeload: Bool

            var displayName: String { label ?? name.replacingOccurrences(of: "_", with: " ").capitalized }
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
        /// Completion per program week, elapsed sessions only — Today's
        /// card. Empty from a server older than the series.
        struct Week: Decodable {
            let weekIndex: Int
            let weekNumber: Int
            let planned: Int
            let completed: Int
            let pct: Double?
        }
        let weeks: [Week]
        let plannedSessions: Int?
        let completedSessions: Int?
        /// This week: done of those due so far, and how many the week holds.
        struct CurrentWeek: Decodable {
            let weekIndex: Int
            let weekNumber: Int
            let due: Int
            let completed: Int
            let total: Int
            let isDeload: Bool?
        }
        let currentWeek: CurrentWeek?

        private enum CodingKeys: String, CodingKey {
            case headline, overallPct, tiers, elapsedWeeks, modalities, weeks, plannedSessions, completedSessions, currentWeek
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            headline = (try? c.decodeIfPresent(String.self, forKey: .headline)) ?? "not_started"
            overallPct = try? c.decodeIfPresent(Double.self, forKey: .overallPct)
            tiers = (try? c.decodeIfPresent([String: Tier].self, forKey: .tiers)) ?? [:]
            elapsedWeeks = (try? c.decodeIfPresent(Int.self, forKey: .elapsedWeeks)) ?? 0
            modalities = ((try? c.decodeIfPresent([Lossy<Row>].self, forKey: .modalities)) ?? [])?.compactMap(\.value) ?? []
            weeks = ((try? c.decodeIfPresent([Lossy<Week>].self, forKey: .weeks)) ?? [])?.compactMap(\.value) ?? []
            plannedSessions = try? c.decodeIfPresent(Int.self, forKey: .plannedSessions)
            completedSessions = try? c.decodeIfPresent(Int.self, forKey: .completedSessions)
            currentWeek = try? c.decodeIfPresent(CurrentWeek.self, forKey: .currentWeek)
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
        /// set_load: "kg", or "reps" for a lift with no kg prescribed or logged.
        let unit: String?
        var id: String { exerciseId }

        private enum CodingKeys: String, CodingKey {
            case exerciseId, name, series, expected, trend, status, stalled, prescribedNow, bestEst1rm, unit
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
            unit = try? c.decodeIfPresent(String.self, forKey: .unit)
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
        /// The latest result as the server prints it ("4:58").
        let latestText: String?
        let target: String?
        let targetValue: Double?
        let met: Bool?
        let level: String?
        let levelIndex: Int?
        let next: String?
        let domain: String?
        /// The thresholds as printed, keyed by level, for the ladder.
        let standardsText: [String: String]
        let missing: Bool
        var id: String { benchmarkId }

        private enum CodingKeys: String, CodingKey {
            case benchmarkId, name, unit, latest, latestText, target, targetValue, met, level, levelIndex, next,
                 domain, standardsText, missing
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            benchmarkId = try c.decode(String.self, forKey: .benchmarkId)
            name = try? c.decodeIfPresent(String.self, forKey: .name)
            unit = try? c.decodeIfPresent(String.self, forKey: .unit)
            latest = try? c.decodeIfPresent(Double.self, forKey: .latest)
            latestText = try? c.decodeIfPresent(String.self, forKey: .latestText)
            target = try? c.decodeIfPresent(String.self, forKey: .target)
            targetValue = try? c.decodeIfPresent(Double.self, forKey: .targetValue)
            met = try? c.decodeIfPresent(Bool.self, forKey: .met)
            level = try? c.decodeIfPresent(String.self, forKey: .level)
            levelIndex = try? c.decodeIfPresent(Int.self, forKey: .levelIndex)
            next = try? c.decodeIfPresent(String.self, forKey: .next)
            domain = try? c.decodeIfPresent(String.self, forKey: .domain)
            standardsText = ((try? c.decodeIfPresent([String: String].self, forKey: .standardsText)) ?? nil) ?? [:]
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
        /// unlocks: movements still locked with practice, those the level opened
        /// from day one, and how many the program draws on.
        let lockedCount: Int
        let assumedCount: Int
        let programTotal: Int?
        /// False when no session of this program is in scope — a pentathlon
        /// cadence in General Practice. Absent on older documents: applies.
        let applies: Bool
        let appliesIn: [AppliesIn]

        struct AppliesIn: Decodable {
            let trackId: String?
            let track: String
            let phases: [String]?
        }

        private enum CodingKeys: String, CodingKey {
            case id, label, primitive, philosophy, headline, source, metric, unit, status, trend, coverage,
                 evidence, series, expected, exercises, leadExerciseId, practised, available, benchmarks,
                 lockedCount, assumedCount, programTotal, applies, appliesIn
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
            lockedCount = (try? c.decodeIfPresent(Int.self, forKey: .lockedCount)) ?? 0
            assumedCount = (try? c.decodeIfPresent(Int.self, forKey: .assumedCount)) ?? 0
            programTotal = try? c.decodeIfPresent(Int.self, forKey: .programTotal)
            applies = (try? c.decodeIfPresent(Bool.self, forKey: .applies)) ?? true
            appliesIn = ((try? c.decodeIfPresent([Lossy<AppliesIn>].self, forKey: .appliesIn)) ?? [])?.compactMap(\.value) ?? []
        }

        /// Practice opens nothing the athlete's level had not already opened
        /// (all of Wildman's library): say so instead of an empty list.
        var levelOpensAll: Bool { available.isEmpty && lockedCount == 0 && assumedCount > 0 }

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
        /// Entries that apply to this program; older documents send none.
        let applicable: Int?
        let total: Int
        /// The headline in a sentence, worded by the server for Today.
        let headlineSummary: HeadlineSummary?
        var id: String { philosophy }

        private enum CodingKeys: String, CodingKey { case philosophy, weight, analytics, headlineId, entryIds, measurable, applicable, total, headlineSummary }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            philosophy = try c.decode(String.self, forKey: .philosophy)
            weight = (try? c.decodeIfPresent(Double.self, forKey: .weight)) ?? 1
            analytics = (try? c.decodeIfPresent(String.self, forKey: .analytics)) ?? "default"
            headlineId = try? c.decodeIfPresent(String.self, forKey: .headlineId)
            entryIds = (try? c.decodeIfPresent([String].self, forKey: .entryIds)) ?? []
            measurable = (try? c.decodeIfPresent(Int.self, forKey: .measurable)) ?? 0
            applicable = try? c.decodeIfPresent(Int.self, forKey: .applicable)
            headlineSummary = try? c.decodeIfPresent(HeadlineSummary.self, forKey: .headlineSummary)
            total = (try? c.decodeIfPresent(Int.self, forKey: .total)) ?? 0
        }
    }

    /// `document.headline_summary`: the methodology's own currency in one
    /// sentence ("Back squat 102.5kg", "3 of 12 movements practised") and
    /// which way it is moving. `text` is nil when nothing measured it yet;
    /// `reason` then says why, in the coverage codes.
    struct HeadlineSummary: Decodable {
        let entryId: String
        let label: String
        let status: String
        let inScope: Int
        let reason: String?
        let text: String?
        let trendDirection: String?
        let trendText: String?

        private enum CodingKeys: String, CodingKey { case entryId, label, status, inScope, reason, text, trendDirection, trendText }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            entryId = try c.decode(String.self, forKey: .entryId)
            label = (try? c.decodeIfPresent(String.self, forKey: .label)) ?? entryId
            status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "insufficient_data"
            inScope = (try? c.decodeIfPresent(Int.self, forKey: .inScope)) ?? 0
            reason = try? c.decodeIfPresent(String.self, forKey: .reason)
            text = try? c.decodeIfPresent(String.self, forKey: .text)
            trendDirection = try? c.decodeIfPresent(String.self, forKey: .trendDirection)
            trendText = try? c.decodeIfPresent(String.self, forKey: .trendText)
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
        /// One framework's split over its weeks: actual and planned shares in
        /// percent, keyed by bucket (`zone1_2_pct` …), and the deviation.
        struct ByFramework: Decodable {
            let frameworkId: String?
            let classifiedMinutes: Double?
            let actualPct: [String: Double?]
            let plannedPct: [String: Double]?
            let deviationPts: [String: Double]?
        }
        /// One HR zone, over the completed sessions:
        /// the minutes their slots planned in it and the minutes their heart
        /// rate recorded. Only zones with either.
        struct Zone: Decodable, Identifiable {
            let zone: String               // z1 … z5
            let label: String
            let plannedMinutes: Double
            let actualMinutes: Double
            var id: String { zone }
        }
        /// Working sets as a share of estimated 1RM — max-effort frameworks only.
        struct Pct1RM: Decodable {
            let sessions: Int
            let meanPct: Double?
        }
        let status: String
        let coverage: Coverage?
        let maxHr: Int?
        /// Each week's bucket fields (`zone12Pct` …) are **minutes**, despite
        /// the `_pct` in the server's keys; the shares are `actualPct`.
        let weeks: [Week]
        let maxDeviationPts: Double?
        let byFramework: [ByFramework]
        /// Empty from an older server, which sent only the buckets.
        let zones: [Zone]
        let pct1rm: Pct1RM?

        private enum CodingKeys: String, CodingKey { case status, coverage, maxHr, weeks, maxDeviationPts, byFramework, zones, pct1rm }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "insufficient_data"
            coverage = try? c.decodeIfPresent(Coverage.self, forKey: .coverage)
            maxHr = try? c.decodeIfPresent(Int.self, forKey: .maxHr)
            weeks = ((try? c.decodeIfPresent([Lossy<Week>].self, forKey: .weeks)) ?? [])?.compactMap(\.value) ?? []
            byFramework = ((try? c.decodeIfPresent([Lossy<ByFramework>].self, forKey: .byFramework)) ?? [])?.compactMap(\.value) ?? []
            zones = ((try? c.decodeIfPresent([Lossy<Zone>].self, forKey: .zones)) ?? [])?.compactMap(\.value) ?? []
            pct1rm = try? c.decodeIfPresent(Pct1RM.self, forKey: .pct1rm)
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
        /// Done against planned per rolled-up pattern (push, pull, hinge…).
        struct Rollup: Decodable {
            let planned: Double
            let done: Double
        }
        struct Table: Decodable {
            let rollups: [String: Rollup]
            /// Minutes only: prescribed minutes counted for completed sessions
            /// with no matched workout.
            let assumed: Double?
            private enum CodingKeys: String, CodingKey { case rollups, assumed }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                rollups = (try? c.decodeIfPresent([String: Rollup].self, forKey: .rollups)) ?? [:]
                assumed = try? c.decodeIfPresent(Double.self, forKey: .assumed)
            }
            /// Largest planned first, as on the web.
            var rows: [(pattern: String, value: Rollup)] {
                rollups.map { ($0.key, $0.value) }.sorted { $0.value.planned > $1.value.planned }
            }
        }
        struct Share: Decodable {
            let planned: Double?
            let done: Double?
        }
        let balance: [Balance]
        let sets: Table?
        let minutes: Table?
        let unilateralShare: Share?

        private enum CodingKeys: String, CodingKey { case balance, sets, minutes, unilateralShare }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            balance = ((try? c.decodeIfPresent([Lossy<Balance>].self, forKey: .balance)) ?? [])?.compactMap(\.value) ?? []
            sets = try? c.decodeIfPresent(Table.self, forKey: .sets)
            minutes = try? c.decodeIfPresent(Table.self, forKey: .minutes)
            unilateralShare = try? c.decodeIfPresent(Share.self, forKey: .unilateralShare)
        }

        var isEmpty: Bool {
            balance.isEmpty && (sets?.rollups.isEmpty ?? true) && (minutes?.rollups.isEmpty ?? true)
        }
    }

    // MARK: Session shapes — one row per archetype in the block

    struct ArchetypeRow: Decodable, Identifiable {
        struct HR: Decodable { let avg: Int?; let max: Int? }
        struct LeadLift: Decodable {
            let exerciseId: String
            let firstEst1rm: Double?
            let latestEst1rm: Double?
        }
        let archetypeId: String
        let name: String
        let modality: String?
        let scheduled: Int
        let completed: Int
        let meanDurationDeltaPct: Double?
        let hr: HR?
        let leadLift: LeadLift?
        var id: String { archetypeId }

        private enum CodingKeys: String, CodingKey {
            case archetypeId, name, modality, scheduled, completed, meanDurationDeltaPct, hr, leadLift
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            archetypeId = try c.decode(String.self, forKey: .archetypeId)
            name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? archetypeId
            modality = try? c.decodeIfPresent(String.self, forKey: .modality)
            scheduled = (try? c.decodeIfPresent(Int.self, forKey: .scheduled)) ?? 0
            completed = (try? c.decodeIfPresent(Int.self, forKey: .completed)) ?? 0
            meanDurationDeltaPct = try? c.decodeIfPresent(Double.self, forKey: .meanDurationDeltaPct)
            hr = try? c.decodeIfPresent(HR.self, forKey: .hr)
            leadLift = try? c.decodeIfPresent(LeadLift.self, forKey: .leadLift)
        }
    }

    // MARK: Standards — the program's ladders

    struct Benchmarks: Decodable {
        struct Row: Decodable, Identifiable {
            let benchmarkId: String
            let name: String
            let unit: String
            let lowerIsBetter: Bool
            /// declared | tested | philosophy | priority_modality
            let why: [String]
            /// The program's own: declared by its package or measured by a test
            /// it schedules; the rest wait behind "More standards".
            let primary: Bool
            let standards: [String: Double]
            /// The thresholds as the server prints them ("4:30", "1.5×BW").
            let standardsText: [String: String]
            let value: Double?
            /// The value as printed; nil on a document from before the server said.
            let valueText: String?
            let valueSource: String?      // logged | derived
            let level: String?
            /// 0 = below entry … 4 = elite, from the server.
            let levelIndex: Int
            let next: String?
            let gapToNext: Double?
            let gapText: String?
            let derivedReason: String?
            /// The modality the standard measures (`max_strength`,
            /// `strength_endurance`…), which colours its ladder.
            let domain: String?
            /// Where the athlete stood when the block began.
            let atBlockStart: BlockPoint?
            /// Levels moved this block; nil with nothing to compare.
            let levelChange: Int?
            /// The block's results, its starting standing first.
            let blockHistory: [BlockPoint]
            var id: String { benchmarkId }

            struct BlockPoint: Decodable {
                let date: String
                let value: Double
                let valueText: String
                let level: String?
            }

            private struct Derived: Decodable { let reason: String? }
            private enum CodingKeys: String, CodingKey {
                case benchmarkId, name, unit, lowerIsBetter, why, primary, standards, standardsText, value, valueText,
                     valueSource, level, levelIndex, next, gapToNext, gapText, derived, domain,
                     atBlockStart, levelChange, blockHistory
            }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                benchmarkId = try c.decode(String.self, forKey: .benchmarkId)
                name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? benchmarkId
                unit = (try? c.decodeIfPresent(String.self, forKey: .unit)) ?? ""
                lowerIsBetter = (try? c.decodeIfPresent(Bool.self, forKey: .lowerIsBetter)) ?? false
                why = (try? c.decodeIfPresent([String].self, forKey: .why)) ?? []
                primary = (try? c.decodeIfPresent(Bool.self, forKey: .primary)) ?? true
                standards = (try? c.decodeIfPresent([String: Double].self, forKey: .standards)) ?? [:]
                standardsText = ((try? c.decodeIfPresent([String: String].self, forKey: .standardsText)) ?? nil) ?? [:]
                value = try? c.decodeIfPresent(Double.self, forKey: .value)
                valueText = try? c.decodeIfPresent(String.self, forKey: .valueText)
                valueSource = try? c.decodeIfPresent(String.self, forKey: .valueSource)
                level = try? c.decodeIfPresent(String.self, forKey: .level)
                levelIndex = ((try? c.decodeIfPresent(Int.self, forKey: .levelIndex)) ?? nil) ?? 0
                next = try? c.decodeIfPresent(String.self, forKey: .next)
                gapToNext = try? c.decodeIfPresent(Double.self, forKey: .gapToNext)
                gapText = try? c.decodeIfPresent(String.self, forKey: .gapText)
                derivedReason = (try? c.decodeIfPresent(Derived.self, forKey: .derived))?.reason
                domain = try? c.decodeIfPresent(String.self, forKey: .domain)
                atBlockStart = try? c.decodeIfPresent(BlockPoint.self, forKey: .atBlockStart)
                levelChange = try? c.decodeIfPresent(Int.self, forKey: .levelChange)
                blockHistory = ((try? c.decodeIfPresent([Lossy<BlockPoint>].self, forKey: .blockHistory)) ?? nil)?
                    .compactMap(\.value) ?? []
            }

            /// The thresholds as text — the server's, or number + unit for an
            /// older cached document.
            var thresholdTexts: [String: String] {
                guard standardsText.isEmpty else { return standardsText }
                return standards.mapValues { "\(AnalyticsProgramTab.number($0))\(unit)" }
            }
        }
        let bodyweightKg: Double?
        let bodyweightText: String?
        let rows: [Row]

        private enum CodingKeys: String, CodingKey { case bodyweightKg, bodyweightText, benchmarks }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            bodyweightKg = try? c.decodeIfPresent(Double.self, forKey: .bodyweightKg)
            bodyweightText = try? c.decodeIfPresent(String.self, forKey: .bodyweightText)
            rows = ((try? c.decodeIfPresent([Lossy<Row>].self, forKey: .benchmarks)) ?? [])?.compactMap(\.value) ?? []
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
