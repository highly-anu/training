import SwiftUI

struct ContentView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var sync = SyncManager()

    var body: some View {
        if auth.isSignedIn {
            SyncView(sync: sync)
                .onAppear {
                    sync.configure(auth: auth)
                    Task {
                        do {
                            try await HealthKitManager.shared.requestPermissions()
                        } catch {
                            sync.lastError = "HealthKit: \(error.localizedDescription)"
                            return
                        }
                        await sync.syncAll()
                    }
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
    @ObservedObject private var logger = AppLogger.shared

    private let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ── Top controls ──
                VStack(spacing: 16) {
                    Image(systemName: "heart.text.square")
                        .font(.system(size: 44))
                        .foregroundStyle(.red.gradient)
                        .padding(.top, 20)

                    // Status
                    Group {
                        if sync.isSyncing {
                            HStack(spacing: 8) {
                                ProgressView().scaleEffect(0.8)
                                Text("Syncing…").font(.footnote).foregroundStyle(.secondary)
                            }
                        } else if let err = sync.lastError {
                            Label(err, systemImage: "exclamationmark.triangle")
                                .font(.footnote).foregroundStyle(.orange)
                        } else if let last = sync.lastSyncDate {
                            Label("Last synced \(dayFmt.string(from: last))", systemImage: "checkmark.circle")
                                .font(.footnote).foregroundStyle(.green)
                        } else {
                            Text("Not yet synced").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 20)

                    Button {
                        Task { await sync.syncAll() }
                    } label: {
                        Label("Sync Now", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(sync.isSyncing)
                    .padding(.horizontal)
                }
                .padding(.bottom, 12)

                Divider()

                // ── Log panel ──
                if logger.entries.isEmpty {
                    Spacer()
                    Text("No log entries yet.\nRun a sync or finish a watch workout.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(logger.entries) { entry in
                                    HStack(alignment: .top, spacing: 6) {
                                        Text(timeFmt.string(from: entry.date))
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 62, alignment: .leading)
                                        Text(entry.message)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(.primary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .id(entry.id)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 1)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .onChange(of: logger.entries.count) { _, _ in
                            if let last = logger.entries.last {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Training Companion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign Out", role: .destructive) { auth.signOut() }
                        .font(.footnote)
                }
                ToolbarItem(placement: .topBarLeading) {
                    if !logger.entries.isEmpty {
                        Button("Clear") { logger.entries.removeAll() }
                            .font(.footnote)
                    }
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
