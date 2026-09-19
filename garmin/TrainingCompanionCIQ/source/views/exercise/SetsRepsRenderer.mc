using Toybox.Graphics as Gfx;

// sets_reps — the most common slot in the corpus (~45 slots).
//
// Core number is the rep count, editable in place: UP/DOWN adjust the focused
// field so a heavy set can be logged without pushing a separate logger view.
// The inner ring is segmented, one arc per prescribed set.
class SetsRepsRenderer extends Renderer {

    function initialize() { Renderer.initialize(); }

    function core(ctl, ex) { return ctl.editReps().toString(); }

    function sub(ctl, ex) {
        var f = ctl.editFocusField();
        if (f.equals("weight") || ctl.editHasField("weight")) {
            var w = ctl.editWeight();
            if (w != null) { return Text.kg(w) + " kg"; }
        }
        var r = ctl.editRpe();
        if (r != null) { return "RPE " + Text.kg(r); }
        return "reps";
    }

    function innerSegments(ctl, ex) {
        return (ex != null && ex.sets() != null) ? ex.sets() : 1;
    }

    function innerFilled(ctl, ex) { return ctl.currentSetCount(); }

    function drawBase(dc, g, accent, ctl, ex) {
        var aid = ctl.archetypeId();

        // Cumulative protocols (Gym Jones' 100 get-ups) track a running total
        // rather than sets: that total IS what the athlete is counting.
        var cum = ArchetypeBehavior.cumulativeTarget(aid);
        if (cum != null) {
            var done = ctl.currentSetCount() * ((ex != null && ex.reps() != null)
                                                ? ex.reps().toNumber() : 1);
            dc.setColor(Theme.TEXT_DIM, Gfx.COLOR_TRANSPARENT);
            dc.drawText(g.cx, g.yBase, Text.label(),
                        done.toString() + " / " + cum.toString(),
                        Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
            return;
        }

        if (ArchetypeBehavior.sideTracked(aid, ex)) {
            drawSideStepper(dc, g, accent, ctl);
            return;
        }

        var sets = (ex != null && ex.sets() != null) ? ex.sets() : 1;
        var pop = Anim.settled(Anim.SLOT_PULSE) ? 0.0 : Anim.value(Anim.SLOT_PULSE);
        Chrome.drawDots(dc, g, g.yBase, sets, ctl.currentSetCount(), accent, pop);
    }

    function hint(ctl, ex) {
        var aid = ctl.archetypeId();
        if (aid != null && aid.equals("tgu_practice")) {
            return ArchetypeBehavior.tguPhases();
        }
        return (ctl.editFieldCount() > 1) ? "UP/DOWN adjust  -  START log"
                                          : "START log set";
    }

    function editable(ctl, ex) { return true; }

    function onSelect(ctl, ex) {
        ctl.logCurrentSet();
        Anim.start(Anim.SLOT_PULSE, 1.0, 0.0, 350, Anim.EASE_OUT, null);
        var target = (ex != null && ex.sets() != null) ? ex.sets() : 1;
        if (ctl.currentSetCount() >= target) {
            ctl.nextExercise();
        } else {
            ctl.startRest();
        }
        return true;
    }
}
