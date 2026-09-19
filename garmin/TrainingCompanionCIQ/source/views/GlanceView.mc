using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Application.Storage;
using Toybox.Lang;

// At-a-glance card (swiped from the watch face). Shows today's headline session
// plus a readiness dot, both from cache (the main app refreshes them; a glance has
// no reliable network). Parity with the iOS TodayWidget / SessionStartWidget.
//
// TODO: wire a complication that deep-links straight into the session.
(:glance)
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
                // Line 2 used to repeat the archetype name already on line 1.
                // Show the things line 1 does not: duration and move count.
                var n = (s.hasKey("exercises") && s["exercises"] != null)
                    ? (s["exercises"] as Lang.Array).size() : 0;
                line2 = s["estimatedMinutes"] + " min";
                // Narrow band: a tight separator buys room for the move count.
                if (n == 1) { line2 += " - 1 move"; }
                else if (n > 1) { line2 += " - " + n + " moves"; }
            } else if (status.equals("ok")) {
                line1 = "Rest day";
                line2 = "";
            }
        }

        // Readiness dot (green/yellow/red) at the right edge, from cache.
        var r = Storage.getValue(Config.KEY_READINESS) as Lang.Dictionary?;
        if (r != null && r.hasKey("status")) {
            dc.setColor(readinessColor(r["status"] as Lang.String), Gfx.COLOR_TRANSPARENT);
            dc.fillCircle(((dc.getWidth() * 95) / 100) - 12, 14, 6);
        }

        // Archetype names run long ("Gym Jones Accumulation Circuit (Goblet
        // Squat / Bear Crawl / Carry)") and were clipping off the right edge.
        // Step down the bitmap font ladder until the line fits; no vector fonts
        // here, they are not worth the glance's memory.
        // The glance Dc spans the FULL face, not the visible glance band, so an
        // x=4 origin drew into the hidden left region and nothing ever truncated.
        // The device profile puts the content area at x=82 w=349 on a 454 face
        // (x=75 w=320 on 416) — i.e. ~18% in, ~77% wide. Derive it proportionally
        // rather than hardcoding either resolution.
        var w = dc.getWidth();
        var pad = (w * 18) / 100;
        // 77% is the profile's nominal band width, but the band sits near the TOP
        // of a round face where the chord is materially narrower, so text still
        // ran off the right. 66% keeps both lines inside the visible arc.
        var avail = (w * 66) / 100;
        var f1 = fit(dc, line1, avail);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(pad, 2, f1, clip(dc, line1, f1, avail), Gfx.TEXT_JUSTIFY_LEFT);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(pad, 26, Gfx.FONT_XTINY,
                    clip(dc, line2, Gfx.FONT_XTINY, avail), Gfx.TEXT_JUSTIFY_LEFT);
    }
    // Largest bitmap font that fits `str` in `w` pixels.
    hidden function fit(dc, str, w) {
        if (dc.getTextWidthInPixels(str, Gfx.FONT_TINY) <= w)  { return Gfx.FONT_TINY; }
        return Gfx.FONT_XTINY;
    }

    // Truncate with an ellipsis so a long archetype name cannot overflow.
    // Stepping the font down alone was not enough: "Gym Jones Accumulation
    // Circuit (Goblet Squat / Bear Crawl / Carry)" overflows even at XTINY, and
    // drawText does no clipping of its own.
    hidden function clip(dc, str, font, w) {
        if (str == null) { return ""; }
        if (dc.getTextWidthInPixels(str, font) <= w) { return str; }
        var n = str.length();
        while (n > 1) {
            var t = str.substring(0, n) + "...";
            if (dc.getTextWidthInPixels(t, font) <= w) { return t; }
            n -= 1;
        }
        return str.substring(0, 1);
    }

    // A glance gets a 64 KB budget — a twelfth of the watch app's.
    //
    // These hex values are duplicated from ui/Theme.mc ON PURPOSE. Calling
    // Theme.readiness() here links the whole Theme module into the glance and
    // blows the budget: it crashed with "Out Of Memory Error" at 57.2/59.8 KB.
    // Keep this file free of ui/* dependencies entirely.
    hidden function readinessColor(status) {
        if (status == null) { return Gfx.COLOR_DK_GRAY; }
        if (status.equals("green"))  { return 0x10B981; }
        if (status.equals("yellow")) { return 0xEAB308; }
        if (status.equals("red"))    { return 0xEF4444; }
        return Gfx.COLOR_DK_GRAY;
    }
}
