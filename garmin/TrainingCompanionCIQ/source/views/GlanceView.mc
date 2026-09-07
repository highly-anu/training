using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Application.Storage;

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

        var today = Storage.getValue(Config.KEY_TODAY_SESSION);
        var line1 = "Training";
        var line2 = "Open to sync";

        if (today != null && today.hasKey("status")) {
            if (today["status"].equals("ok") && today.hasKey("sessions")
                && today["sessions"].size() > 0) {
                var s = today["sessions"][0];
                line1 = s["archetypeName"];
                line2 = s["estimatedMinutes"] + " min · " + s["modalityId"];
            } else if (today["status"].equals("ok")) {
                line1 = "Rest day";
                line2 = "";
            }
        }

        dc.drawText(4, 2, Gfx.FONT_TINY, line1, Gfx.TEXT_JUSTIFY_LEFT);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(4, 26, Gfx.FONT_XTINY, line2, Gfx.TEXT_JUSTIFY_LEFT);
    }
}
