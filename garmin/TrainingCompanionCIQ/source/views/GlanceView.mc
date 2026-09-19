using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Application.Storage;
using Toybox.Lang;

// At-a-glance card (swiped from the watch face). Shows today's headline session
// plus a readiness dot, both from cache (the main app refreshes them; a glance has
// no reliable network). Parity with the iOS TodayWidget / SessionStartWidget.
//
// TODO: wire a complication that deep-links straight into the session.
class GlanceView extends Ui.GlanceView {

    function initialize() {
        GlanceView.initialize();
    }

    function onUpdate(dc) {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();

        var today = Storage.getValue(Config.KEY_TODAY_SESSION) as Lang.Dictionary?;
        var line1 = "Training";
        var line2 = "Open to sync";

        if (today != null && today.hasKey("status")) {
            var status = today["status"] as Lang.String;
            var sessions = today.hasKey("sessions") ? (today["sessions"] as Lang.Array) : null;
            if (status.equals("ok") && sessions != null && sessions.size() > 0) {
                var s = sessions[0] as Lang.Dictionary;
                line1 = s["archetypeName"] as Lang.String;
                line2 = s["estimatedMinutes"] + " min  |  " + s["archetypeName"];
            } else if (status.equals("ok")) {
                line1 = "Rest day";
                line2 = "";
            }
        }

        // Readiness dot (green/yellow/red) at the right edge, from cache.
        var r = Storage.getValue(Config.KEY_READINESS) as Lang.Dictionary?;
        if (r != null && r.hasKey("status")) {
            dc.setColor(readinessColor(r["status"] as Lang.String), Gfx.COLOR_TRANSPARENT);
            dc.fillCircle(dc.getWidth() - 12, 14, 6);
        }

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(4, 2, Gfx.FONT_TINY, line1, Gfx.TEXT_JUSTIFY_LEFT);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(4, 26, Gfx.FONT_XTINY, line2, Gfx.TEXT_JUSTIFY_LEFT);
    }

    hidden function readinessColor(status) {
        if (status == null) { return Gfx.COLOR_DK_GRAY; }
        if (status.equals("green"))  { return Gfx.COLOR_GREEN; }
        if (status.equals("yellow")) { return Gfx.COLOR_YELLOW; }
        if (status.equals("red"))    { return Gfx.COLOR_RED; }
        return Gfx.COLOR_DK_GRAY;
    }
}
