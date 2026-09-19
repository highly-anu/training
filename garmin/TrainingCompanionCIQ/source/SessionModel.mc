using Toybox.Lang;

// Thin typed wrappers over the today-session JSON dict returned by
// GET /api/user/today-session. Field names match the backend payload
// (see api.py _encode_watch_exercise), which itself mirrors iOS WatchExercise.

class WorkoutExercise {
    hidden var d;
    function initialize(dict) { d = dict; }

    hidden function g(k) { return (d != null && d.hasKey(k)) ? d[k] : null; }

    function name()            { return g("name"); }
    function slotType()        { return g("slotType"); }
    function slotRole()        { return g("slotRole"); }
    function isMeta()          { return g("isMeta") == true; }
    function loadDescription() { return g("loadDescription"); }
    function loadNote()        { return g("loadNote"); }
    function coachingCue()     { return g("coachingCue"); }

    function sets()            { return g("sets"); }
    function reps()            { return g("reps"); }
    function weightKg()        { return g("weightKg"); }
    function targetRpe()       { return g("targetRpe"); }
    function durationMinutes() { return g("durationMinutes"); }
    function zoneTarget()      { return g("zoneTarget"); }
    function timeMinutes()     { return g("timeMinutes"); }
    function targetRounds()    { return g("targetRounds"); }
    function emomFormat()      { return g("emomFormat"); }
    function holdSeconds()     { return g("holdSeconds"); }
    function distanceKm()      { return g("distanceKm"); }
    function restSeconds()     { return g("restSeconds"); }
    function zoneLower()       { return g("prescribedZoneLower"); }
    function zoneUpper()       { return g("prescribedZoneUpper"); }

    // Identity — drives the movement-pattern icon and side alternation.
    function exerciseId()      { return g("exerciseId"); }
    function category()        { return g("category"); }
    function movementPattern() { return g("movementPattern"); }
    // false means a unilateral movement: the screen tracks left/right separately.
    function isUnilateral()    { return g("bilateral") == false; }

    // Structured interval timing. Tabata is 8 x 20s work / 10s rest; before these
    // existed the whole protocol collapsed to "5 min / 1 round".
    function workSec()         { return g("workSec"); }
    function intervalRestSec() { return g("intervalRestSec"); }

    function distanceM()       { return g("distanceM"); }
    function repsPerRound()    { return g("repsPerRound"); }
    function packLoadKg()      { return g("packLoadKg"); }
    function focus()           { return g("focus"); }
    function rir()             { return g("rir"); }
    // Set on an amrap_movement to name the amrap slot it belongs to.
    function parentSlotRole()  { return g("parentSlotRole"); }
}

class WorkoutSession {
    hidden var d;
    hidden var _exercises;

    function initialize(dict) {
        d = dict;
        _exercises = [];
        var raw = (d != null && d.hasKey("exercises")) ? d["exercises"] : [];
        for (var i = 0; i < raw.size(); i++) {
            _exercises.add(new WorkoutExercise(raw[i]));
        }
    }

    hidden function s(k) { return (d != null && d.hasKey(k)) ? d[k] : null; }

    function sessionId()       { return d["sessionId"]; }
    function modalityId()      { return d["modalityId"]; }
    function archetypeName()   { return d["archetypeName"]; }
    // Archetype identity drives the per-archetype behaviour table and the
    // category icon. Null on programs generated before the backend sent them.
    function archetypeId()       { return s("archetypeId"); }
    function archetypeCategory() { return s("archetypeCategory"); }
    function estimatedMinutes(){ return d["estimatedMinutes"]; }
    function isDeload()        { return d["isDeload"] == true; }
    function exercises()       { return _exercises; }
    function exerciseCount()   { return _exercises.size(); }

    // Parse a today-session response into an array of WorkoutSession (or []).
    static function listFromToday(today) {
        var out = [];
        // Compare with .equals(), NOT !=.
        //
        // Monkey C's == / != on String objects compares identity, not contents.
        // A status string deserialized from JSON is a different object from the
        // literal "ok", so `today["status"] != "ok"` was ALWAYS true — this
        // returned an empty list for every response, which the session list then
        // rendered as "Rest day" even when the server had sent a full day of
        // sessions. Every other string comparison in this codebase uses equals();
        // this was the one that didn't.
        if (today == null || !today.hasKey("status")) { return out; }
        var status = today["status"];
        if (!(status instanceof Lang.String) || !status.equals("ok")) { return out; }
        var arr = today.hasKey("sessions") ? today["sessions"] : [];
        for (var i = 0; i < arr.size(); i++) {
            out.add(new WorkoutSession(arr[i]));
        }
        return out;
    }
}
