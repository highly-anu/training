// The session log's exercises in the server's shape — what src/health_store
// stores and the analytics primitives and src/standard_results read: keyed by
// exercise id, each set with setIndex, repsActual (a hold's seconds as
// durationSeconds), weightKg, rpe and completed; a round step's count as
// rounds; a for-time step's clock as durationSec and a distance step's km as
// distanceKm (the controller's outcomes).
//
// In memory the controller keeps sets by exercise name with "reps", which Edit
// Set and the summary read. It used to upload them that way, and every set the
// watch logged was invisible to the server: the primitives read repsActual on
// a completed set, keyed by exercise id.
module Wire {

    function exercises(setLogs, outcomes, list) {
        var out = {};
        var keys = setLogs.keys();
        for (var i = 0; i < keys.size(); i += 1) {
            var name = keys[i];
            var ex = named(list, name);
            var arr = setLogs[name];
            var entry = {};
            if (ex != null && countsRounds(ex)) {
                // logRound keeps one entry whose reps are the rounds so far.
                entry["rounds"] = (arr.size() > 0) ? arr[0]["reps"] : 0;
                entry["sets"] = [];
            } else {
                var hold = ex != null && ex.isTemplate("hold");
                var sets = [];
                for (var j = 0; j < arr.size(); j += 1) {
                    var s = arr[j];
                    var w = { "setIndex" => j, "weightKg" => s["weightKg"], "rpe" => s["rpe"], "completed" => true };
                    if (hold) { w["durationSeconds"] = s["reps"]; } else { w["repsActual"] = s["reps"]; }
                    sets.add(w);
                }
                entry["sets"] = sets;
            }
            out[key(name, ex)] = entry;
        }
        var oks = outcomes.keys();
        for (var i = 0; i < oks.size(); i += 1) {
            var name = oks[i];
            var k = key(name, named(list, name));
            var entry = out.hasKey(k) ? out[k] : { "sets" => [] };
            var o = outcomes[name];
            var fields = o.keys();
            for (var j = 0; j < fields.size(); j += 1) { entry[fields[j]] = o[fields[j]]; }
            out[k] = entry;
        }
        return out;
    }

    // Each step's window on the session clock (seconds from the start, as the
    // heart-rate samples are stamped): { exerciseId, startOffset, endOffset }.
    // The server counts heart rate in zones only inside the windows of steps
    // that prescribe zones (src/analytics/hr_plan.py). `steps` is the
    // controller's index -> [exercise, start, end].
    function timeline(steps) {
        var out = [];
        var keys = steps.keys();
        for (var i = 0; i < keys.size(); i += 1) {
            var w = steps[keys[i]];
            if (w[2] > w[1]) {
                out.add({ "exerciseId" => key(w[0].name(), w[0]), "startOffset" => w[1], "endOffset" => w[2] });
            }
        }
        return out;
    }

    // Steps whose LAP counts a round (or a lap of a carry).
    function countsRounds(ex) {
        return ex.isTemplate("rounds") || ex.isTemplate("for_time")
            || ex.isTemplate("distance") || ex.isTemplate("round_timer");
    }

    function key(name, ex) {
        return (ex != null && ex.exerciseId() != null) ? ex.exerciseId() : name;
    }

    function named(list, name) {
        for (var i = 0; i < list.size(); i += 1) {
            if (name.equals(list[i].name())) { return list[i]; }
        }
        return null;
    }
}
