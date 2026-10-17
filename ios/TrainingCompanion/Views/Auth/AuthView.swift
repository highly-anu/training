import SwiftUI
import AuthenticationServices

/// The signed-out screen (design-system §6.29). One screen for signing in and
/// signing up: Sign in with Apple creates the account when there is none, so
/// the phone needs no web visit to start, and sends no email. The password
/// form for accounts made on the web sits behind a link.
struct AuthView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var showPassword = false
    @State private var email = ""
    @State private var password = ""
    @State private var nonce = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                    .padding(.top, 48)

                appleButton

                if showPassword {
                    divider
                    passwordSection
                }

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                }

                modeSwitch
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .disabled(busy)
        .overlay { if busy { ProgressView().controlSize(.large) } }
        .animation(.easeOut(duration: 0.2), value: showPassword)
        .animation(.easeOut(duration: 0.2), value: error)
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text("Training Companion")
                .font(.title2).fontWeight(.bold)
            Text("Sign in or create an account")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var appleButton: some View {
        SignInWithAppleButton(.continue) { request in
            let fresh = AuthManager.makeNonce()
            nonce = fresh.raw
            request.requestedScopes = [.fullName, .email]
            request.nonce = fresh.hashed
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
                run { try await auth.signInWithApple(credential, nonce: nonce) }
            case .failure(let failure):
                error = SignInError.message(for: failure)
            }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        // The underlying ASAuthorizationAppleIDButton keeps the style it was
        // made with; a new identity per scheme rebuilds it.
        .id(colorScheme)
        .frame(height: 50)
        .clipShape(Capsule())
    }

    private var divider: some View {
        HStack(spacing: 12) {
            Rectangle().frame(height: 1).foregroundStyle(.quaternary)
            Text("or").font(.caption).foregroundStyle(.secondary)
            Rectangle().frame(height: 1).foregroundStyle(.quaternary)
        }
        .accessibilityHidden(true)
    }

    private var passwordSection: some View {
        VStack(spacing: 12) {
            emailField
                .onSubmit { focus = .password }
            SecureField("Password", text: $password)
                .textContentType(.password)
                .focused($focus, equals: .password)
                .inputField()
                .onSubmit(signInWithPassword)
            primaryButton("Sign in",
                          enabled: AuthManager.isPlausibleEmail(email) && !password.isEmpty,
                          action: signInWithPassword)
        }
    }

    private var emailField: some View {
        TextField("Email", text: $email)
            .textContentType(.username)
            .keyboardType(.emailAddress)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .submitLabel(.continue)
            .focused($focus, equals: .email)
            .inputField()
    }

    private var modeSwitch: some View {
        Button(showPassword ? "Hide password sign-in" : "Have an account from the web? Sign in with its password") {
            showPassword.toggle()
            error = nil
            password = ""
            if showPassword { focus = .email }
        }
        .font(.footnote)
    }

    private func primaryButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!enabled)
    }

    // MARK: - Actions

    private func signInWithPassword() {
        guard AuthManager.isPlausibleEmail(email), !password.isEmpty else { return }
        run { try await auth.signIn(email: email, password: password) }
    }

    /// One request at a time; the screen says what went wrong, or nothing
    /// when the athlete cancelled.
    private func run(_ work: @escaping () async throws -> Void) {
        busy = true
        error = nil
        Task {
            do {
                try await work()
                AppHaptics.success()
            } catch {
                self.error = SignInError.message(for: error)
                if self.error != nil { AppHaptics.warning() }
            }
            busy = false
        }
    }
}

private extension View {
    /// §5.1 input field: Muted fill, 10pt corners.
    func inputField() -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.quaternary.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    AuthView().environmentObject(AuthManager())
}
