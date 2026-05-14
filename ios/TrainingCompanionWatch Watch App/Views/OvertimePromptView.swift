import SwiftUI

struct OvertimePromptView: View {
    let exerciseName: String
    let targetSeconds: Int
    let onContinue: () -> Void
    let onFinish: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "flag.checkered")
                    .font(.title2)
                    .foregroundStyle(.orange)

                Text("Target Reached")
                    .font(.headline)

                Text(exerciseName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text(timerString(targetSeconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Button("Keep Going") {
                    onContinue()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button("Finish") {
                    onFinish()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.caption)
            }
            .padding()
        }
    }

    private func timerString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
