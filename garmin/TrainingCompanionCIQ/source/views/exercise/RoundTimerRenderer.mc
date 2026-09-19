using Toybox.Graphics as Gfx;

// A named round timer with no exercise content.
//
// bjj_class is the case: every slot is `skip_exercise`, so no exercise ever
// resolves. The block ROLE is the content — "Drilling 25:00", "Positional
// 15:00", "Rolling 25:00". Before the backend projected meta slots these
// sessions reached the watch as an empty exercise list.
class RoundTimerRenderer extends Renderer {

    function initialize() { Renderer.initialize(); }

    function core(ctl, ex) {
        if (ex == null) { return Text.mmss(elapsed(ctl)); }
        var mins = ex.durationMinutes();
        if (mins == null) { return Text.mmss(elapsed(ctl)); }
        var left = (mins * 60) - elapsed(ctl);
        return Text.mmss(left > 0 ? left : 0);
    }

    function coreWide(ctl, ex) { return true; }

    function sub(ctl, ex) {
        if (ex == null) { return null; }
        return ex.name();
    }

    function innerProgress(ctl, ex) {
        if (ex == null) { return null; }
        var mins = ex.durationMinutes();
        if (mins == null || mins <= 0) { return null; }
        var p = elapsed(ctl).toFloat() / (mins * 60).toFloat();
        return (p > 1.0) ? 1.0 : p;
    }

    function drawBase(dc, g, accent, ctl, ex) {
        // Rolls counted this block — the one thing a grappler actually logs.
        dc.setColor(Theme.TEXT_DIM, Gfx.COLOR_TRANSPARENT);
        dc.drawText(g.cx, g.yBase, Text.label(),
                    ctl.amrapRounds().toString() + " rounds",
                    Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
        if (ex != null) {
            var lo = ex.zoneLower();
            if (lo != null) {
                dc.setColor(Theme.zoneColor(ctl.currentZone()), Gfx.COLOR_TRANSPARENT);
                dc.drawText(g.cx, g.yBase + (g.h * 50 / 1000), Text.hint(),
                            "ZONE " + lo.toString()
                                + ((ex.zoneUpper() != null && ex.zoneUpper() != lo)
                                   ? ("-" + ex.zoneUpper().toString()) : ""),
                            Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
            }
        }
    }

    function hint(ctl, ex) { return "START  +1 round"; }

    function onSelect(ctl, ex) {
        ctl.logRound();
        return true;
    }
}
