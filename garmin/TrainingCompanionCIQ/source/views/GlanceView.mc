using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Application.Storage;
using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.Lang;

// The glance, in the shape of Garmin's own (Body Battery, Training Readiness): a
// small graphic at the left, a short label, and one value line under it. What it
// says follows the day:
//
//   not synced        grey ring      TRAINING             Open to sync
//   rest day          readiness      REST DAY             Tomorrow: Ruck  90 min
//   nothing done yet  readiness      TODAY  3 SESSIONS    SOF Strength A  55 min
//   some done         a segment per session, filled as each is done
//                                    TODAY  1 OF 3 DONE   Next: PT Test Prep  25 min
//   all done          full green ring with a tick
//                                    TODAY  DONE          3 sessions  1:42  17 sets
//   all done, evening the same ring  TOMORROW             Ruck  90 min
//
// Before any training the ring is readiness, which is what matters then; once a
// session is done it is the day's progress. A session is done when this watch
// saved it (DayLog) or the server says so (a log or a matched workout from
// another device). Everything comes from Storage: a glance has no reliable network.
(:glance)
class GlanceView extends Ui.GlanceView {

    const TRACK = 0x2A2A2E;
    const GOOD  = 0x10B981;

    function initialize() {
        // Qualified: this class is also named GlanceView, so the bare name is itself
        // and the constructor recursed until the glance process died, leaving the
        // watch's blank placeholder card.
        Ui.GlanceView.initialize();
    }

    function onUpdate(dc) {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();

        var label = "TRAINING";
        var value = "Open to sync";
        var ring = :none;          // :none | :readiness | :progress | :done
        var sessions = null;
        var doneFlags = null;

        var today = Storage.getValue(Config.KEY_TODAY_SESSION) as Lang.Dictionary?;
        if (today != null && today.hasKey("status") && !stale()) {
            var status = today["status"] as Lang.String;
            sessions = today.hasKey("sessions") ? (today["sessions"] as Lang.Array) : null;
            var tomorrow = today.hasKey("tomorrow") ? today["tomorrow"] : null;
            if (status.equals("ok") && sessions != null && sessions.size() > 0) {
                var log = DayLog.done();
                var n = sessions.size();
                doneFlags = new [n];
                var done = 0;
                var mins = 0;
                var sets = 0;
                var next = null;
                for (var i = 0; i < n; i += 1) {
                    var s = sessions[i] as Lang.Dictionary;
                    var id = s.hasKey("sessionId") ? s["sessionId"] : null;
                    var d = (s.hasKey("completed") && s["completed"] == true)
                            || (id != null && log.hasKey(id));
                    doneFlags[i] = d;
                    if (d) {
                        done += 1;
                        if (id != null && log.hasKey(id)) {
                            mins += log[id][0];
                            sets += log[id][1];
                        } else {
                            mins += s["estimatedMinutes"];
                        }
                    } else if (next == null) {
                        next = s;
                    }
                }
                if (done == 0) {
                    ring = :readiness;
                    label = "TODAY" + ((n > 1) ? ("  " + n + " SESSIONS") : "");
                    value = describe(next);
                } else if (done < n) {
                    ring = :progress;
                    label = "TODAY  " + done + " OF " + n + " DONE";
                    value = "Next: " + describe(next);
                } else if (System.getClockTime().hour >= Config.GLANCE_EVENING_HOUR
                           && tomorrow != null) {
                    ring = :done;
                    label = "TOMORROW";
                    value = describeDay(tomorrow);
                } else {
                    ring = :done;
                    label = "TODAY  DONE";
                    value = n + ((n == 1) ? " session  " : " sessions  ") + hm(mins)
                          + ((sets > 0) ? ("  " + sets + " sets") : "");
                }
            } else if (status.equals("ok")) {
                ring = :readiness;
                label = "REST DAY";
                value = (tomorrow != null) ? ("Tomorrow: " + describeDay(tomorrow)) : "Recover well";
            }
        }

        // The graphic, at the left of the band. Plain vector draws, no bitmaps:
        // the glance budget is 64 KB.
        var w = dc.getWidth();
        var pad = (w * 18) / 100;
        var gx = pad + 16;
        // The glance Dc may report the whole face; the card is ~138 px tall (measured
        // from a photo), so centre within that and never below it.
        var gh = dc.getHeight();
        if (gh > 138) { gh = 138; }
        var gy = gh / 2;
        var gr = (gh * 22) / 100;
        if (gr > 16) { gr = 16; }
        if (gr < 8)  { gr = 8; }
        try {
            dc.setPenWidth(4);
            if (ring == :progress) {
                drawProgress(dc, gx, gy, gr, sessions, doneFlags);
            } else if (ring == :done) {
                drawDone(dc, gx, gy, gr);
            } else {
                drawReadiness(dc, gx, gy, gr, ring == :readiness, sessions);
            }
        } catch (e) {
            value = "gfx: " + e.getErrorMessage();
        }

        // Label small over the value, Garmin's glance order. The glance Dc spans the
        // FULL face; the device profile puts the content area ~18% in and ~77% wide,
        // and the band sits near the top of a round face where the chord is
        // narrower, so the text is held inside that.
        var avail = ((w * 77) / 100) - 40;
        var fl = Gfx.FONT_XTINY;
        var fv = fit(dc, value, avail);
        var hl = dc.getFontHeight(fl);
        var hv = dc.getFontHeight(fv);
        var ty = (gh - (hl + hv)) / 2;
        if (ty < 0) { ty = 0; }
        var tx = pad + 40;
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(tx, ty, fl, clip(dc, label, fl, avail), Gfx.TEXT_JUSTIFY_LEFT);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(tx, ty + hl, fv, clip(dc, value, fv, avail), Gfx.TEXT_JUSTIFY_LEFT);
    }

    // The cache is another day's (the server stamps it with its UTC date).
    hidden function stale() {
        var d = Storage.getValue(Config.KEY_TODAY_DATE);
        if (d == null) { return false; }
        var i = Gregorian.utcInfo(Time.now(), Time.FORMAT_SHORT);
        var t = i.year.format("%04d") + "-" + i.month.format("%02d") + "-" + i.day.format("%02d");
        return !t.equals(d);
    }

    hidden function describe(s) {
        if (s == null) { return ""; }
        return s["archetypeName"] + "  " + s["estimatedMinutes"] + " min";
    }

    hidden function describeDay(t) {
        if (t == null) { return ""; }
        var n = t.hasKey("sessionCount") ? t["sessionCount"] : 0;
        if (n == 0) { return "Rest day"; }
        return t["archetypeName"] + "  " + t["estimatedMinutes"] + " min"
             + ((n > 1) ? ("  +" + (n - 1)) : "");
    }

    // "1:42" for minutes, "45 min" under an hour.
    hidden function hm(m) {
        if (m < 60) { return m + " min"; }
        return (m / 60) + ":" + (m % 60).format("%02d");
    }

    // Readiness: a ring swept by the score around a dot in the next session's colour.
    hidden function drawReadiness(dc, gx, gy, gr, show, sessions) {
        var rc = Gfx.COLOR_DK_GRAY;
        var sweep = 1.0;
        var r = show ? (Storage.getValue(Config.KEY_READINESS) as Lang.Dictionary?) : null;
        if (r != null && r.hasKey("status")) {
            rc = readinessColor(r["status"] as Lang.String);
            if (r.hasKey("score") && r["score"] != null) { sweep = r["score"].toFloat() / 100.0; }
        }
        dc.setColor(TRACK, Gfx.COLOR_TRANSPARENT);
        dc.drawCircle(gx, gy, gr);
        dc.setColor(rc, Gfx.COLOR_TRANSPARENT);
        if (sweep >= 0.99) {
            dc.drawCircle(gx, gy, gr);
        } else if (sweep > 0.02) {
            dc.drawArc(gx, gy, gr, Gfx.ARC_CLOCKWISE, 90, 90 - (360.0 * sweep).toNumber());
        }
        var m = null;
        if (sessions != null && sessions.size() > 0) {
            var s0 = sessions[0] as Lang.Dictionary;
            m = s0.hasKey("modalityId") ? s0["modalityId"] : null;
        }
        dc.setColor(modalityColor(m), Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(gx, gy, gr / 2);
    }

    // One arc per session, clockwise from 12, in its modality colour: bright when
    // done, dim when still to do.
    hidden function drawProgress(dc, gx, gy, gr, sessions, flags) {
        var n = sessions.size();
        var seg = 360 / n;
        var gap = (n > 1) ? 8 : 0;
        for (var i = 0; i < n; i += 1) {
            var s = sessions[i] as Lang.Dictionary;
            var c = modalityColor(s.hasKey("modalityId") ? s["modalityId"] : null);
            dc.setColor(flags[i] ? c : dim(c), Gfx.COLOR_TRANSPARENT);
            var a0 = 90 - (i * seg) - (gap / 2);
            var a1 = 90 - ((i + 1) * seg) + (gap / 2);
            if (n == 1) { dc.drawCircle(gx, gy, gr); } else { dc.drawArc(gx, gy, gr, Gfx.ARC_CLOCKWISE, a0, a1); }
        }
    }

    // A full green ring with a tick.
    hidden function drawDone(dc, gx, gy, gr) {
        dc.setColor(GOOD, Gfx.COLOR_TRANSPARENT);
        dc.drawCircle(gx, gy, gr);
        dc.setPenWidth(3);
        var u = gr / 2;
        dc.drawLine(gx - u, gy, gx - (u / 4), gy + (u * 2 / 3));
        dc.drawLine(gx - (u / 4), gy + (u * 2 / 3), gx + u, gy - (u * 2 / 3));
    }

    hidden function dim(c) {
        var r = ((c >> 16) & 0xFF) * 30 / 100;
        var g = ((c >> 8) & 0xFF) * 30 / 100;
        var b = (c & 0xFF) * 30 / 100;
        return (r << 16) | (g << 8) | b;
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
    hidden function modalityColor(m) {
        if (m == null) { return Gfx.COLOR_LT_GRAY; }
        if (m.equals("max_strength"))             { return 0xEF4444; }
        if (m.equals("strength_endurance"))       { return 0xF97316; }
        if (m.equals("relative_strength"))        { return 0xF43F5E; }
        if (m.equals("aerobic_base"))             { return 0x0EA5E9; }
        if (m.equals("anaerobic_intervals"))      { return 0x06B6D4; }
        if (m.equals("mixed_modal_conditioning")) { return 0x8B5CF6; }
        if (m.equals("power"))                    { return 0xEAB308; }
        if (m.equals("mobility"))                 { return 0x10B981; }
        if (m.equals("movement_skill"))           { return 0x14B8A6; }
        if (m.equals("durability"))               { return 0xF59E0B; }
        if (m.equals("combat_sport"))             { return 0xEC4899; }
        if (m.equals("rehab"))                    { return 0x84CC16; }
        return Gfx.COLOR_LT_GRAY;
    }

    hidden function readinessColor(status) {
        if (status == null) { return Gfx.COLOR_DK_GRAY; }
        if (status.equals("green"))  { return 0x10B981; }
        if (status.equals("yellow")) { return 0xEAB308; }
        if (status.equals("red"))    { return 0xEF4444; }
        return Gfx.COLOR_DK_GRAY;
    }
}
