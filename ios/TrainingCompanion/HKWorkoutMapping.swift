import Foundation
import HealthKit

/// How an Apple Health workout maps onto our ontology, and where it came from.
///
/// The activity-type table mirrors `APPLE_HEALTH_MAP` in `api.py`, which the
/// web app's Apple Health XML importer uses — the same workout imported either
/// way should land on the same modality.
enum HKWorkoutMapping {

    /// Who wrote this workout into Apple Health.
    enum Origin {
        /// Garmin Connect — the reason this importer exists.
        case garmin
        /// Apple's own Fitness/Watch, or our own watch app.
        case apple
        /// Someone else writing to Apple Health (Strava, Wahoo, …).
        case thirdParty
    }

    /// Bundle id prefix that identifies Garmin Connect as the writer.
    ///
    /// This only *labels* the workout — see `sourceTag(for:)`. It does not gate
    /// the import, and it must not go back to doing so: this started life as a
    /// one-entry allowlist (`com.garmin.connect.mobile`) and every workout the
    /// athlete's watch recorded was silently skipped because a guess at an
    /// undocumented vendor string did not match. A prefix, because Garmin ships
    /// more than one bundle id across regions and app generations.
    static let garminBundlePrefix = "com.garmin"

    /// Never import these, whatever else matches.
    ///
    /// Excluding our own bundle is load-bearing: the watch app writes its own
    /// HKWorkout (the one `findHKWorkout(near:)` looks up) and the phone has
    /// already relayed that session as `apple_watch_live` under a completely
    /// different id, so re-importing it would duplicate the session. Apple's
    /// own workouts are excluded for the same reason.
    ///
    /// These are prefixes, not exact ids, for a second load-bearing reason: the
    /// watch app writes under `haerdsoft.TrainingCompanion.watchkitapp`, which
    /// only a prefix test catches.
    static let excludedBundlePrefixes: [String] = [
        "com.apple",
        "haerdsoft.TrainingCompanion",
    ]

    static func origin(of workout: HKWorkout) -> Origin {
        origin(ofBundle: workout.sourceRevision.source.bundleIdentifier)
    }

    /// Same decision, from a bundle id alone — so the diagnostic log can report
    /// what the importer *would* do with a source without holding the workout.
    /// One implementation of the rule, two readers.
    static func origin(ofBundle bundle: String) -> Origin {
        if bundle.hasPrefix(garminBundlePrefix) { return .garmin }
        if excludedBundlePrefixes.contains(where: { bundle.hasPrefix($0) }) { return .apple }
        return .thirdParty
    }

    /// True when we should pull this workout into the training log.
    ///
    /// A denylist: everything except the two writers whose workouts we already
    /// hold under another id. The inversion is safe because the server dedups
    /// (`POST /api/health/workouts` → `src/workout_dedupe.py`), so importing one
    /// activity twice costs a merge rather than a duplicate — whereas importing
    /// nothing, which is what the old allowlist did, costs the workout.
    ///
    /// The trade: a third-party app writing to Health now imports too, and the
    /// athlete may have to delete a row by hand. That is the right way round for
    /// a tool whose job is to not lose the workout you did.
    static func shouldImport(_ workout: HKWorkout) -> Bool {
        origin(of: workout) != .apple
    }

    /// Which `source` the imported workout carries.
    ///
    /// Garmin-written workouts are tagged `garmin` so they read correctly in
    /// the UI and rank above an Apple Health summary in the server's dedup
    /// richness ladder.
    static func sourceTag(for workout: HKWorkout) -> String {
        switch origin(of: workout) {
        case .garmin: return "garmin"
        default:      return "apple_health"
        }
    }

    /// Mirrors APPLE_HEALTH_MAP in api.py.
    static func modalityId(for type: HKWorkoutActivityType) -> String? {
        switch type {
        case .running, .cycling, .swimming, .rowing, .elliptical,
             .swimBikeRun, .paddleSports, .crossCountrySkiing:
            return "aerobic_base"
        case .walking, .hiking:
            return "durability"
        case .highIntensityIntervalTraining:
            return "anaerobic_intervals"
        case .crossTraining, .mixedCardio:
            return "mixed_modal_conditioning"
        case .traditionalStrengthTraining:
            return "max_strength"
        case .functionalStrengthTraining, .coreTraining:
            return "strength_endurance"
        case .yoga, .flexibility, .mindAndBody, .preparationAndRecovery:
            return "mobility"
        case .martialArts, .boxing, .kickboxing, .wrestling:
            return "combat_sport"
        case .climbing:
            return "durability"
        default:
            return nil
        }
    }

    /// Human-readable activity name. Deliberately NOT the raw
    /// `HKWorkoutActivityTypeRunning` spelling the XML export uses — see the
    /// note on id matching in HealthKitManager.importableWorkouts().
    static func displayName(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .running:                      return "Running"
        case .cycling:                      return "Cycling"
        case .swimming:                     return "Swimming"
        case .walking:                      return "Walking"
        case .hiking:                       return "Hiking"
        case .rowing:                       return "Rowing"
        case .elliptical:                   return "Elliptical"
        case .highIntensityIntervalTraining: return "HIIT"
        case .crossTraining:                return "Cross Training"
        case .mixedCardio:                  return "Mixed Cardio"
        case .traditionalStrengthTraining:  return "Strength Training"
        case .functionalStrengthTraining:   return "Functional Strength"
        case .coreTraining:                 return "Core Training"
        case .yoga:                         return "Yoga"
        case .flexibility:                  return "Flexibility"
        case .mindAndBody:                  return "Mind And Body"
        case .preparationAndRecovery:       return "Preparation And Recovery"
        case .martialArts:                  return "Martial Arts"
        case .boxing:                       return "Boxing"
        case .kickboxing:                   return "Kickboxing"
        case .wrestling:                    return "Wrestling"
        case .climbing:                     return "Climbing"
        case .crossCountrySkiing:           return "Cross Country Skiing"
        case .paddleSports:                 return "Paddle Sports"
        case .swimBikeRun:                  return "Triathlon"
        default:                            return "Workout"
        }
    }
}
