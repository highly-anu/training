using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Application;
using Toybox.Application.Storage;
using Toybox.System;
using Toybox.Lang;

// The glance, in one of three styles the athlete picks (Settings ▸ Glance on
// the watch, Glance style in Garmin Connect Mobile; `glanceStyle`):
//
//   0  Next up   Garmin's own glance layout: left-aligned text in the glance
//                font, the day's state over what is next and how long, beside
//                a bar in that session's colour. Two lines when the glance is
//                too short for three. The default since 1.12.
//   1  Day bar   a title, a bar with a segment per session (its modality's
//                colour, bright once done; on a rest day the week's sessions)
//                and one line under it.
//   2  Ring      the glance until 1.12: a small ring at the left (readiness
//                before any training, then the day's sessions, then a tick)
//                beside a label and one line.
//
// What each says is GlanceDay's; this file only draws it. Everything comes
// from Storage: a glance has no reliable network. A Connect IQ app has one
// glance, so "styles" is a setting, not several glances.
(:glance)
class GlanceView extends Ui.GlanceView {

    const TRACK = 0x2A2A2E;
    const GOOD  = 0x10B981;
    const DIM_TEXT = 0xAAAAAA;

    hidden var _demoReadiness = null;   // a demo day's own readiness, from its glance copy

    function initialize() {
        // Qualified: this class is also named GlanceView, so the bare name is itself
        // and the constructor recursed until the glance process died, leaving the
        // watch's blank placeholder card.
        Ui.GlanceView.initialize();
    }

    function onUpdate(dc) {
        drawStyle(dc, style());
    }

    // 0 Next up, 1 Day bar, 2 Ring.
    function style() {
        try {
            var v = Application.Properties.getValue("glanceStyle");
            if (v instanceof Lang.Number && v >= 0 && v <= 2) { return v; }
        } catch (e) {}
        return 0;
    }

    // Public so a scratch build can draw every style on one screen.
    function drawStyle(dc, style) {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();

        var today = Storage.getValue(Config.KEY_TODAY_GLANCE) as Lang.Dictionary?;
        var demo = today != null && today["demo"] == true;
        _demoReadiness = demo ? today["readiness"] : null;
        if (today != null && !demo && stale()) { today = null; }
        var d = GlanceDay.read(today, DayLog.done(),
                               System.getClockTime().hour >= Config.GLANCE_EVENING_HOUR);

        // The glance Dc spans the FULL face; the device profile puts the content
        // area ~18% in and ~77% wide, and the card ~30% of the width tall (138 px
        // measured from a photo of the 454 px fenix 9; the 416 px 43 mm's
        // profile gives 120), so everything is held inside that, centred in its
        // height. The band sits near the top of a round face where the chord is
        // narrower.
        var w = dc.getWidth();
        var pad = (w * 18) / 100;
        var right = pad + (w * 77) / 100;
        var gh = dc.getHeight();
        if (gh > (w * 30) / 100) { gh = (w * 30) / 100; }

        try {
            if (style == 1) { drawBar(dc, d, pad, right, gh); }
            else if (style == 2) { drawRing(dc, d, pad, right, gh); }
            else { drawNextUp(dc, d, pad, right, gh); }
        } catch (e) {
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            dc.drawText(pad, 0, Gfx.FONT_XTINY, "gfx: " + e.getErrorMessage(), Gfx.TEXT_JUSTIFY_LEFT);
        }
    }

    // ── Next up ────────────────────────────────────────────────────────────

    hidden function drawNextUp(dc, d, pad, right, gh) {
        var lines = GlanceDay.nextUp(d);
        var f = Gfx.FONT_GLANCE;
        var fh = dc.getFontHeight(f);
        var k = (lines[2] != null && fh * 3 <= gh) ? 3 : 2;
        var ty = (gh - fh * k) / 2;
        if (ty < 0) { ty = 0; }
        // The bar: the next session's colour, green once the day is done.
        var st = d[:st];
        var c = Gfx.COLOR_DK_GRAY;
        if (st == :done) { c = GOOD; }
        else if (st == :todo || st == :some) { c = modalityColor(sessionModality(d[:next])); }
        else if (st == :evening || st == :rest) {
            var t = d[:tomorrow];
            if (t != null && GlanceDay.count(t) > 0) { c = modalityColor(sessionModality(t)); }
        }
        var bw = dc.getWidth() / 100 + 3;
        dc.setColor(c, Gfx.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(pad, ty + fh / 6, bw, fh * k - fh / 3, bw / 2);
        var tx = pad + bw + 10;
        var avail = right - 8 - tx;
        dc.setColor(DIM_TEXT, Gfx.COLOR_TRANSPARENT);
        dc.drawText(tx, ty, f, clip(dc, lines[0], f, avail), Gfx.TEXT_JUSTIFY_LEFT);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(tx, ty + fh, f, clip(dc, lines[1], f, avail), Gfx.TEXT_JUSTIFY_LEFT);
        if (k == 3) {
            dc.setColor(DIM_TEXT, Gfx.COLOR_TRANSPARENT);
            dc.drawText(tx, ty + fh * 2, f, clip(dc, lines[2], f, avail), Gfx.TEXT_JUSTIFY_LEFT);
        }
    }

    // ── Day bar ────────────────────────────────────────────────────────────

    hidden function drawBar(dc, d, pad, right, gh) {
        var lines = GlanceDay.bar(d);
        var f = Gfx.FONT_GLANCE;
        var fh = dc.getFontHeight(f);
        var bh = fh / 3;
        if (bh < 6) { bh = 6; }
        var gap = fh / 4;
        var ty = (gh - (fh * 2 + bh + gap * 2)) / 2;
        if (ty < 0) { ty = 0; }
        var tx = pad + 4;
        var avail = right - 8 - tx;
        dc.setColor(DIM_TEXT, Gfx.COLOR_TRANSPARENT);
        dc.drawText(tx, ty, f, clip(dc, lines[0], f, avail), Gfx.TEXT_JUSTIFY_LEFT);

        var by = ty + fh + gap;
        var st = d[:st];
        if (st == :rest) {
            // The week: done in green, still to come dim.
            var wk = GlanceDay.week(d);
            if (wk == null) {
                segments(dc, tx, by, avail, bh, 1, null, null);
            } else {
                var n = wk[1];
                if (n > 14) { n = 14; }
                var cols = new [n];
                var lit = new [n];
                for (var i = 0; i < n; i += 1) { cols[i] = GOOD; lit[i] = i < wk[0]; }
                segments(dc, tx, by, avail, bh, n, cols, lit);
            }
        } else if (d[:sessions] != null) {
            var ss = d[:sessions];
            var n = ss.size();
            var cols = new [n];
            for (var i = 0; i < n; i += 1) { cols[i] = modalityColor(sessionModality(ss[i])); }
            segments(dc, tx, by, avail, bh, n, cols, d[:flags]);
        } else {
            segments(dc, tx, by, avail, bh, 1, null, null);
        }

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(tx, by + bh + gap, f, clip(dc, lines[1], f, avail), Gfx.TEXT_JUSTIFY_LEFT);
    }

    // `n` rounded segments across `width`; with no colours, one empty track.
    hidden function segments(dc, x, y, width, h, n, cols, lit) {
        var gap = (n > 1) ? 4 : 0;
        var sw = (width - gap * (n - 1)) / n;
        if (sw < 2) { sw = 2; }
        for (var i = 0; i < n; i += 1) {
            var c = (cols == null) ? TRACK : (lit[i] ? cols[i] : dim(cols[i], 45));
            dc.setColor(c, Gfx.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x + i * (sw + gap), y, sw, h, h / 2);
        }
    }

    // ── Ring ───────────────────────────────────────────────────────────────

    hidden function drawRing(dc, d, pad, right, gh) {
        var lines = GlanceDay.ring(d);
        var label = lines[0];
        var value = lines[1];
        var st = d[:st];

        // The graphic, at the left of the band. Plain vector draws, no bitmaps:
        // the glance budget is 64 KB.
        var gx = pad + 16;
        var gy = gh / 2;
        var gr = (gh * 22) / 100;
        if (gr > 16) { gr = 16; }
        if (gr < 8)  { gr = 8; }
        dc.setPenWidth(4);
        if (st == :some) {
            drawProgress(dc, gx, gy, gr, d[:sessions], d[:flags]);
        } else if (st == :done || st == :evening) {
            drawDone(dc, gx, gy, gr);
        } else {
            // Readiness before any training; a grey ring when not synced.
            drawReadiness(dc, gx, gy, gr, st == :todo || st == :rest, d[:first]);
        }

        // Label small over the value, Garmin's glance order.
        var avail = right - pad - 40;
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

    // Readiness: a ring swept by the score around a dot in the first session's colour.
    hidden function drawReadiness(dc, gx, gy, gr, show, first) {
        var rc = Gfx.COLOR_DK_GRAY;
        var sweep = 1.0;
        var r = !show ? null
              : ((_demoReadiness != null) ? (_demoReadiness as Lang.Dictionary?)
                                          : (Storage.getValue(Config.KEY_READINESS) as Lang.Dictionary?));
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
        dc.setColor(modalityColor(sessionModality(first)), Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(gx, gy, gr / 2);
    }

    // One arc per session, clockwise from 12, in its modality colour: bright when
    // done, dim when still to do.
    hidden function drawProgress(dc, gx, gy, gr, sessions, flags) {
        var n = sessions.size();
        var seg = 360 / n;
        var gap = (n > 1) ? 8 : 0;
        for (var i = 0; i < n; i += 1) {
            var c = modalityColor(sessionModality(sessions[i]));
            dc.setColor(flags[i] ? c : dim(c, 30), Gfx.COLOR_TRANSPARENT);
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

    // ── Shared ─────────────────────────────────────────────────────────────

    // The cache is another day's (stamped with the local date the watch asked for).
    hidden function stale() {
        var d = Storage.getValue(Config.KEY_TODAY_DATE);
        if (d == null) { return false; }
        return !Config.localDate().equals(d);
    }

    hidden function sessionModality(s) {
        return (s != null && s.hasKey("modalityId")) ? s["modalityId"] : null;
    }

    // `c` at `pct` percent: the ring's arcs at 30, the bar's wider segments at 45
    // (at 30 a lone to-do segment all but vanished).
    hidden function dim(c, pct) {
        var r = ((c >> 16) & 0xFF) * pct / 100;
        var g = ((c >> 8) & 0xFF) * pct / 100;
        var b = (c & 0xFF) * pct / 100;
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
