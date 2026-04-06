import SwiftUI

struct ContentView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var sync = SyncManager()
    @StateObject private var appState = AppState()

    var body: some View {
        if auth.isSignedIn {
            MainTabView()
                .environmentObject(sync)
                .environmentObject(appState)
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
                    guard url.pathExtension.lowercased() == "fit" else { return }
                    appState.pendingFITURL = url
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

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Dashboard", systemImage: "house") }

            ProgramView()
                .tabItem { Label("Program", systemImage: "calendar") }

            LogView()
                .tabItem { Label("Log", systemImage: "checkmark.circle") }

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person") }

            SyncStatusView()
                .tabItem {
                    Label(
                        sync.isSyncing ? "Syncing…" : "Sync",
                        systemImage: sync.isSyncing ? "arrow.clockwise.circle.fill" : "arrow.triangle.2.circlepath"
                    )
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
