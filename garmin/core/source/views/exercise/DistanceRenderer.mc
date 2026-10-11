// distance — rucks, 400m repeats, 40m carries.
//
// Long distances show the live km against the target; short carries (metres) are
// counted as laps with LAP, and the last lap moves on.
class DistanceRenderer extends Renderer {

    function initialize() { Renderer.initialize(); }

    function title(ctl, ex) {
        var t = Renderer.title(ctl, ex);
        if (t != null && ex.packLoadKg() != null) { t += "  pack " + Text.kg(ex.packLoadKg()) + " kg"; }
        return t;
    }

    function fieldA(ctl, ex) {
        if (Steps.isShortDistance(ex)) {
            return ["LAPS", ctl.amrapRounds().toString() + "/" + Steps.setCount(ex).toString()];
        }
        return ["KM", Text.kg(ctl.distanceKm())];
    }

    function fieldB(ctl, ex) {
        if (ex == null) { return null; }
        if (Steps.isShortDistance(ex)) { return ["METRES", ex.distanceM().toString()]; }
        if (ex.distanceKm() != null) { return ["OF KM", Text.kg(ex.distanceKm())]; }
        return ["TIME", Text.mmss(elapsed(ctl))];
    }

    function onLap(ctl, ex) {
        if (Steps.isShortDistance(ex)) {
            ctl.logRound();
            if (ctl.amrapRounds() >= Steps.setCount(ex)) { ctl.skip(); }
            return;
        }
        ctl.skip();
    }
}
