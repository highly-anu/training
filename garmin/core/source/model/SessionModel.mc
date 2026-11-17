using Toybox.Lang;

// Thin typed wrappers over the today-session JSON dict returned by
// GET /api/user/today-session. Field names match the backend payload
// (see api.py _encode_watch_exercise), which itself mirrors iOS WatchExercise.

class WorkoutExercise {
    hidden var d;
    hidden var o;   // the athlete's own reps / load / hold / RPE for this run, or null
    hidden var _spec; // the screen this exercise is drawn with (ScreenSpec)
    hidden var _edit; // the package's Edit Set steps, or null

    function initialize(dict, screens, edit) {
        d = dict; o = null;
        _spec = ScreenSpec.forExercise(dict, screens);
        _edit = edit;
    }

    // The Edit Set weight step: the package's step for the category, its flat
    // step, else the vocabulary's (4 kg for a kettlebell, 2.5 otherwise).
    function weightStep() {
        var cat = category();
        var by = (_edit instanceof Lang.Dictionary && _edit.hasKey("weight_step_by_category"))
            ? _edit["weight_step_by_category"] : Vocab.weightStepByCategory();
        if (cat != null && by instanceof Lang.Dictionary && by.hasKey(cat)) { return by[cat].toFloat(); }
        if (_edit instanceof Lang.Dictionary && _edit.hasKey("weight_step_kg")) { return _edit["weight_step_kg"].toFloat(); }
        return Vocab.WEIGHT_STEP_KG;
    }

    // ── the package's screen spec ────────────────────────────────────────────────

    function spec()            { return _spec; }
    // The template runs the step: sets, hold, interval, rounds, for_time,
    // distance, timed or round_timer.
    function template()        { return _spec["template"]; }
    function isTemplate(t)     { return t.equals(_spec["template"]); }
    function behaviour(k) {
        var b = _spec.hasKey("behaviours") ? _spec["behaviours"] : null;
        return (b instanceof Lang.Dictionary && b.hasKey(k)) ? b[k] : null;
    }
    // Counted per side: a unilateral movement, or a package that says so (a
    // get-up is bilateral in the library but trained one side at a time).
    function sideTracked()     { return isUnilateral() || behaviour("side_tracked") == true; }

    hidden function g(k) {
        if (o != null && o.hasKey(k)) { return o[k]; }
        return (d != null && d.hasKey(k)) ? d[k] : null;
    }

    // Set before starting, from the workout's Steps list ("set reps / weight"). The
    // server's prescription stays untouched; the session log records what was done.
    function setPlan(vals) {
        if (o == null) { o = {}; }
        if (vals.hasKey("sets"))   { o["sets"] = vals["sets"]; }
        if (vals.hasKey("reps"))   { o["reps"] = vals["reps"]; }
        if (vals.hasKey("hold"))   { o["holdSeconds"] = vals["hold"]; }
        if (vals.hasKey("weight")) { o["weightKg"] = vals["weight"]; }
        if (vals.hasKey("rpe"))    { o["targetRpe"] = vals["rpe"]; }
        if (vals.hasKey("rpm"))    { o["targetRpm"] = vals["rpm"]; }
    }

    function isEdited() { return o != null; }

    function name()            { return g("name"); }
    // "" when the payload names none, so a comparison never runs on null.
    function slotType()        { var s = g("slotType"); return (s != null) ? s : ""; }
    function slotRole()        { return g("slotRole"); }
    function isMeta()          { return g("isMeta") == true; }
    // The server's "5x3 @ 110 kg" no longer describes an edited exercise.
    function loadDescription() { return (o != null) ? null : g("loadDescription"); }
    function loadNote()        { return g("loadNote"); }
    function coachingCue()     { return g("coachingCue"); }

    function sets()            { return g("sets"); }
    function reps()            { return g("reps"); }
    function weightKg()        { return g("weightKg"); }   // one bell of a double, as the server prescribes
    // Bells held at once: 2 for double-kettlebell work (the exercise's `bells`,
    // sent by the server), else 1.
    function bells() {
        var b = g("bells");
        return (b != null) ? b : 1;
    }
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
    // Reps round by round (Fran's [21, 15, 9]), in place of repsPerRound.
    function repScheme()       { return g("repScheme"); }

    // This round's reps: the scheme's entry for the rounds logged (its last
    // once past it), else the one count.
    function repsInRound(logged) {
        var s = repScheme();
        if (s == null || !(s instanceof Lang.Array) || s.size() == 0) { return repsPerRound(); }
        var i = (logged < 0) ? 0 : logged;
        return s[(i < s.size()) ? i : (s.size() - 1)];
    }
    function packLoadKg()      { return g("packLoadKg"); }
    function focus()           { return g("focus"); }
    // What was done last time ("24kg × 10"), from the server's session logs
    // (src/last_time.py); null on a first time, a demo day or an older server.
    function last()            { return g("last"); }
    // A test's scored slot: { id, name, result, best, target }, the server's
    // words (standards.watch_standard); null on every other step.
    function standard()        { return g("standard"); }
    // What the step's screen does not record and the athlete is asked at the
    // end (["reps"] for a timed kettlebell set: its cadence), the server's
    // outcome fields; null on most steps and on an older server.
    function logs()            { return g("logs"); }
    // An interval whose even rounds are another movement (Option C: two-hand,
    // then hand-to-hand swings): that movement's name; null on every other step.
    function alternateName()   { return g("alternateName"); }
    function asksReps()        { var l = logs(); return l != null && l.indexOf("reps") >= 0; }
    function rir()             { return g("rir"); }
    // Set on an amrap_movement to name the amrap slot it belongs to.
    function parentSlotRole()  { return g("parentSlotRole"); }

    // Demo-only for now (the server encoder does not send them yet); each is
    // optional and absent means the behaviour before it existed. targetRpm also
    // takes the package's metronome_rpm behaviour.
    // Metronome pace for timed sets: the exercise's, else the package's default.
    function targetRpm() {
        var r = g("targetRpm");
        return (r != null) ? r : behaviour("metronome_rpm");
    }
    function switchAtSec()     { return g("switchAtSec"); }   // hand switch inside a work period
    function restUntilHr()     { return g("restUntilHr"); }   // rest ends when HR drops below this
}

class WorkoutSession {
    hidden var d;
    hidden var _exercises;

    function initialize(dict) {
        d = dict;
        _exercises = [];
        var raw = (d != null && d.hasKey("exercises")) ? d["exercises"] : [];
        var screens = (d != null && d.hasKey("screens")) ? d["screens"] : null;
        var w = watch();
        var edit = w.hasKey("edit") ? w["edit"] : null;
        for (var i = 0; i < raw.size(); i++) {
            _exercises.add(new WorkoutExercise(raw[i], screens, edit));
        }
    }

    hidden function s(k) { return (d != null && d.hasKey(k)) ? d[k] : null; }

    function sessionId()       { return d["sessionId"]; }
    function modalityId()      { return d["modalityId"]; }
    function archetypeName()   { return d["archetypeName"]; }
    // Archetype identity drives the per-archetype behaviour table and the
    // category icon. Null on programs generated before the backend sent them.
    function archetypeId()       { return s("archetypeId"); }
    // The package that owns the session (?spec=1), and its watch settings:
    // label, accent token, summary pages, edit steps, module.
    function packageId()         { return s("packageId"); }
    function watch() {
        var w = s("watch");
        return (w instanceof Lang.Dictionary) ? w : {};
    }
    // The package's accent colour, or null to use the modality's.
    function accent() {
        var w = watch();
        return w.hasKey("accent") ? Vocab.colour(w["accent"]) : null;
    }
    function summaryPages() {
        var w = watch();
        var sm = w.hasKey("summary") ? w["summary"] : null;
        var p = (sm instanceof Lang.Dictionary && sm.hasKey("pages")) ? sm["pages"] : null;
        return (p instanceof Lang.Array && p.size() > 0) ? p : Vocab.summaryPages();
    }

    function archetypeCategory() { return s("archetypeCategory"); }
    // The session's workout icon (data/commons/workout_icons.json): what its
    // main exercise is. Absent from older servers and from sessions with none.
    function icon()            { return s("icon"); }
    function estimatedMinutes(){ return d["estimatedMinutes"]; }
    function isDeload()        { return d["isDeload"] == true; }
    // Done today: saved on this watch, or reported done by the server (a session
    // log, or a workout from another device matched to it).
    function isCompleted()     { return d["completed"] == true || DayLog.isDone(sessionId()); }
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
