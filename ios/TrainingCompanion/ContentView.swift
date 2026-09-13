import SwiftUI

struct ContentView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var sync = SyncManager()
    @StateObject private var appState = AppState()
    @StateObject private var programStore = ProgramStore()
    @State private var selectedTab = 0

    var body: some View {
        if auth.isSignedIn {
            MainTabView(selectedTab: $selectedTab)
                .environmentObject(sync)
                .environmentObject(appState)
                .environmentObject(programStore)
                .onAppear {
                    sync.configure(auth: auth)
                    appState.configure(auth: auth)
                    // Load everything except workouts immediately (Today tab needs program/profile/logs).
                    Task { await appState.loadAllExceptWorkouts() }
                    // HealthKit + Watch sync, then reload everything including workouts once.
                    Task {
                        do {
                            try await HealthKitManager.shared.requestPermissions()
                        } catch {
                            sync.lastError = "HealthKit: \(error.localizedDescription)"
                        }
                        await sync.syncAll()
                        await appState.loadAll()
                    }
                    scheduleNextSync()
                }
                .onOpenURL { url in
                    // .fit file import
                    if url.pathExtension.lowercased() == "fit" {
                        appState.pendingFITURL = url
                        return
                    }
                    // Widget deep links — trainingcompanion://today or trainingcompanion://session?key=...
                    guard url.scheme == "trainingcompanion" else { return }
                    selectedTab = 0     // always land on the Dashboard tab
                }
                .sheet(isPresented: Binding(
                    get: { appState.pendingFITURL != nil },
                    set: { if !$0 { appState.pendingFITURL = nil } }
                )) {
                    FITImportSheet()
                        .environmentObject(appState)
                }
        } else {
            SignInView()
        }
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    @EnvironmentObject var sync: SyncManager
    @Binding var selectedTab: Int

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView()
                .tabItem { Label("Dashboard", systemImage: "house") }
                .tag(0)

            ProgramView()
                .tabItem { Label("Program", systemImage: "calendar") }
                .tag(1)

            AnalyticsView()
                .tabItem { Label("Analytics", systemImage: "chart.bar.xaxis") }
                .tag(2)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person") }
                .tag(3)

            SyncStatusView()
                .tabItem {
                    Label(
                        sync.isSyncing ? "Syncing…" : "Sync",
                        systemImage: sync.isSyncing ? "arrow.clockwise.circle.fill" : "arrow.triangle.2.circlepath"
                    )
                }
                .tag(4)
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
    @State private var showEnableBiometrics = false

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

                // Face ID button — shown when credentials are already stored
                if auth.hasBiometricCredentials && auth.canUseBiometrics {
                    Button {
                        isLoading = true
                        error = nil
                        Task {
                            do {
                                try await auth.biometricSignIn()
                            } catch let laError as LAError where laError.code == .userCancel {
                                // User cancelled — no error shown, fall back to form
                            } catch {
                                self.error = error.localizedDescription
                            }
                            isLoading = false
                        }
                    } label: {
                        Label("Sign in with Face ID", systemImage: "faceid")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading)
                    .padding(.horizontal)

                    Text("or enter your credentials below")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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
                            // Offer Face ID setup after first successful password login
                            if auth.canUseBiometrics && !auth.hasBiometricCredentials {
                                showEnableBiometrics = true
                            }
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
                .tint(auth.hasBiometricCredentials ? .secondary : .blue)
                .disabled(email.isEmpty || password.isEmpty || isLoading)
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Training Companion")
            .alert("Use Face ID?", isPresented: $showEnableBiometrics) {
                Button("Enable Face ID") { auth.enableBiometricLogin(email: email, password: password) }
                Button("Not now", role: .cancel) {}
            } message: {
                Text("Sign in faster next time without entering your password.")
            }
        }
        .onAppear {
            // Auto-trigger Face ID on app open if credentials are stored
            if auth.hasBiometricCredentials && auth.canUseBiometrics {
                Task {
                    try? await auth.biometricSignIn()
                }
            }
        }
    }
}

// Needed to check LAError in SignInView
import LocalAuthentication
