using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Application.Storage;
using Toybox.Lang;

// At-a-glance card (swiped from the watch face). Shows today's headline session
// from cache. Parity with the iOS TodayWidget / watch complication.
//
// TODO: fetch GET /api/health/readiness and draw a green/yellow/red dot; wire a
// complication that deep-links straight into the session (parity with iOS
// SessionStartWidget).
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
                line2 = s["estimatedMinutes"] + " min · " + s["modalityId"];
            } else if (status.equals("ok")) {
                line1 = "Rest day";
                line2 = "";
            }
        }

        dc.drawText(4, 2, Gfx.FONT_TINY, line1, Gfx.TEXT_JUSTIFY_LEFT);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(4, 26, Gfx.FONT_XTINY, line2, Gfx.TEXT_JUSTIFY_LEFT);
    }
}
