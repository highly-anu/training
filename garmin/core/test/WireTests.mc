using Toybox.Test;
using Toybox.Lang;

// What the watch uploads is what the server reads: sets keyed by exercise id
// with repsActual and completed, a hold's seconds as durationSeconds, a round
// step's count as rounds, a for-time clock as durationSec. Before, every set
// went up by name with "reps", and the analytics read none of them. Run with
// build.sh --test.

(:test)
function setsGoUpAsTheServerReadsThem(logger as Test.Logger) as Lang.Boolean {
    var squat = new WorkoutExercise({ "exerciseId" => "back_squat", "name" => "Back Squat", "slotType" => "sets_reps" }, {}, null);
    var plank = new WorkoutExercise({ "exerciseId" => "plank", "name" => "Plank", "slotType" => "static_hold" }, {}, null);
    var fran  = new WorkoutExercise({ "exerciseId" => "thruster", "name" => "Thruster", "slotType" => "for_time" }, {}, null);
    var cindy = new WorkoutExercise({ "exerciseId" => "pull_up", "name" => "Pull-up", "slotType" => "amrap" }, {}, null);
    var clean = new WorkoutExercise({ "name" => "KB Clean", "slotType" => "time_domain" }, {}, null);
    var list = [squat, plank, fran, cindy, clean];

    var logs = {
        "Back Squat" => [ { "reps" => 5, "weightKg" => 100, "rpe" => 8 }, { "reps" => 4, "weightKg" => 100, "rpe" => null } ],
        "Plank" => [ { "reps" => 45, "weightKg" => null, "rpe" => null } ],
        "Pull-up" => [ { "reps" => 19, "weightKg" => null, "rpe" => null } ],
        "KB Clean" => [ { "reps" => 102, "weightKg" => 24, "rpe" => null } ]
    };
    var outcomes = { "Thruster" => { "durationSec" => 298 } };
    var out = Wire.exercises(logs, outcomes, list);

    var sq = out["back_squat"]["sets"];
    Test.assertEqualMessage(sq.size(), 2, "keyed by exercise id");
    Test.assertEqual(sq[1]["setIndex"], 1);
    Test.assertEqual(sq[0]["repsActual"], 5);
    Test.assertEqual(sq[0]["weightKg"], 100);
    Test.assertEqual(sq[0]["completed"], true);
    Test.assertMessage(!sq[0].hasKey("reps"), "no bare reps");
    Test.assertEqualMessage(out["plank"]["sets"][0]["durationSeconds"], 45, "a hold's seconds");
    Test.assertMessage(!out["plank"]["sets"][0].hasKey("repsActual"), "a hold has no reps");
    Test.assertEqualMessage(out["thruster"]["durationSec"], 298, "a for-time clock");
    Test.assertEqualMessage(out["pull_up"]["rounds"], 19, "an AMRAP's rounds");
    Test.assertEqualMessage(out["pull_up"]["sets"].size(), 0, "rounds are not a set");
    Test.assertEqualMessage(out["KB Clean"]["sets"][0]["repsActual"], 102, "no id: the name stands");
    return true;
}

// Each step's window goes up keyed like its sets, in the session clock's
// seconds; a step with no time on it (skipped at once) is left out.
(:test)
function stepWindowsGoUpAsTheTimeline(logger as Test.Logger) as Lang.Boolean {
    var row = new WorkoutExercise({ "exerciseId" => "row", "name" => "Row", "slotType" => "time_domain" }, {}, null);
    var fran = new WorkoutExercise({ "exerciseId" => "thruster", "name" => "Thruster", "slotType" => "for_time" }, {}, null);
    var clean = new WorkoutExercise({ "name" => "KB Clean", "slotType" => "time_domain" }, {}, null);
    var out = Wire.timeline({ 0 => [row, 0, 900], 1 => [fran, 960, 1258], 2 => [clean, 1300, 1300] });
    Test.assertEqualMessage(out.size(), 2, "the empty step is left out");
    var byId = {};
    for (var i = 0; i < out.size(); i += 1) { byId[out[i]["exerciseId"]] = out[i]; }
    Test.assertEqual(byId["row"]["startOffset"], 0);
    Test.assertEqual(byId["row"]["endOffset"], 900);
    Test.assertEqualMessage(byId["thruster"]["startOffset"], 960, "keyed by exercise id");
    return true;
}
