using Toybox.Graphics as Gfx;

// for_time — count UP, because the elapsed clock is the score.
class ForTimeRenderer extends Renderer {

    function initialize() { Renderer.initialize(); }

    function core(ctl, ex)     { return Text.mmss(elapsed(ctl)); }
    function coreWide(ctl, ex) { return true; }

    function sub(ctl, ex) {
        var t = (ex != null) ? ex.targetRounds() : null;
        var r = "ROUND " + (ctl.amrapRounds() + 1).toString();
        if (t != null) { r += "/" + t.toString(); }
        return r;
    }

    function innerSegments(ctl, ex) {
        return (ex != null) ? ex.targetRounds() : null;
    }

    function innerFilled(ctl, ex) { return ctl.amrapRounds(); }

    function drawBase(dc, g, accent, ctl, ex) {
        var pop = Anim.settled(Anim.SLOT_PULSE) ? 0.0 : Anim.value(Anim.SLOT_PULSE);
        var t = (ex != null) ? ex.targetRounds() : null;
        if (t != null) {
            Chrome.drawDots(dc, g, g.yBase, t, ctl.amrapRounds(), accent, pop);
        }
    }

    function hint(ctl, ex) { return "START  +1 round"; }

    function onSelect(ctl, ex) {
        ctl.logRound();
        Anim.start(Anim.SLOT_PULSE, 1.0, 0.0, 300, Anim.EASE_OUT, null);
        var t = (ex != null) ? ex.targetRounds() : null;
        if (t != null && ctl.amrapRounds() >= t) { ctl.nextExercise(); }
        return true;
    }
}
