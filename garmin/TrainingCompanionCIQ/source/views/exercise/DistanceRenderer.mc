using Toybox.Graphics as Gfx;

// distance — rucks, 400m repeats, 40m carries.
//
// Core is the live distance, not a clock: on a ruck the question is always "how
// far", and the app already tracks elapsedDistance for cardio sessions. Short
// sub-500m carries arrive as metres and are counted as laps instead.
class DistanceRenderer extends Renderer {

    function initialize() { Renderer.initialize(); }

    function isShort(ex) {
        return ex != null && ex.distanceM() != null && ex.distanceKm() == null;
    }

    function core(ctl, ex) {
        if (isShort(ex)) { return ctl.amrapRounds().toString(); }
        return Text.kg(ctl.distanceKm());
    }

    function sub(ctl, ex) {
        if (ex == null) { return null; }
        if (isShort(ex)) {
            var sets = (ex.sets() != null) ? ex.sets() : 1;
            return "of " + sets.toString() + " x " + ex.distanceM().toString() + "m";
        }
        var target = ex.distanceKm();
        return (target != null) ? ("of " + Text.kg(target) + " km") : "km";
    }

    function innerProgress(ctl, ex) {
        if (ex == null) { return null; }
        if (isShort(ex)) {
            var sets = (ex.sets() != null) ? ex.sets() : 1;
            if (sets <= 0) { return null; }
            var p = ctl.amrapRounds().toFloat() / sets.toFloat();
            return (p > 1.0) ? 1.0 : p;
        }
        var t = ex.distanceKm();
        if (t == null || t <= 0) { return null; }
        var q = ctl.distanceKm() / t;
        return (q > 1.0) ? 1.0 : q;
    }

    function drawBase(dc, g, accent, ctl, ex) {
        if (ex == null) { return; }
        var parts = Text.mmss(elapsed(ctl));
        if (ctl.ascentM() > 0) {
            parts += "   +" + ctl.ascentM().toNumber().toString() + "m";
        }
        dc.setColor(Theme.TEXT_DIM, Gfx.COLOR_TRANSPARENT);
        dc.drawText(g.cx, g.yBase, Text.label(), parts,
                    Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
        var pack = ex.packLoadKg();
        if (pack != null) {
            dc.setColor(Theme.dimmed(accent, 80), Gfx.COLOR_TRANSPARENT);
            dc.drawText(g.cx, g.yBase + (g.h * 50 / 1000), Text.hint(),
                        "PACK " + Text.kg(pack) + " KG",
                        Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
        }
    }

    function hint(ctl, ex) {
        return isShort(ex) ? "START count lap" : "START finish";
    }

    function onSelect(ctl, ex) {
        if (isShort(ex)) {
            ctl.logRound();
            var sets = (ex != null && ex.sets() != null) ? ex.sets() : 1;
            if (ctl.amrapRounds() >= sets) { ctl.nextExercise(); }
            return true;
        }
        ctl.nextExercise();
        return true;
    }
}
