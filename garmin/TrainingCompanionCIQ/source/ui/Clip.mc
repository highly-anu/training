using Toybox.Graphics as Gfx;
using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;

// Truncate to a pixel width with an ellipsis; drawText does no clipping of its own.
module Clip {
    // A screen that throws shows what threw, instead of taking the app down. The
    // demo is for finding exactly this on a real watch, where there is no console.
    function drawError(dc, where, e) {
        var msg = where + ": " + ((e != null) ? e.getErrorMessage() : "?");
        System.println("CIQ_SCREEN_ERROR " + msg);
        if (e != null) { e.printStackTrace(); }
        drawMessage(dc, msg);
    }

    function drawMessage(dc, msg) {
        dc.setColor(Theme.TEXT, Theme.BG);
        dc.clear();
        dc.setColor(Theme.READY_RED, Gfx.COLOR_TRANSPARENT);
        var w = dc.getWidth();
        var y = (dc.getHeight() * 22) / 100;
        var line = "";
        for (var i = 0; i < msg.length(); i += 1) {
            line += msg.substring(i, i + 1);
            if (dc.getTextWidthInPixels(line, Gfx.FONT_XTINY) > (w * 60) / 100) {
                dc.drawText(w / 2, y, Gfx.FONT_XTINY, line, Gfx.TEXT_JUSTIFY_CENTER);
                y += dc.getFontHeight(Gfx.FONT_XTINY);
                line = "";
                if (y > (dc.getHeight() * 78) / 100) { return; }
            }
        }
        dc.drawText(w / 2, y, Gfx.FONT_XTINY, line, Gfx.TEXT_JUSTIFY_CENTER);
    }

    function fit(dc, str, font, w) {
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

    // "THU 10" for a day `offset` days from today, "TODAY" for 0.
    function dayLabel(offset) {
        if (offset == 0) { return "TODAY"; }
        var names = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
        var info = Gregorian.info(Time.now().add(new Time.Duration(offset * 86400)),
                                  Time.FORMAT_SHORT);
        return names[info.day_of_week - 1] + " " + info.day.toString();
    }

    // Accent for a day: its first session's modality, or the recovery colour.
    function dayAccent(day) {
        var ss = day["sessions"];
        return (ss.size() > 0) ? Theme.accent(ss[0].modalityId()) : Theme.TEXT_HINT;
    }

    function dayMinutes(day) {
        var ss = day["sessions"];
        var m = 0;
        for (var i = 0; i < ss.size(); i += 1) { m += ss[i].estimatedMinutes(); }
        return m;
    }
}
