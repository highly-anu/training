import SwiftUI

/// S3-A: Dispatches to the correct slot-type view for the current exercise.
struct CurrentExerciseView: View {
    @EnvironmentObject var sessionState: WorkoutSessionState

    private var exerciseIndex: Int? {
        switch sessionState.phase {
        case .active(let i, _),
             .timedWork(let i, _),
             .emomInterval(let i, _, _, _),
             .amrapRunning(let i, _, _),
             .forTimeRunning(let i, _):
            return i
        default:
            return nil
        }
    }

    var body: some View {
        if let idx = exerciseIndex,
           let ex = sessionState.session?.exercises[safe: idx] {
            Group {
                switch ex.slotType {
                case "time_domain", "skill_practice":
                    TimeDomainView(exercise: ex, exerciseIndex: idx)
                case "emom":
                    EMOMView(exercise: ex, exerciseIndex: idx)
                case "amrap":
                    AMRAPView(exercise: ex, exerciseIndex: idx)
                case "for_time":
                    ForTimeView(exercise: ex, exerciseIndex: idx)
                case "distance":
                    DistanceView(exercise: ex, exerciseIndex: idx)
                case "static_hold":
                    StaticHoldView(exercise: ex, exerciseIndex: idx)
                default:
                    SetsRepsView(exercise: ex, exerciseIndex: idx)
                }
            }
        } else {
            ProgressView()
        }
    }
}
