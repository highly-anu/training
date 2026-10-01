import SwiftUI

/// Manual resting-HR / HRV / notes entry for today. Presented from
/// Analytics ▸ Recovery; the Apple Health relay fills the sleep fields.
struct BioCheckInView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var restingHR: String = ""
    @State private var hrv: String = ""
    @State private var notes: String = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Today's Metrics") {
                    HStack {
                        Text("Resting HR")
                        Spacer()
                        TextField("bpm", text: $restingHR)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    HStack {
                        Text("HRV")
                        Spacer()
                        TextField("ms", text: $hrv)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }

                if let latest = appState.recentBioLogs.first {
                    Section("Last Night's Sleep") {
                        if let sleep = latest.sleepDurationMin, sleep > 0 {
                            let h = sleep / 60; let m = sleep % 60
                            LabeledContent("Total Sleep", value: m > 0 ? "\(h)h \(m)m" : "\(h)h")
                        }
                        if let deep = latest.deepSleepMin, deep > 0 {
                            LabeledContent("Deep", value: "\(deep / 60)h \(deep % 60)m")
                        }
                        if let rem = latest.remSleepMin, rem > 0 {
                            LabeledContent("REM", value: "\(rem / 60)h \(rem % 60)m")
                        }
                        if let spo2 = latest.spo2Avg {
                            LabeledContent("SpO₂", value: String(format: "%.1f%%", spo2))
                        }
                        if let rr = latest.respiratoryRateAvg {
                            LabeledContent("Respiratory Rate", value: String(format: "%.1f /min", rr))
                        }
                        if let source = latest.source {
                            LabeledContent("Source", value: source.replacingOccurrences(of: "_", with: " ").capitalized)
                        }
                    }
                }
            }
            .navigationTitle("Bio Check-In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .fontWeight(.semibold)
                    .disabled(restingHR.isEmpty && hrv.isEmpty)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let dayFmt = DateFormatter(); dayFmt.dateFormat = "yyyy-MM-dd"
        let today = dayFmt.string(from: Date())

        // A manual check-in is not an Apple Watch sync: the relay decides which
        // days it has already pushed by `source == "apple_watch"`, so stamping
        // that here would stop the real sleep data from ever arriving for today.
        let payload = DailyBioPayload(
            restingHR: Double(restingHR),
            hrv: Double(hrv),
            sleepDurationMin: nil,
            deepSleepMin: nil,
            remSleepMin: nil,
            lightSleepMin: nil,
            awakeMins: nil,
            sleepStart: nil,
            sleepEnd: nil,
            spo2Avg: nil,
            respiratoryRateAvg: nil,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
            source: "manual"
        )

        try? await appState.api?.pushBio(date: today, payload: payload)
        await appState.loadRecentBioLogs()
        await appState.loadReadiness()
        dismiss()
    }
}
