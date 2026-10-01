import Foundation

/// Which API this build talks to.
///
/// Production comes from Info.plist (`API_BASE_URL`). A developer can point a
/// simulator at the local Flask server instead — `API_BASE_URL` in the launch
/// environment (`SIMCTL_CHILD_API_BASE_URL=… xcrun simctl launch`), or the
/// `apiBaseURLOverride` default, which `LOCAL_API=1 ./ios/run_sim.sh` writes —
/// so every screen can be looked at with the local dev program instead of
/// production's. The local server runs with Supabase unset and answers as
/// `local-dev-user` without a token, so a local target also means no sign-in.
enum APITarget {
    static let overrideDefaultsKey = "apiBaseURLOverride"
    static let environmentKey = "API_BASE_URL"
    static let localBaseURL = "http://localhost:8000/api"
    static let fallbackBaseURL = "https://training-api.fly.dev/api"

    /// What the build was configured with.
    static var productionBaseURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String) ?? fallbackBaseURL
    }

    /// Environment first (one launch), then the stored override (until
    /// cleared), then the build's own URL.
    static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment,
                        defaults: UserDefaults = .standard,
                        production: String = productionBaseURL) -> String {
        if let env = environment[environmentKey]?.trimmingCharacters(in: .whitespaces), !env.isEmpty { return env }
        if let stored = defaults.string(forKey: overrideDefaultsKey)?.trimmingCharacters(in: .whitespaces),
           !stored.isEmpty { return stored }
        return production
    }

    static var baseURL: String { resolve() }

    /// True when the URL names this machine: localhost, the loopback
    /// addresses, or a `.local` host — the targets that run without auth.
    static func isLocal(_ baseURL: String) -> Bool {
        guard let host = URL(string: baseURL)?.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".local")
    }

    static var isLocal: Bool { isLocal(baseURL) }

    static var isOverridden: Bool {
        UserDefaults.standard.string(forKey: overrideDefaultsKey).map { !$0.isEmpty } ?? false
    }

    /// Store (or clear, with nil) the override. Takes effect on the next
    /// request; `AuthManager.applyTargetChange()` re-evaluates the sign-in gate.
    static func setOverride(_ baseURL: String?, defaults: UserDefaults = .standard) {
        let trimmed = baseURL?.trimmingCharacters(in: .whitespaces) ?? ""
        if trimmed.isEmpty {
            defaults.removeObject(forKey: overrideDefaultsKey)
        } else {
            defaults.set(trimmed, forKey: overrideDefaultsKey)
        }
    }
}
