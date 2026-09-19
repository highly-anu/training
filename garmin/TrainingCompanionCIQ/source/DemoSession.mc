using Toybox.Lang;
using Toybox.Application;

// A built-in session covering every slot type and every archetype specialization.
//
// The workout screens are otherwise only reachable through pair -> sync -> today,
// which needs an account, a backend and a generated program. This lets the nine
// screens be driven in the simulator and on-wrist before any of that exists, and
// it is the practical way to exercise the hardware-verification gate.
//
// Shapes exactly mirror api.py::_encode_watch_exercise, so what renders here is
// what renders from the real payload.
module DemoSession {

    function enabled() {
        try {
            return Application.Properties.getValue("demoMode") == true;
        } catch (e) {
            return false;
        }
    }

    function build() {
        return new WorkoutSession({
            "sessionId" => "demo-0",
            "modalityId" => "max_strength",
            "archetypeId" => "tgu_practice",
            "archetypeName" => "Turkish Get-Up Practice (Wildman)",
            "archetypeCategory" => "kettlebell",
            "estimatedMinutes" => 40,
            "isDeload" => false,
            "exercises" => [
                // sets_reps, unilateral -> side stepper
                ex("wk_kb_tgu", "Kettlebell Turkish Get-Up", "sets_reps", "main",
                   { "sets" => 5, "reps" => "5", "weightKg" => 24.0,
                     "category" => "kettlebell", "movementPattern" => "rotation",
                     "bilateral" => false, "restSeconds" => 90,
                     "loadDescription" => "5x5 @ 24 kg",
                     "loadNote" => "+2kg from last session" }),

                // sets_reps, bilateral -> set dots + inline editor
                ex("back_squat", "Back Squat", "sets_reps", "primary_compound",
                   { "sets" => 5, "reps" => "5", "weightKg" => 92.5,
                     "category" => "barbell", "movementPattern" => "squat",
                     "bilateral" => true, "restSeconds" => 180,
                     "loadDescription" => "5x5 @ 92.5 kg" }),

                // emom with real work/rest -> Tabata capsule
                ex("kb_swing", "Kettlebell Swing", "emom", "tabata_block_1",
                   { "targetRounds" => 8, "workSec" => 20, "intervalRestSec" => 10,
                     "timeMinutes" => 4, "emomFormat" => "EMOM",
                     "category" => "kettlebell", "movementPattern" => "ballistic",
                     "bilateral" => true, "loadDescription" => "8 x 20s/10s" }),

                // emom without rest -> load wave (emom_strength specialization)
                ex("power_clean", "Power Clean", "emom", "primary_emom_lift",
                   { "targetRounds" => 10, "workSec" => 60, "intervalRestSec" => 0,
                     "timeMinutes" => 10, "weightKg" => 80.0,
                     "category" => "barbell", "movementPattern" => "olympic_lift",
                     "bilateral" => true, "loadDescription" => "10 x 60s" }),

                // time_domain with a zone band
                ex("run_easy", "Easy Run (Zone 1-2)", "time_domain", "warm_up",
                   { "durationMinutes" => 10, "zoneTarget" => "Zone 1-2",
                     "prescribedZoneLower" => 1, "prescribedZoneUpper" => 2,
                     "category" => "aerobic", "movementPattern" => "aerobic_monostructural",
                     "bilateral" => true, "loadDescription" => "10 min - Zone 1-2" }),

                // amrap + folded component movements
                ex("squat_air", "Air Squat", "amrap", "amrap_main",
                   { "timeMinutes" => 20, "targetRounds" => 7, "emomFormat" => "AMRAP",
                     "category" => "bodyweight", "movementPattern" => "squat",
                     "bilateral" => true, "loadDescription" => "AMRAP 20 min" }),
                ex("pull_up", "Pull-Up", "amrap_movement", "amrap_pull",
                   { "repsPerRound" => 10, "parentSlotRole" => "amrap_main",
                     "category" => "bodyweight", "movementPattern" => "vertical_pull",
                     "bilateral" => true, "loadDescription" => "10 reps / round" }),
                ex("push_up", "Push-Up", "amrap_movement", "amrap_push",
                   { "repsPerRound" => 10, "parentSlotRole" => "amrap_main",
                     "category" => "bodyweight", "movementPattern" => "horizontal_push",
                     "bilateral" => true, "loadDescription" => "10 reps / round" }),

                // for_time
                ex("row_2k", "2000m Row", "for_time", "conditioning_finisher",
                   { "targetRounds" => 4, "timeMinutes" => 12,
                     "category" => "aerobic", "movementPattern" => "aerobic_monostructural",
                     "bilateral" => true, "loadDescription" => "4 rounds for time" }),

                // static_hold
                ex("front_lever", "Front Lever Hold", "static_hold", "isometric_endurance",
                   { "sets" => 5, "holdSeconds" => 45, "restSeconds" => 60,
                     "category" => "bodyweight", "movementPattern" => "isometric",
                     "bilateral" => true, "loadDescription" => "5x45s hold" }),

                // distance, long -> ruck with pack
                ex("ruck", "Ruck March", "distance", "ruck_main",
                   { "distanceKm" => 12.0, "packLoadKg" => 20,
                     "prescribedZoneLower" => 1, "prescribedZoneUpper" => 2,
                     "category" => "loaded_carry", "movementPattern" => "loaded_carry",
                     "bilateral" => true, "loadDescription" => "12.0 km @ 20 kg" }),

                // distance, short -> lap counter
                ex("farmer_carry", "Farmer Carry", "distance", "carry_finisher",
                   { "distanceM" => 40, "sets" => 3,
                     "category" => "loaded_carry", "movementPattern" => "farmer_carry",
                     "bilateral" => true, "loadDescription" => "3x40 m" }),

                // skill_practice
                ex("movement_flow", "Floreio Groundwork", "skill_practice", "floreio",
                   { "durationMinutes" => 5, "focus" => "movement quality over quantity",
                     "category" => "skill", "movementPattern" => "locomotion",
                     "bilateral" => true, "loadDescription" => "5 min" }),

                // meta slot -> named round timer, no exercise (BJJ shape)
                ex(null, "Free Rolling", "time_domain", "free_rolling",
                   { "durationMinutes" => 25, "isMeta" => true,
                     "prescribedZoneLower" => 3, "prescribedZoneUpper" => 4,
                     "loadDescription" => "25 min - Zone 3-4" })
            ]
        });
    }

    // Merge the shared identity fields into one exercise dict.
    function ex(id, name, slotType, slotRole, extra) {
        var d = {
            "exerciseId" => id,
            "name" => name,
            "slotType" => slotType,
            "slotRole" => slotRole,
            "isMeta" => false
        };
        var keys = extra.keys();
        for (var i = 0; i < keys.size(); i += 1) { d[keys[i]] = extra[keys[i]]; }
        return d;
    }
}
