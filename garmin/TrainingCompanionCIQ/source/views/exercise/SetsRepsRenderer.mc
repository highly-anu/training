// sets_reps — the most common slot in the corpus.
//
// Garmin's Strength page: REPS and SET side by side, "Next: Rest 3:00" under the
// rule. LAP ends the set; the reps and load logged are the working values, which
// Edit Set (hold UP) changes after the fact.
class SetsRepsRenderer extends Renderer {

    function initialize() { Renderer.initialize(); }

    function title(ctl, ex) {
        if (ex == null) { return null; }
        var t = ex.name();
        if (ArchetypeBehavior.sideTracked(ctl.archetypeId(), ex)) {
            t += ctl.sideIsLeft() ? "  Left" : "  Right";
        }
        var w = ctl.editWeight();
        if (w != null) { t += "  " + Steps.loadText(ex, w) + " kg"; }
        return t;
    }

    function fieldA(ctl, ex) {
        // Cumulative protocols (Gym Jones' 100 get-ups) count toward a total.
        var cum = ArchetypeBehavior.cumulativeTarget(ctl.archetypeId());
        if (cum != null) {
            var per = (ex != null && ex.reps() != null) ? ctl.editReps() : 1;
            return ["TOTAL", (ctl.currentSetCount() * per).toString() + "/" + cum.toString()];
        }
        return ["REPS", ctl.editReps().toString()];
    }

    function fieldB(ctl, ex) {
        if (ex != null && ex.targetRpe() != null && ctl.editWeight() == null) {
            return ["RPE", Text.kg(ctl.editRpe())];
        }
        return setField(ctl, ex);
    }

    function gaugeField(ctl, ex) { return setField(ctl, ex); }

    function onLap(ctl, ex) { ctl.completeSet(); }
}
