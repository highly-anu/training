using Toybox.Test;
using Toybox.Lang;

// Unit tests for the spec interpreter's pure parts: run with
// garmin/TrainingCompanionCIQ/build.sh --test (monkeyc --unit-test + monkeydo -t).

(:test)
function slotTypesSynthesiseTheirOldScreens(logger as Test.Logger) as Lang.Boolean {
    var cases = [
        ["sets_reps", "sets", "reps", "rpe_or_set", "complete_set"],
        ["static_hold", "hold", "hold", "set", "toggle_hold"],
        ["emom", "interval", "interval", "interval_left", "skip"],
        ["amrap", "rounds", "rounds", "cap_left", "log_round"],
        ["for_time", "for_time", "rounds_of_target", "elapsed", "log_round"],
        ["distance", "distance", "distance", "distance_target", "log_round"],
        ["time_domain", "timed", "time_left", "zone_or_time", "skip"],
        ["skill_practice", "timed", "time_left", "zone_or_time", "skip"],
        ["no_such_slot", "timed", "time_left", "zone_or_time", "skip"]
    ];
    for (var i = 0; i < cases.size(); i += 1) {
        var c = cases[i];
        var s = ScreenSpec.synthesise(c[0]);
        Test.assertEqualMessage(s["template"], c[1], c[0] + " template");
        Test.assertEqualMessage(s["a"], c[2], c[0] + " a");
        Test.assertEqualMessage(s["b"], c[3], c[0] + " b");
        Test.assertEqualMessage(s["lap"], c[4], c[0] + " lap");
    }
    return true;
}

(:test)
function aPayloadSpecIsUsedAndUnknownIdsFallBack(logger as Test.Logger) as Lang.Boolean {
    var screens = {
        "s0" => { "template" => "sets", "a" => "cumulative", "b" => "from_the_future",
                  "lap" => "teleport", "title" => ["name"],
                  "behaviours" => { "cumulative_target" => 100 } }
    };
    var s = ScreenSpec.forExercise({ "slotType" => "sets_reps", "screen" => "s0" }, screens);
    Test.assertEqual(s["a"], "cumulative");
    Test.assertEqualMessage(s["b"], "rpe_or_set", "an unknown field falls back to the template's");
    Test.assertEqualMessage(s["lap"], "complete_set", "an action the template lacks falls back");
    Test.assertEqual(s["behaviours"]["cumulative_target"], 100);

    var t = ScreenSpec.forExercise({ "slotType" => "time_domain", "screen" => "s9" }, screens);
    Test.assertEqualMessage(t["template"], "timed", "a missing key synthesises from the slot type");
    var u = ScreenSpec.forExercise({ "slotType" => "amrap", "screen" => "s0" },
                                   { "s0" => { "template" => "warp" } });
    Test.assertEqualMessage(u["template"], "rounds", "an unknown template synthesises");
    return true;
}

(:test)
function laddersClimbAndComeDown(logger as Test.Logger) as Lang.Boolean {
    Test.assertEqual(Ladder.rung(0, 20), 1);
    Test.assertEqual(Ladder.rung(19, 20), 20);
    Test.assertEqual(Ladder.rung(20, 20), 19);
    Test.assertEqual(Ladder.rung(60, 20), 1);
    Test.assertEqual(Ladder.total(3, 20), 6);
    Test.assertEqual(Ladder.total(5, 3), 1 + 2 + 3 + 2 + 1);
    return true;
}

(:test)
function vocabularyColoursAndSteps(logger as Test.Logger) as Lang.Boolean {
    Test.assertEqual(Vocab.colour("violet"), 0x8B5CF6);
    Test.assert(Vocab.colour("chartreuse") == null);
    Test.assertEqual(Vocab.weightStepByCategory()["kettlebell"], 4.0f);
    return true;
}

// LAP asks "Skip …?" only when it would cut short a step that ends by itself.
(:test)
function lapAsksBeforeCuttingAStepShort(logger as Test.Logger) as Lang.Boolean {
    var r = new SpecRenderer();
    var bike = { "exerciseId" => "bike_easy", "name" => "Easy Bike", "slotType" => "time_domain",
                 "durationMinutes" => 30 };
    var cases = [
        // [name, exercise, state, asks]
        ["a block with time left", bike, { "elapsedSec" => 600 }, true],
        ["a block whose time is up", bike, { "elapsedSec" => 1800 }, false],
        ["an open block", { "exerciseId" => "mob", "name" => "Mobility", "slotType" => "time_domain" },
         { "elapsedSec" => 600 }, false],
        ["an interval block", { "exerciseId" => "kb_swing", "name" => "Swing", "slotType" => "emom",
                                "targetRounds" => 10, "workSec" => 40, "intervalRestSec" => 20 },
         { "intervalRound" => 2, "intervalTotal" => 10 }, true],
        ["a ruck short of its distance", { "exerciseId" => "ruck", "name" => "Ruck", "slotType" => "distance",
                                           "distanceKm" => 8 }, { "distanceKm" => 3.4 }, true],
        ["a ruck past it", { "exerciseId" => "ruck", "name" => "Ruck", "slotType" => "distance",
                             "distanceKm" => 8 }, { "distanceKm" => 8.1 }, false],
        ["a set", { "exerciseId" => "kb_press", "name" => "Press", "slotType" => "sets_reps",
                    "sets" => 5, "reps" => 5 }, {}, false],
        ["a round", { "exerciseId" => "kb_swing", "name" => "Swing", "slotType" => "amrap",
                      "timeMinutes" => 10 }, { "capLeftSec" => 300 }, false]
    ];
    for (var i = 0; i < cases.size(); i += 1) {
        var c = cases[i];
        var ex = new WorkoutExercise(c[1], null, null);
        Test.assertEqualMessage(r.lapSkipsEarly(new SpecFixtureCtl(c[2], ex), ex), c[3], c[0]);
    }
    return true;
}
