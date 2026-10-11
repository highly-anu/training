// static_hold — front levers, isometric endurance, ATG rehab holds.
//
// LAP starts the hold and, while it runs, ends it early (a short hold is still
// logged — a failed hold is data). The hold ends itself when the time is up.
class StaticHoldRenderer extends Renderer {

    function initialize() { Renderer.initialize(); }

    function fieldA(ctl, ex) {
        return ["HOLD", Text.secs(ctl.holdRunning() ? ctl.holdRemaining() : ctl.holdTarget())];
    }

    function fieldB(ctl, ex) { return setField(ctl, ex); }

    function lines(ctl, ex) {
        if (ctl.holdRunning()) { return ["Holding", "LAP ends early"]; }
        return ["Press LAP", "to start the hold"];
    }

    function onLap(ctl, ex) {
        if (ctl.holdRunning()) { ctl.stopHoldEarly(); } else { ctl.startHold(); }
    }
}
