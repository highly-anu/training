import SwiftUI

private let orderedDays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

struct MoveWorkoutSheet: View {
    let api: APIClient
    let weekIndex: Int
    let fromDay: String
    let sessionIndex: Int
    let weekSchedule: [String: [ProgramSession]]

    @EnvironmentObject var programStore: ProgramStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDay: String = ""

    private var availableDays: [String] {
        orderedDays.filter { $0 != fromDay }
    }

    var body: some View {
        NavigationStack {
            List(availableDays, id: \.self) { day in
                let sessionCount = weekSchedule[day]?.count ?? 0
                Button {
                    selectedDay = day
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(day)
                                .foregroundStyle(.primary)
                            Text(sessionCount == 0 ? "Rest day" : "\(sessionCount) session\(sessionCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedDay == day {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
            .navigationTitle("Move to Day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") {
                        programStore.moveSession(
                            weekIndex: weekIndex,
                            fromDay: fromDay,
                            toDay: selectedDay,
                            sessionIndex: sessionIndex,
                            api: api
                        )
                        dismiss()
                    }
                    .disabled(selectedDay.isEmpty)
                }
            }
        }
        .onAppear {
            selectedDay = availableDays.first ?? ""
        }
    }
}
