using Toybox.Graphics as Gfx;

// time_domain and skill_practice — together the largest share of the corpus
// (~75 slots), and everything Uphill Athlete, Kelly Starrett and Ido Portal
// prescribe.
//
// Core is the elapsed clock; the inner ring drains toward the prescribed block
// duration. When the slot carries an HR zone, the sub-line shows the target band
// and the core number takes the live zone colour, so the athlete can hold the
// prescription without reading any text.
class TimeDomainRenderer extends Renderer {

    function initialize() { Renderer.initialize(); }

    function core(ctl, ex)     { return Text.mmss(elapsed(ctl)); }
    function coreWide(ctl, ex) { return true; }

    function sub(ctl, ex) {
        if (ex == null) { return null; }
        var mins = ex.durationMinutes();
        if (mins != null) { return "of " + Text.mmss(mins * 60); }
        return ex.loadDescription();
    }

    function innerProgress(ctl, ex) {
        if (ex == null) { return null; }
        var mins = ex.durationMinutes();
        if (mins == null || mins <= 0) { return null; }
        var p = elapsed(ctl).toFloat() / (mins * 60).toFloat();
        return (p > 1.0) ? 1.0 : p;
    }

    function drawBase(dc, g, accent, ctl, ex) {
        if (ex == null) { return; }

        // Distance-led sessions (rucks) foreground km and pack weight.
        if (ArchetypeBehavior.isDistanceLed(ctl.archetypeId())) {
            drawRuckLine(dc, g, accent, ctl, ex);
            return;
        }

        // A prescribed HR band is the actual instruction for zone work.
        var lo = ex.zoneLower();
        if (lo != null) {
            var hi = ex.zoneUpper();
            var label = (hi != null && hi != lo)
                ? ("ZONE " + lo.toString() + "-" + hi.toString())
                : ("ZONE " + lo.toString());
            dc.setColor(Theme.zoneColor(ctl.currentZone()), Gfx.COLOR_TRANSPARENT);
            dc.drawText(g.cx, g.yBase, Text.label(), label,
                        Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
            return;
        }

        var f = ex.focus();
        if (f != null) {
            dc.setColor(Theme.TEXT_HINT, Gfx.COLOR_TRANSPARENT);
            dc.drawText(g.cx, g.yBase, Text.hint(), f,
                        Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
        }
    }

    function drawRuckLine(dc, g, accent, ctl, ex) {
        var pack = ex.packLoadKg();
        var line = Text.kg(ctl.distanceKm()) + " km";
        if (ctl.ascentM() > 0) { line += "  +" + ctl.ascentM().toNumber().toString() + "m"; }
        dc.setColor(Theme.TEXT_DIM, Gfx.COLOR_TRANSPARENT);
        dc.drawText(g.cx, g.yBase, Text.label(), line,
                    Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
        if (pack != null) {
            dc.setColor(Theme.dimmed(accent, 80), Gfx.COLOR_TRANSPARENT);
            dc.drawText(g.cx, g.yBase + (g.h * 50 / 1000), Text.hint(),
                        "PACK " + Text.kg(pack) + " KG",
                        Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
        }
    }

    function hint(ctl, ex) { return "START next block"; }
}
