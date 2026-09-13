import SwiftUI

/// Pair a Garmin (or other) watch companion to this account.
///
/// The watch shows a 6-character code from its Pairing screen; the user enters it
/// here (already signed in) to call POST /devices/claim, binding the watch's device
/// token to their user_id. Thereafter the watch authenticates on its own.
struct DevicesView: View {
    @EnvironmentObject var appState: AppState

    @State private var code: String = ""
    @State private var isClaiming = false
    @State private var claimError: String?
    @State private var justPaired = false

    @State private var devices: [PairedDevice] = []
    @State private var isLoading = false

    private var normalizedCode: String {
        code.trimmingCharacters(in: .whitespaces).uppercased()
    }
    private var canSubmit: Bool { normalizedCode.count == 6 && !isClaiming }

    var body: some View {
        List {
            Section {
                TextField("6-character code", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(.title2, design: .monospaced))
                    .onChange(of: code) { _, newValue in
                        // Keep it tidy: uppercase, strip spaces, cap at 6.
                        let cleaned = newValue.uppercased().filter { !$0.isWhitespace }
                        code = String(cleaned.prefix(6))
                    }

                Button {
                    Task { await claim() }
                } label: {
                    HStack {
                        if isClaiming { ProgressView().padding(.trailing, 4) }
                        Text(isClaiming ? "Pairing…" : "Pair Watch")
                    }
                }
                .disabled(!canSubmit)

                if let claimError {
                    Text(claimError).foregroundStyle(.red).font(.footnote)
                }
                if justPaired {
                    Label("Paired! Your watch will sync today's session shortly.",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.footnote)
                }
            } header: {
                Text("Pair a watch")
            } footer: {
                Text("On your Garmin, open the Training app. It shows a 6-character code — enter it here.")
            }

            Section("Paired devices") {
                if isLoading {
                    ProgressView()
                } else if devices.isEmpty {
                    Text("No devices paired yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(devices) { d in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.deviceName ?? "Watch").font(.body)
                            if let last = d.lastUsedAt {
                                Text("Last used \(shortDate(last))")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else if let claimed = d.claimedAt {
                                Text("Paired \(shortDate(claimed))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Devices")
        .task { await load() }
    }

    private func claim() async {
        guard let api = appState.api else { return }
        isClaiming = true; claimError = nil; justPaired = false
        do {
            try await api.claimDevice(code: normalizedCode)
            justPaired = true
            code = ""
            await load()
        } catch {
            claimError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isClaiming = false
    }

    private func load() async {
        guard let api = appState.api else { return }
        isLoading = true
        devices = (try? await api.fetchDevices()) ?? []
        isLoading = false
    }

    /// Trims an ISO/DB timestamp to just the date for display.
    private func shortDate(_ s: String) -> String {
        return String(s.prefix(10))
    }
}
