using Toybox.Graphics as Gfx;

// static_hold — front levers, isometric endurance, ATG rehab holds.
//
// Two states: idle (showing the prescribed hold) and running (counting down).
// The inner ring drains during the hold so the athlete can see the end coming
// without reading digits under load.
class StaticHoldRenderer extends Renderer {

    function initialize() { Renderer.initialize(); }

    function core(ctl, ex) {
        if (ctl.holdRunning()) { return Text.secs(ctl.holdRemaining()); }
        return Text.secs(ctl.holdTarget());
    }

    function sub(ctl, ex) {
        if (ctl.holdRunning()) { return "hold"; }
        var sets = (ex != null && ex.sets() != null) ? ex.sets() : 1;
        return "SET " + (ctl.currentSetCount() + 1).toString() + "/" + sets.toString();
    }

    function innerProgress(ctl, ex) {
        if (!ctl.holdRunning()) { return null; }
        var t = ctl.holdTarget();
        if (t <= 0) { return null; }
        return (t - ctl.holdRemaining()).toFloat() / t.toFloat();
    }

    function drawBase(dc, g, accent, ctl, ex) {
        var sets = (ex != null && ex.sets() != null) ? ex.sets() : 1;
        var pop = Anim.settled(Anim.SLOT_PULSE) ? 0.0 : Anim.value(Anim.SLOT_PULSE);
        Chrome.drawDots(dc, g, g.yBase, sets, ctl.currentSetCount(), accent, pop);
    }

    function hint(ctl, ex) {
        return ctl.holdRunning() ? "START stop early" : "START begin hold";
    }

    function onSelect(ctl, ex) {
        if (ctl.holdRunning()) {
            // Stopping early still records the hold — a failed hold is data.
            ctl.stopHoldEarly();
        } else {
            ctl.startHold();
            Anim.start(Anim.SLOT_RING, 0.0, 1.0, 400, Anim.EASE_OUT, null);
        }
        return true;
    }
}
