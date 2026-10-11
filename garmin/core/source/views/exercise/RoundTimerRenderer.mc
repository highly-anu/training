// A named round timer with no exercise content (bjj_class): the block role is
// the content — "Drilling 25:00", "Rolling 25:00". LAP counts a round; once the
// block's time is up, LAP moves on.
class RoundTimerRenderer extends Renderer {

    function initialize() { Renderer.initialize(); }

    function title(ctl, ex) { return (ex != null) ? ex.name() : null; }

    hidden function left(ctl, ex) {
        if (ex == null || ex.durationMinutes() == null) { return null; }
        var l = (ex.durationMinutes() * 60) - elapsed(ctl);
        return (l > 0) ? l : 0;
    }

    function fieldA(ctl, ex) {
        var l = left(ctl, ex);
        return (l != null) ? ["LEFT", Text.mmss(l)] : ["TIME", Text.mmss(elapsed(ctl))];
    }

    function fieldB(ctl, ex) { return ["ROUNDS", ctl.amrapRounds().toString()]; }

    function onLap(ctl, ex) {
        var l = left(ctl, ex);
        if (l != null && l == 0) { ctl.skip(); return; }
        ctl.logRound();
    }
}
