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

    function sessionId()       { return d["sessionId"]; }
    function modalityId()      { return d["modalityId"]; }
    function archetypeName()   { return d["archetypeName"]; }
    function estimatedMinutes(){ return d["estimatedMinutes"]; }
    function isDeload()        { return d["isDeload"] == true; }
    function exercises()       { return _exercises; }
    function exerciseCount()   { return _exercises.size(); }

    // Parse a today-session response into an array of WorkoutSession (or []).
    static function listFromToday(today) {
        var out = [];
        if (today == null || !today.hasKey("status") || today["status"] != "ok") {
            return out;
        }
        var arr = today.hasKey("sessions") ? today["sessions"] : [];
        for (var i = 0; i < arr.size(); i++) {
            out.add(new WorkoutSession(arr[i]));
        }
        return out;
    }
}
