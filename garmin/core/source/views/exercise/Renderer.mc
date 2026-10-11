using Toybox.Lang;

// Base class for the slot-type screens.
//
// Each renderer supplies only the content of Garmin's data page — a title line,
// one or two fields (capitals over a number) and the two lines under the rule —
// and what LAP does. ExerciseScreen draws them in the watch's own layout, so every
// slot type reads like a page of Garmin's Strength workout.
class Renderer {

    function initialize() {}

    // The line above the fields: the exercise and its load.
    function title(ctl, ex) {
        if (ex == null) { return null; }
        var w = ex.weightKg();
        return (w != null) ? (ex.name() + "  " + Steps.loadText(ex, w) + " kg") : ex.name();
    }

    // The fields, [label, value] each, or null.
    function fieldA(ctl, ex) { return null; }
    function fieldB(ctl, ex) { return null; }

    // The left field on the heart-rate page.
    function gaugeField(ctl, ex) { return fieldA(ctl, ex); }

    // The two lines under the rule: by default the next step, as Garmin shows it.
    function lines(ctl, ex) {
        var n = ctl.nextStep();
        return ["Next: " + n[0], n[1]];
    }

    // LAP (the BACK button while recording). Default: on to the next step.
    function onLap(ctl, ex) { ctl.skip(); }

    // ── shared helpers ───────────────────────────────────────────────────────────

    function elapsed(ctl) { return ctl.exerciseElapsedSec(); }

    function setField(ctl, ex) {
        var n = Steps.setCount(ex);
        var at = ctl.currentSetCount() + 1;
        if (at > n) { at = n; }
        return ["SET", at.toString() + "/" + n.toString()];
    }
}
