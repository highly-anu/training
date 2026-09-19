using Toybox.Graphics as Gfx;

// The rest overlay.
//
// Replaces a bare "REST" label and a countdown with a draining ring, the next
// exercise named so the athlete can set up, and a recovery check: if HR is still
// well above the prescribed band when the timer expires, that is worth showing
// rather than silently starting the next set.
class RestRenderer extends Renderer {

    function initialize() { Renderer.initialize(); }

    function core(ctl, ex)     { return Text.mmss(ctl.restRemaining()); }
    function coreWide(ctl, ex) { return true; }
    function sub(ctl, ex)      { return "REST"; }

    function innerProgress(ctl, ex) {
        var total = ctl.restTotal();
        if (total == null || total <= 0) { return null; }
        var done = total - ctl.restRemaining();
        return done.toFloat() / total.toFloat();
    }

    function drawBase(dc, g, accent, ctl, ex) {
        // Name what's coming, so the rest is spent setting up rather than waiting.
        var nx = ctl.nextExerciseName();
        if (nx != null) {
            Text.drawFitted(dc, g.cx, g.yBase, g.chordWidth(g.yBase),
                            "NEXT  " + nx.toUpper(), Theme.TEXT_DIM,
                            (g.w * 46) / 1000,
                            ["RobotoCondensedBold", "RobotoMedium"]);
        }
    }

    function hint(ctl, ex) { return "START skip rest"; }

    function onSelect(ctl, ex) {
        ctl.skipRest();
        return true;
    }
}
