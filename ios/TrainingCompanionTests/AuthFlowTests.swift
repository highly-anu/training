import XCTest
import AuthenticationServices
@testable import TrainingCompanion

/// Sign-in and sign-up on the phone: the Apple nonce, the email check,
/// the one-time move of a pre-SDK session, and the words a failure shows.
@MainActor
final class AuthFlowTests: XCTestCase {

    private func scratchDefaults() throws -> UserDefaults {
        let name = "AuthFlowTests.\(UUID().uuidString)"
        let d = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { d.removePersistentDomain(forName: name) }
        return d
    }

    // MARK: Apple nonce

    func testNonceHashIsSHA256HexOfTheRawValue() {
        // FIPS 180-2 test vector.
        XCTAssertEqual(AuthManager.sha256("abc"),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let nonce = AuthManager.makeNonce()
        XCTAssertEqual(nonce.raw.count, 32)
        XCTAssertEqual(nonce.hashed, AuthManager.sha256(nonce.raw))
        XCTAssertNotEqual(AuthManager.makeNonce().raw, nonce.raw)
    }

    // MARK: Email

    func testEmailValidationAndNormalising() {
        XCTAssertTrue(AuthManager.isPlausibleEmail("  Ath.Lete@Example.com "))
        XCTAssertEqual(AuthManager.normalised("  Ath.Lete@Example.com "), "ath.lete@example.com")
        for bad in ["", "athlete", "athlete@", "@example.com", "a b@example.com", "a@example", "a@.com", "a@example.c"] {
            XCTAssertFalse(AuthManager.isPlausibleEmail(bad), bad)
        }
    }

    // MARK: Session migration

    func testLegacySessionIsReadOnceAndRemoved() throws {
        let d = try scratchDefaults()
        XCTAssertNil(LegacySession.take(from: d))

        let stored = LegacySession(accessToken: "a", refreshToken: "r", expiresAt: Date(timeIntervalSince1970: 5))
        d.set(try JSONEncoder().encode(stored), forKey: LegacySession.key)

        XCTAssertEqual(LegacySession.peek(in: d), stored)
        XCTAssertEqual(LegacySession.peek(in: d), stored, "peek leaves it")
        XCTAssertEqual(LegacySession.take(from: d), stored)
        XCTAssertNil(d.data(forKey: LegacySession.key))
        XCTAssertNil(LegacySession.take(from: d))
    }

    func testLegacySessionDecodesWhatTheOldBuildWrote() throws {
        // The old AuthManager's StoredSession, encoded by JSONEncoder's defaults.
        let json = #"{"accessToken":"tok","refreshToken":"ref","expiresAt":782000000}"#
        let session = try JSONDecoder().decode(LegacySession.self, from: Data(json.utf8))
        XCTAssertEqual(session.refreshToken, "ref")
        XCTAssertEqual(session.expiresAt, Date(timeIntervalSinceReferenceDate: 782_000_000))
    }

    // MARK: Account summary

    func testAccountSummaryNamesTheMethodsAndTheRelay() {
        let apple = AccountSummary(id: "1", email: "x7@privaterelay.appleid.com", providers: ["apple"])
        XCTAssertTrue(apple.isPrivateRelay)
        XCTAssertEqual(apple.methodsLabel, "Apple")

        let both = AccountSummary(id: "2", email: "a@b.com", providers: ["apple", "email"])
        XCTAssertFalse(both.isPrivateRelay)
        XCTAssertEqual(both.methodsLabel, "Apple · Email")

        XCTAssertEqual(AccountSummary(id: "3", email: nil, providers: []).methodsLabel, "Email")
    }

    // MARK: Messages

    func testCancellingSaysNothing() {
        XCTAssertNil(SignInError.message(for: ASAuthorizationError(.canceled)))
        XCTAssertNotNil(SignInError.message(for: ASAuthorizationError(.failed)))
        XCTAssertEqual(SignInError.message(for: URLError(.notConnectedToInternet)),
                       "No connection. Check your network and try again.")
    }
}
