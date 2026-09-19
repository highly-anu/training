using Toybox.Graphics as Gfx;

// emom — EMOM strength waves, Gym Jones row intervals, and Tabata.
//
// This is the screen the old derived-interval logic could not draw. Tabata is 8
// rounds of 20s work / 10s rest: a 30s cycle with two distinct states. The core
// number counts down the CURRENT phase, a WORK/REST capsule names it, and the
// inner ring is one segment per round so the athlete can see how many remain.
class EmomRenderer extends Renderer {

    function initialize() { Renderer.initialize(); }

    function core(ctl, ex) { return Text.secs(ctl.intervalLeft()); }

    function sub(ctl, ex) {
        var total = ctl.emomTotal();
        var r = "RD " + ctl.emomRound().toString();
        if (total > 0) { r += "/" + total.toString(); }
        return r;
    }

    function innerSegments(ctl, ex) {
        var t = ctl.emomTotal();
        return (t > 0) ? t : null;
    }

    function innerFilled(ctl, ex) { return ctl.emomRound() - 1; }

    function innerProgress(ctl, ex) {
        return (ctl.emomTotal() > 0) ? null : ctl.intervalProgress();
    }

    function drawBase(dc, g, accent, ctl, ex) {
        // WORK / REST capsule. Only shown when the protocol actually has a rest
        // period — a rest-less EMOM is a single continuous state and the capsule
        // would be noise.
        if (ctl.intervalRestSec() > 0) {
            var working = ctl.intervalWorking();
            Chrome.drawCapsule(dc, g, g.yBase, working ? "WORK" : "REST",
                               working ? accent : Theme.dimmed(accent, 45));
        }

        // The EMOM strength load wave, so the athlete can see the prescribed
        // percentage for this round instead of recalling it from the notes.
        var wave = ArchetypeBehavior.loadWave(ctl.archetypeId());
        if (wave != null) {
            var i = ctl.emomRound() - 1;
            if (i >= 0 && i < wave.size()) {
                var line = wave[i].toString() + "% 1RM";
                var w = (ex != null) ? ex.weightKg() : null;
                if (w != null) { line += "  -  " + Text.kg(w) + " kg"; }
                dc.setColor(Theme.TEXT_DIM, Gfx.COLOR_TRANSPARENT);
                dc.drawText(g.cx, g.yBase + (g.h * 55 / 1000), Text.hint(), line,
                            Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
            }
        }
    }

    function hint(ctl, ex) {
        if (ctl.intervalRestSec() > 0) { return "auto  -  START skip block"; }
        return "START next block";
    }
}
