using Toybox.Graphics as Gfx;
using Toybox.Lang;

// Base class for the nine slot-type screens.
//
// Each renderer owns only its own body: the core number, the sub-line, the base
// band and the inner ring. The outer ring, crown, HR chip, page dots and footer
// hint are drawn once by ExerciseScreen via Chrome, so the instrument language
// stays identical across every screen.
class Renderer {

    function initialize() {}

    // The one number that matters, as a string.
    function core(ctl, ex) { return ""; }

    // True when the core string is wide (mm:ss) and needs the narrower face.
    function coreWide(ctl, ex) { return false; }

    // Secondary metric under the core number, or null.
    function sub(ctl, ex) { return null; }

    // The base band: set dots, checklists, side steppers. Default: nothing.
    function drawBase(dc, g, accent, ctl, ex) {}

    // Inner ring progress in [0,1], or null for no inner ring.
    function innerProgress(ctl, ex) { return null; }

    // Segment count for the inner ring (sets, rounds, intervals). null = continuous.
    function innerSegments(ctl, ex) { return null; }
    function innerFilled(ctl, ex) { return 0; }

    // Footer text naming what SELECT does right now.
    function hint(ctl, ex) { return null; }

    // SELECT. Return true if handled.
    function onSelect(ctl, ex) {
        ctl.nextExercise();
        return true;
    }

    // UP/DOWN adjust a focused field on screens that have one.
    function editable(ctl, ex) { return false; }

    // ── shared helpers ───────────────────────────────────────────────────────────

    // Seconds elapsed in the current exercise.
    function elapsed(ctl) { return ctl.exerciseElapsedSec(); }

    // Draw the left/right stepper used by every unilateral movement.
    function drawSideStepper(dc, g, accent, ctl) {
        var y = g.yBase;
        var left = ctl.sideIsLeft();
        var on  = accent;
        var off = Theme.dimmed(accent, 30);
        var f = Text.label();
        dc.setColor(left ? on : off, Gfx.COLOR_TRANSPARENT);
        dc.drawText(g.cx - (g.padH / 2), y, f, "LEFT",
                    Gfx.TEXT_JUSTIFY_RIGHT | Gfx.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Theme.TEXT_HINT, Gfx.COLOR_TRANSPARENT);
        dc.drawText(g.cx, y, f, "|", Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
        dc.setColor(left ? off : on, Gfx.COLOR_TRANSPARENT);
        dc.drawText(g.cx + (g.padH / 2), y, f, "RIGHT",
                    Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    // The prescribed load, formatted for the sub-line.
    function loadLine(ex) {
        if (ex == null) { return null; }
        var w = ex.weightKg();
        if (w != null) { return Text.kg(w) + " kg"; }
        var rpe = ex.targetRpe();
        if (rpe != null) { return "RPE " + Text.kg(rpe); }
        return null;
    }
}
