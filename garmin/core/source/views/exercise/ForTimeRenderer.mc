// for_time — the elapsed clock is the score. LAP counts a round; the last round
// moves on.
class ForTimeRenderer extends Renderer {

    function initialize() { Renderer.initialize(); }

    function fieldA(ctl, ex) {
        var t = (ex != null) ? ex.targetRounds() : null;
        return ["ROUNDS", ctl.amrapRounds().toString() + ((t != null) ? ("/" + t.toString()) : "")];
    }

    function fieldB(ctl, ex) { return ["TIME", Text.mmss(elapsed(ctl))]; }

    function onLap(ctl, ex) {
        ctl.logRound();
        var t = (ex != null) ? ex.targetRounds() : null;
        if (t != null && ctl.amrapRounds() >= t) { ctl.skip(); }
    }
}
