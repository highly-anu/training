import Foundation

// An athlete's own methods and the builds that write them (docs/roadmap.md
// item 21): what `/api/methods` answers, the request a build is started with,
// and the words the screens say. The athlete reads *method*; the server keeps
// *package*. The web's copies are `api/methods.ts` and `lib/methodBuild.ts` —
// change the words in both.

/// One of the athlete's methods, as the list names it.
struct MethodSummary: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let revision: Int
    /// The active program is built from it: it cannot be deleted.
    let inUse: Bool

    private enum CodingKeys: String, CodingKey { case id, name, revision, inUse }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? id
        revision = (try? c.decode(Int.self, forKey: .revision)) ?? 1
        inUse = (try? c.decode(Bool.self, forKey: .inUse)) ?? false
    }
}

/// A build: queued, running, or ended one of three ways.
struct MethodBuild: Decodable, Identifiable, Hashable {
    struct Progress: Decodable, Hashable {
        var stage: String?
        var detail: String?
    }

    struct Outcome: Decodable, Hashable {
        let packageId: String
        let revision: Int?
        let name: String
        let summary: String?
    }

    struct Failure: Decodable, Hashable {
        let code: String?
        let message: String?
    }

    let id: String
    let status: String
    let progress: Progress
    let result: Outcome?
    let error: Failure?
    /// The athlete's words, shortened.
    let description: String?
    /// The id of the method this build revises, when it is a revision.
    let revise: String?

    private enum CodingKeys: String, CodingKey { case id, status, progress, result, error, description, revise }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        status = (try? c.decode(String.self, forKey: .status)) ?? "queued"
        progress = (try? c.decode(Progress.self, forKey: .progress)) ?? Progress()
        result = try? c.decode(Outcome.self, forKey: .result)
        error = try? c.decode(Failure.self, forKey: .error)
        description = try? c.decode(String.self, forKey: .description)
        revise = try? c.decode(String.self, forKey: .revise)
    }

    /// Still being built: the screen asks again.
    var isOpen: Bool { status == "queued" || status == "running" }
    var isDone: Bool { status == "done" && result != nil }
}

/// `GET /api/methods`: whether a build can start, the methods, the builds.
struct MethodsAnswer: Decodable {
    struct Limits: Decodable {
        var daily = 0
        var remaining = 0
    }

    let available: Bool
    /// Why not: `not_enabled` for this athlete, `no_model_key` on the server.
    let reason: String?
    let methods: [MethodSummary]
    /// The open build first, then recent ones.
    let builds: [MethodBuild]
    let limits: Limits

    private enum CodingKeys: String, CodingKey { case available, reason, methods, builds, limits }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        available = (try? c.decode(Bool.self, forKey: .available)) ?? false
        reason = try? c.decode(String.self, forKey: .reason)
        methods = ((try? c.decode([Lossy<MethodSummary>].self, forKey: .methods)) ?? []).compactMap(\.value)
        builds = ((try? c.decode([Lossy<MethodBuild>].self, forKey: .builds)) ?? []).compactMap(\.value)
        limits = (try? c.decode(Limits.self, forKey: .limits)) ?? Limits()
    }

    /// The build in progress, if there is one.
    var openBuild: MethodBuild? { builds.first(where: \.isOpen) }

    /// The methods and their builds are shown at all: the account may build,
    /// or has methods from when it could.
    var isShown: Bool { reason != "not_enabled" }
}

/// What a build is started with: a description, or a change to a method.
struct MethodBuildRequest: Encodable, Equatable {
    struct Answers: Encodable, Equatable {
        var days: Int
        var minutes: Int
        var level: String
        var equipment: [String]
    }

    struct Revision: Encodable, Equatable {
        let packageId: String
        let note: String
    }

    var description: String?
    var answers: Answers
    var pastedText: String?
    var webSearch: Bool
    var revise: Revision?

    /// The describe form as a request: a new method, or a revision of `revises`.
    init(text: String, pastedText: String, webSearch: Bool, answers: Answers, revises: String?) {
        let said = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pasted = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.answers = answers
        self.webSearch = webSearch
        if let revises {
            revise = Revision(packageId: revises, note: said)
        } else {
            description = said
            self.pastedText = pasted.isEmpty ? nil : pasted
        }
    }
}

/// How a start ended: a build to watch, or why there is none.
enum MethodBuildStart: Equatable {
    /// Queued, or the one already running (the screen goes to it either way).
    case build(MethodBuild)
    case refused(String)
}

/// The builder's words. Pure, so the screens only lay them out.
enum MethodBuildWords {
    static let descriptionLength = 20...8000
    static let noteLength = 5...2000
    static let pastedMax = 60_000
    static let minutes = [20, 30, 45, 60, 75, 90, 120]
    static let days = Array(2...7)

    /// The steps a build goes through, in order, as the athlete reads them.
    static let steps: [(stage: String, label: String)] = [
        ("reading", "Reading your description"),
        ("writing", "Writing the method"),
        ("checking", "Checking that it generates a program"),
        ("installing", "Adding it to your methods"),
    ]

    /// Where a build stands among `steps` (research counts as reading, a fix
    /// as checking); past the last when it is done.
    static func stepIndex(_ build: MethodBuild) -> Int {
        if build.status == "done" { return steps.count }
        let stage = build.progress.stage
        let at = stage == "researching" ? "reading" : stage == "fixing" ? "checking" : stage
        return steps.firstIndex { $0.stage == at } ?? 0
    }

    /// One line for what the build is doing now.
    static func headline(_ build: MethodBuild) -> String {
        if build.status == "queued" { return "Waiting to start" }
        switch build.progress.stage {
        case "researching": return "Reading about the method"
        case "writing": return "Writing the method"
        case "checking": return "Checking that it generates a program"
        case "fixing": return "Fixing what the checks found"
        case "installing": return "Adding it to your methods"
        default: return "Reading your description"
        }
    }

    /// Why the form's text cannot be sent, or nil.
    static func textProblem(_ text: String, length: ClosedRange<Int>, what: String) -> String? {
        let count = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        if count < length.lowerBound {
            return "Say a little more: \(what) needs at least \(length.lowerBound) characters."
        }
        if count > length.upperBound {
            return "Shorten it: \(what) takes at most \(length.upperBound.formatted()) characters."
        }
        return nil
    }

    /// Why a build cannot be started at all right now, or nil.
    static func unavailableReason(_ methods: MethodsAnswer?) -> String? {
        guard let methods else { return nil }
        if !methods.available {
            return methods.reason == "no_model_key"
                ? "Methods cannot be built right now."
                : "Building your own method is not turned on for this account."
        }
        if methods.limits.remaining <= 0 { return "You have used today's builds. Try again tomorrow." }
        return nil
    }

    /// A start's answer, by its status and body: the build that was queued, the
    /// one already running, or the refusal in the athlete's words.
    static func start(status: Int, body: Data) -> MethodBuildStart {
        struct Answer: Decodable {
            let build: MethodBuild?
            let error: String?
            let detail: String?
        }
        let answer = try? JSONDecoder().decode(Answer.self, from: body)
        if let build = answer?.build, (200..<300).contains(status) || answer?.error == "build_running" {
            return .build(build)
        }
        switch answer?.error {
        case "not_enabled": return .refused("Building your own method is not turned on for this account.")
        case "not_found": return .refused("That method is no longer among yours.")
        default: return .refused(answer?.detail ?? "The build could not be started. Try again.")
        }
    }

    /// Why a method could not be deleted, or nil when it was.
    static func deleteRefusal(status: Int, body: Data) -> String? {
        if (200..<300).contains(status) { return nil }
        struct Answer: Decodable { let error: String? }
        if (try? JSONDecoder().decode(Answer.self, from: body))?.error == "in_use" {
            return "Your program is built from this method. Start another program first."
        }
        return "The method could not be deleted. Try again."
    }
}
