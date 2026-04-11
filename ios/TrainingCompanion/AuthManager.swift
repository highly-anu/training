import Foundation
import Combine
import LocalAuthentication

/// Thin wrapper around Supabase Swift SDK auth.
/// Uses the same project credentials as the web app — no separate account needed.
@MainActor
final class AuthManager: ObservableObject {
    @Published var isSignedIn = false
    @Published var accessToken: String? = nil

    // Loaded from ios/TrainingCompanion/Config.plist
    static let supabaseURL = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String ?? ""
    static let supabaseAnonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? ""

    private let sessionKey   = "supabase_session"
    private let keychainEmail    = "tc_biometric_email"
    private let keychainPassword = "tc_biometric_password"

    // MARK: - Biometric

    /// Whether valid credentials are stored for Face ID / Touch ID login.
    var hasBiometricCredentials: Bool {
        Keychain.read(keychainEmail) != nil
    }

    /// Whether this device supports biometric authentication.
    var canUseBiometrics: Bool {
        let ctx = LAContext()
        var err: NSError?
        return ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
    }

    /// Saves credentials to the Keychain so biometric login can retrieve them later.
    func enableBiometricLogin(email: String, password: String) {
        Keychain.save(keychainEmail,    value: email)
        Keychain.save(keychainPassword, value: password)
    }

    /// Removes stored credentials (disables biometric login).
    func disableBiometricLogin() {
        Keychain.delete(keychainEmail)
        Keychain.delete(keychainPassword)
    }

    /// Prompts Face ID / Touch ID, then signs in with the stored credentials on success.
    /// Throws `BiometricError.noCredentials` if none are stored,
    /// or the underlying `LAError` if the user cancels / fails.
    func biometricSignIn() async throws {
        guard let email    = Keychain.read(keychainEmail),
              let password = Keychain.read(keychainPassword) else {
            throw BiometricError.noCredentials
        }
        let ctx    = LAContext()
        let reason = "Sign in to Training Companion"
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                               localizedReason: reason) { success, error in
                if success { cont.resume() }
                else       { cont.resume(throwing: error ?? BiometricError.failed) }
            }
        }
        let result = try await passwordGrant(email: email, password: password)
        persistSession(result)
    }

    init() {
        // Restore persisted session; refresh if expired
        if let data = UserDefaults.standard.data(forKey: sessionKey),
           let session = try? JSONDecoder().decode(StoredSession.self, from: data) {
            if session.expiresAt > Date() {
                self.accessToken = session.accessToken
                self.isSignedIn = true
            } else if let refreshToken = session.refreshToken {
                // Token expired — attempt silent refresh on first use
                Task { await self.refreshSession(refreshToken: refreshToken) }
            }
        }
    }

    /// Silently refreshes the token if it expires within 60 seconds.
    /// Safe to call before every API request.
    func refreshIfNeeded() async {
        guard let data = UserDefaults.standard.data(forKey: sessionKey),
              let session = try? JSONDecoder().decode(StoredSession.self, from: data),
              session.expiresAt.timeIntervalSinceNow < 60,
              let refreshToken = session.refreshToken else { return }
        await refreshSession(refreshToken: refreshToken)
    }

    func signIn(email: String, password: String) async throws {
        let result = try await passwordGrant(email: email, password: password)
        persistSession(result)
    }

    func signOut() {
        accessToken = nil
        isSignedIn = false
        UserDefaults.standard.removeObject(forKey: sessionKey)
    }

    // MARK: - Private

    private func passwordGrant(email: String, password: String) async throws -> AuthResponse {
        var request = URLRequest(url: URL(string: "\(AuthManager.supabaseURL)/auth/v1/token?grant_type=password")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AuthManager.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(["email": email, "password": password])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AuthError.invalidCredentials
        }
        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }

    private func refreshSession(refreshToken: String) async {
        guard let url = URL(string: "\(AuthManager.supabaseURL)/auth/v1/token?grant_type=refresh_token") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AuthManager.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try? JSONEncoder().encode(["refresh_token": refreshToken])

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let result = try? JSONDecoder().decode(AuthResponse.self, from: data) else {
            signOut()
            return
        }
        persistSession(result)
    }

    private func persistSession(_ result: AuthResponse) {
        self.accessToken = result.access_token
        self.isSignedIn = true

        let session = StoredSession(
            accessToken: result.access_token,
            refreshToken: result.refresh_token,
            expiresAt: Date().addingTimeInterval(TimeInterval(result.expires_in))
        )
        UserDefaults.standard.set(try? JSONEncoder().encode(session), forKey: sessionKey)
    }
}

enum AuthError: LocalizedError {
    case invalidCredentials
    var errorDescription: String? { "Invalid email or password." }
}

enum BiometricError: LocalizedError {
    case noCredentials, failed
    var errorDescription: String? {
        switch self {
        case .noCredentials: return "No saved credentials for biometric login."
        case .failed:        return "Biometric authentication failed."
        }
    }
}

// MARK: - Keychain helper

private enum Keychain {
    static func save(_ key: String, value: String) {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrAccount:      key,
            kSecAttrAccessible:   kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData:        data,
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrAccount: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private struct AuthResponse: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int
}

private struct StoredSession: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date
}
