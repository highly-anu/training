import SwiftUI

struct ContentView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var sync = SyncManager()

    var body: some View {
        if auth.isSignedIn {
            SyncView(sync: sync)
                .onAppear {
                    sync.configure(auth: auth)
                    // Auto-sync on launch
                    Task { await sync.syncAll() }
                    scheduleNextSync()
                }
        } else {
            SignInView()
        }
    }
}

// MARK: - Sync screen

struct SyncView: View {
    @EnvironmentObject var auth: AuthManager
    @ObservedObject var sync: SyncManager

    private let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                Image(systemName: "heart.text.square")
                    .font(.system(size: 56))
                    .foregroundStyle(.red.gradient)

                VStack(spacing: 6) {
                    Text("Training Companion")
                        .font(.title2.bold())
                    Text("Syncs Apple Watch health data\nto your training dashboard.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                // Status
                VStack(spacing: 8) {
                    if sync.isSyncing {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.8)
                            Text("Syncing…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else if let err = sync.lastError {
                        Label(err, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    } else if let last = sync.lastSyncDate {
                        Label("Last synced \(dayFmt.string(from: last))", systemImage: "checkmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.green)
                    } else {
                        Text("Not yet synced")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 24)

                Button {
                    Task { await sync.syncAll() }
                } label: {
                    Label("Sync Now", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(sync.isSyncing)
                .padding(.horizontal)

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign Out", role: .destructive) {
                        auth.signOut()
                    }
                    .font(.footnote)
                }
            }
        }
    }
}

// MARK: - Sign-in screen

struct SignInView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var error: String? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "figure.run.circle")
                    .font(.system(size: 56))
                    .foregroundStyle(.blue.gradient)

                Text("Sign in with your training app account")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding()
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal)

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .padding()
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal)
                }

                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button {
                    isLoading = true
                    error = nil
                    Task {
                        do {
                            try await auth.signIn(email: email, password: password)
                        } catch {
                            self.error = error.localizedDescription
                        }
                        isLoading = false
                    }
                } label: {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Sign In")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(email.isEmpty || password.isEmpty || isLoading)
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Training Companion")
        }
    }
}
