import SwiftUI

/// Settings ▸ Account (§6.29): who is signed in and how, sign out, and
/// deleting the account — which the App Store requires of an app that can
/// create one.
struct AccountSection: View {
    @EnvironmentObject var auth: AuthManager

    @State private var showDelete = false

    var body: some View {
        Section {
            if auth.isLocalTarget {
                Text("Local API — no account. Switch back to production to sign in.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                identityRow
                Button("Sign Out", role: .destructive) { auth.signOut() }
                Button("Delete Account…", role: .destructive) { showDelete = true }
            }
        } header: {
            Text("Account")
        }
        .sheet(isPresented: $showDelete) {
            DeleteAccountSheet()
        }
    }

    private var identityRow: some View {
        HStack(spacing: 12) {
            Image(systemName: auth.account?.providers.contains("apple") == true ? "apple.logo" : "envelope")
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(auth.account?.isPrivateRelay == true ? "Hidden email (Apple)" : (auth.account?.email ?? "Signed in"))
                    .font(.subheadline)
                    .lineLimit(1).truncationMode(.middle)
                Text(auth.account?.methodsLabel ?? "")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Typing DELETE is the confirmation: the account, its programs, logs,
/// workouts and connections go, and cannot be brought back.
struct DeleteAccountSheet: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var confirmation = ""
    @State private var busy = false
    @State private var error: String?

    private var confirmed: Bool { confirmation.trimmingCharacters(in: .whitespaces) == "DELETE" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("This deletes your account and everything stored with it: programs, logs, workouts, health data and connections. It can't be undone.")
                        .font(.subheadline)
                    Text("Apple Health and your watches keep their own copies.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    TextField("Type DELETE to confirm", text: $confirmation)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } footer: {
                    if let error { Text(error).foregroundStyle(.red) }
                }
                Section {
                    Button(role: .destructive) {
                        delete()
                    } label: {
                        if busy { ProgressView() } else { Text("Delete Account") }
                    }
                    .disabled(!confirmed || busy)
                }
            }
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(busy)
                }
            }
        }
        .interactiveDismissDisabled(busy)
    }

    private func delete() {
        guard let api = appState.api else { return }
        busy = true
        error = nil
        Task {
            do {
                try await api.deleteAccount()
                dismiss()
                auth.forgetDeletedAccount()
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}
