import Foundation
import Combine
import CryptoKit
import AuthenticationServices
import Auth

/// The phone's Supabase account, through supabase-swift's `Auth` module.
///
/// Sign in with Apple creates the account when there is none, so nobody needs
/// the web to sign up, and it sends no email and needs no domain. Email +
/// password stays for accounts made on the web. An emailed code and passkeys
/// wait for mail and a permanent domain (roadmap item 11).
///
/// The session lives in the Keychain and the SDK refreshes it. Builds before
/// 2026-10 kept it in UserDefaults; `init` hands that one to the SDK once, so
/// an update signs nobody out (`LegacySession`).
@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var isSignedIn = false
    @Published private(set) var accessToken: String? = nil
    @Published private(set) var account: AccountSummary? = nil

    static let supabaseURL = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String ?? ""
    static let supabaseAnonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? ""

    /// nil without a configured project (a build with Info.plist keys unset).
    let client: AuthClient?
    let defaults: UserDefaults
    /// Lives as long as the app; holds `self` weakly, and no deinit cancels
    /// it — an isolated deinit aborts under XCTest (CurrentWeekIndexTests).
    private var listener: Task<Void, Never>?
    private var restored = false

    init(storage: (any AuthLocalStorage)? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let url = URL(string: Self.supabaseURL), !Self.supabaseURL.isEmpty {
            client = AuthClient(
                url: url.appendingPathComponent("/auth/v1"),
                headers: ["apikey": Self.supabaseAnonKey,
                          "Authorization": "Bearer \(Self.supabaseAnonKey)"],
                localStorage: storage ?? KeychainLocalStorage(service: "haerdsoft.TrainingCompanion.auth"),
                // Offline at launch is still signed in; the SDK refreshes
                // the stored session when it can and signs out only when the
                // server refuses it.
                emitLocalSessionAsInitialSession: true
            )
        } else {
            client = nil
        }
        // The old Face ID shortcut replayed a stored password. The SDK keeps
        // the session and refreshes it, so a sign-in is rare; the password
        // should not linger for it.
        LegacyCredentials.purge()
        applyTargetChange()
        listen()
    }

    /// True while the app is pointed at a local server (`APITarget`), which
    /// needs no account: the gate is open and no token is sent.
    var isLocalTarget: Bool { APITarget.isLocal }

    /// Re-evaluate the sign-in gate for the current API target: a local target
    /// is signed in by definition; production reads the stored session.
    func applyTargetChange() {
        if APITarget.isLocal {
            isSignedIn = true
            return
        }
        if client?.currentSession == nil, let legacy = LegacySession.peek(in: defaults) {
            // An update from a build that kept the session in UserDefaults:
            // stay signed in while `restoreLegacySessionIfNeeded` moves it.
            accessToken = legacy.accessToken
            isSignedIn = true
            return
        }
        apply(client?.currentSession)
    }

    /// Hands the SDK a fresh token if the current one is about to expire.
    /// Safe to call before every API request.
    func refreshIfNeeded() async {
        guard !APITarget.isLocal, let client else { return }
        await restoreLegacySessionIfNeeded()
        if let session = try? await client.session { apply(session) }
    }

    // MARK: - Sign in / sign up

    /// A fresh nonce for one Sign in with Apple request: `raw` goes to
    /// Supabase, `hashed` into Apple's request, and Supabase checks one
    /// against the other inside Apple's ID token.
    static func makeNonce() -> (raw: String, hashed: String) {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        let raw = String((0..<32).map { _ in chars.randomElement(using: &generator)! })
        return (raw, sha256(raw))
    }

    static func sha256(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Signs in with Apple, creating the account the first time. Apple sends
    /// the name only on that first authorisation, so it is kept then.
    func signInWithApple(_ credential: ASAuthorizationAppleIDCredential, nonce: String) async throws {
        guard let client else { throw SignInError.notConfigured }
        guard let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            throw SignInError.appleTokenMissing
        }
        let session = try await client.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce))
        if let name = credential.fullName.map(Self.displayName), !name.isEmpty,
           session.user.userMetadata["full_name"] == nil {
            _ = try? await client.update(user: UserAttributes(data: ["full_name": .string(name)]))
        }
        await didSignInInteractively()
    }

    /// Accounts made on the web with a password.
    func signIn(email: String, password: String) async throws {
        guard let client else { throw SignInError.notConfigured }
        try await client.signIn(email: Self.normalised(email), password: password)
        await didSignInInteractively()
    }

    /// Signs out on this device only; the web stays signed in.
    func signOut() {
        LegacyCredentials.purge()
        let client = client
        Task { try? await client?.signOut(scope: .local) }
        apply(nil)
    }

    /// After the server deleted the account: forget the session (the SDK's
    /// logout call fails quietly for a user who no longer exists).
    func forgetDeletedAccount() {
        signOut()
    }

    // MARK: - Private

    private func listen() {
        guard let client else { return }
        listener = Task { [weak self] in
            for await (event, session) in client.authStateChanges {
                guard let self else { return }
                if APITarget.isLocal { continue }
                switch event {
                case .initialSession:
                    await self.restoreLegacySessionIfNeeded()
                    self.apply(self.client?.currentSession)
                case .signedOut:
                    self.apply(nil)
                default:
                    self.apply(session)
                }
            }
        }
    }

    /// Publishes a session (or its absence) to the gate and the API client.
    private func apply(_ session: Session?) {
        accessToken = session?.accessToken
        account = session.map { AccountSummary(user: $0.user) }
        isSignedIn = session != nil
    }

    /// One-time move of a pre-SDK session out of UserDefaults.
    private func restoreLegacySessionIfNeeded() async {
        guard !restored, let client else { return }
        restored = true
        guard client.currentSession == nil,
              let legacy = LegacySession.take(from: defaults),
              let refresh = legacy.refreshToken else { return }
        // A refused token (revoked, or a refresh token already used) ends
        // here as signed out, the same as the old refresh failing did.
        apply(try? await client.setSession(accessToken: legacy.accessToken, refreshToken: refresh))
    }

    private func didSignInInteractively() async {
        apply(client?.currentSession)
    }

    static func normalised(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Something@something.tld, no spaces — enough to enable the button.
    static func isPlausibleEmail(_ raw: String) -> Bool {
        let email = normalised(raw)
        guard !email.contains(" "), let at = email.firstIndex(of: "@") else { return false }
        let domain = email[email.index(after: at)...]
        guard at != email.startIndex, let dot = domain.lastIndex(of: "."),
              dot != domain.startIndex, domain.distance(from: dot, to: domain.endIndex) > 2 else { return false }
        return true
    }

    static func displayName(_ name: PersonNameComponents) -> String {
        PersonNameComponentsFormatter().string(from: name).trimmingCharacters(in: .whitespaces)
    }
}

/// What Settings ▸ Account shows of the signed-in user.
struct AccountSummary: Equatable {
    let id: String
    let email: String?
    let providers: [String]

    init(id: String, email: String?, providers: [String]) {
        self.id = id
        self.email = email
        self.providers = providers
    }

    init(user: User) {
        let fromIdentities = (user.identities ?? []).map(\.provider)
        let fromMetadata = user.appMetadata["providers"]?.arrayValue?.compactMap(\.stringValue) ?? []
        self.init(id: user.id.uuidString.lowercased(),
                  email: user.email,
                  providers: Array(Set(fromIdentities + fromMetadata)).sorted())
    }

    /// Apple's "Hide My Email" relay address.
    var isPrivateRelay: Bool { email?.hasSuffix("@privaterelay.appleid.com") ?? false }

    /// "Apple", "Email", "Apple · Email" — how the account signs in.
    var methodsLabel: String {
        let names = providers.map { p -> String in
            switch p {
            case "apple": return "Apple"
            case "email": return "Email"
            default: return p.capitalized
            }
        }
        return names.isEmpty ? "Email" : names.joined(separator: " · ")
    }
}

/// The session as builds before supabase-swift stored it.
struct LegacySession: Codable, Equatable {
    static let key = "supabase_session"

    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date

    static func peek(in defaults: UserDefaults) -> LegacySession? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(LegacySession.self, from: $0) }
    }

    /// Reads and removes it, so the move happens once.
    static func take(from defaults: UserDefaults) -> LegacySession? {
        guard let data = defaults.data(forKey: key) else { return nil }
        defaults.removeObject(forKey: key)
        return try? JSONDecoder().decode(LegacySession.self, from: data)
    }
}

/// The email and password the old Face ID shortcut kept in the Keychain.
enum LegacyCredentials {
    static func purge() {
        for account in ["tc_biometric_email", "tc_biometric_password"] {
            let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrAccount: account]
            SecItemDelete(query as CFDictionary)
        }
    }
}

enum SignInError: LocalizedError {
    case notConfigured, appleTokenMissing

    var errorDescription: String? {
        switch self {
        case .notConfigured:     return "This build has no account server configured."
        case .appleTokenMissing: return "Apple didn't return a sign-in token. Try again."
        }
    }

    /// The words the sign-in screen shows for any failure; nil when the
    /// athlete cancelled and nothing should be said.
    static func message(for error: Error) -> String? {
        if let error = error as? ASAuthorizationError {
            switch error.code {
            case .canceled: return nil
            case .notInteractive: return nil
            default: return "Sign in didn't complete. Try again."
            }
        }
        if let error = error as? AuthError {
            switch error.errorCode.rawValue {
            case "invalid_credentials":         return "Wrong email or password."
            case "email_address_invalid", "validation_failed":
                return "That email address doesn't look right."
            case "signup_disabled":             return "New accounts are closed for now."
            default:                            return error.message
            }
        }
        if error is URLError { return "No connection. Check your network and try again." }
        return error.localizedDescription
    }
}
