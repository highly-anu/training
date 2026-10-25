using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Application;
using Toybox.Application.Storage;
using Toybox.System;
using Toybox.Lang;

// The glance, as Garmin's own cards in the glance loop (the athlete's fenix 9
// Pro, 2026-10-25: "Training", "Health"): a white title in the glance font,
// left-aligned, over one row of information. Two styles, picked in Settings ▸
// Glance on the watch or Glance style in Garmin Connect Mobile (`glanceStyle`):
//
//   0  Next up   two icon + value pairs: the next session's icon in its
//                colour and its minutes, then its exercise count ("4 ex").
//   1  Day bar   a segment per session (its colour, bright once done; on a
//                rest day the week's sessions) and one value beside them.
//
// What each says is GlanceDay's; this file only draws it. Everything comes
// from Storage: a glance has no reliable network. A Connect IQ app has one
// glance, so "styles" is a setting, not several glances. Ring, the glance
// until 1.14, is gone; a stored 2 reads as Next up.
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
        drawStyle(dc, style());
    }

    // 0 Next up, 1 Day bar.
    function style() {
        try {
            var v = Application.Properties.getValue("glanceStyle");
            if (v instanceof Lang.Number && v == 1) { return 1; }
        } catch (e) {}
        return 0;
    }

    // Public so a scratch build can draw every style on one screen.
    function drawStyle(dc, style) {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();

        var today = Storage.getValue(Config.KEY_TODAY_GLANCE) as Lang.Dictionary?;
        var demo = today != null && today["demo"] == true;
        if (today != null && !demo && stale()) { today = null; }
        var d = GlanceDay.read(today, DayLog.done(),
                               System.getClockTime().hour >= Config.GLANCE_EVENING_HOUR);

        // The Dc is the card, beside the app's icon the watch draws at its left:
        // in the photo the native titles start ~14 px into it (4 % of its ~347
        // px), and an 18 % inset written for a full-face Dc put our text 65 px
        // right of theirs. Title and row are one block, centred in the card.
        var w = dc.getWidth();
        var x = (w * 4) / 100;
        var right = w - (w * 4) / 100;
        var gh = dc.getHeight();
        if (gh > (w * 40) / 100) { gh = (w * 40) / 100; }
        var f = Gfx.FONT_GLANCE;
        var fh = dc.getFontHeight(f);
        var ty = (gh - fh * 2) / 2;
        if (ty < 0) { ty = 0; }

        try {
            if (style == 1) { drawBar(dc, d, x, right, ty, f, fh); }
            else { drawNextUp(dc, d, x, right, ty, f, fh); }
        } catch (e) {
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            dc.drawText(x, 0, Gfx.FONT_XTINY, "gfx: " + e.getErrorMessage(), Gfx.TEXT_JUSTIFY_LEFT);
        }
    }

    // ── Next up ────────────────────────────────────────────────────────────

    hidden function drawNextUp(dc, d, x, right, ty, f, fh) {
        var c = GlanceDay.nextUp(d);
        title(dc, c[0], x, right, ty, f);
        var ry = ty + fh;
        if (c[2] == null) {
            pair(dc, c[1], x, right, ry, f, fh);
            return;
        }
        // Two pairs, the second from the middle of the card, as Garmin's.
        var mid = x + (right - x) / 2;
        pair(dc, c[1], x, mid - 6, ry, f, fh);
        pair(dc, c[2], mid, right, ry, f, fh);
    }

    // [glyph, text, session]: the icon, then the value in white.
    hidden function pair(dc, p, x, right, y, f, fh) {
        var sz = iconSize();
        var tint = Gfx.COLOR_LT_GRAY;
        var rid = Rez.Drawables.GlGeneric;
        var g = p[0];
        if (g == :session) { rid = sessionIcon(p[2]); tint = sessionColor(p[2]); }
        else if (g == :check) { rid = Rez.Drawables.GlCheck; tint = GOOD; }
        else if (g == :sets)  { rid = Rez.Drawables.GlSets; }
        else if (g == :steps) { rid = Rez.Drawables.GlSteps; }
        else if (g == :week)  { rid = Rez.Drawables.GlWeek; tint = GOOD; }
        else if (g == :rest)  { rid = Rez.Drawables.GlRest; tint = GOOD; }
        else if (g == :sync)  { rid = Rez.Drawables.GlSync; }
        var iy = y + (fh - sz) / 2;
        try {
            var r = Application.loadResource(rid);
            if (dc has :drawBitmap2) { dc.drawBitmap2(x, iy, r, { :tintColor => tint }); }
            else { dc.drawBitmap(x, iy, r); }
        } catch (e) {}
        var tx = x + sz + 6;
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(tx, y, f, clip(dc, p[1], f, right - tx), Gfx.TEXT_JUSTIFY_LEFT);
    }

    // ── Day bar ────────────────────────────────────────────────────────────

    hidden function drawBar(dc, d, x, right, ty, f, fh) {
        var c = GlanceDay.bar(d);
        title(dc, c[0], x, right, ty, f);
        var ry = ty + fh;
        // The value at the right of the row, the segments filling what is left.
        var vw = dc.getTextWidthInPixels(c[1], f);
        var maxV = ((right - x) * 45) / 100;
        if (vw > maxV) { vw = maxV; }
        var segRight = right - vw - 10;
        var bh = fh / 3;
        if (bh < 6) { bh = 6; }
        var by = ry + (fh - bh) / 2;
        var width = segRight - x;

        var st = d[:st];
        if (st == :rest) {
            // The week: done in green, still to come dim.
            var wk = GlanceDay.week(d);
            if (wk == null) {
                segments(dc, x, by, width, bh, 1, null, null);
            } else {
                var n = wk[1];
                if (n > 14) { n = 14; }
                var cols = new [n];
                var lit = new [n];
                for (var i = 0; i < n; i += 1) { cols[i] = GOOD; lit[i] = i < wk[0]; }
                segments(dc, x, by, width, bh, n, cols, lit);
            }
        } else if (st == :evening) {
            // Tomorrow's sessions, all still to do, in its first one's colour.
            var t = d[:tomorrow];
            var n = GlanceDay.count(t);
            if (n < 1) { n = 1; }
            if (n > 14) { n = 14; }
            var cols = new [n];
            var lit = new [n];
            for (var i = 0; i < n; i += 1) { cols[i] = sessionColor(t); lit[i] = false; }
            segments(dc, x, by, width, bh, n, cols, lit);
        } else if (d[:sessions] != null) {
            var ss = d[:sessions];
            var n = ss.size();
            var cols = new [n];
            for (var i = 0; i < n; i += 1) { cols[i] = sessionColor(ss[i]); }
            segments(dc, x, by, width, bh, n, cols, d[:flags]);
        } else {
            segments(dc, x, by, width, bh, 1, null, null);
        }

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(right, ry, f, clip(dc, c[1], f, maxV), Gfx.TEXT_JUSTIFY_RIGHT);
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

    // ── Shared ─────────────────────────────────────────────────────────────

    // The cache is another day's (stamped with the local date the watch asked for).
    hidden function stale() {
        var d = Storage.getValue(Config.KEY_TODAY_DATE);
        if (d == null) { return false; }
        return !Config.localDate().equals(d);
    }

    // The card's title: white, in the glance font, as Garmin's.
    hidden function title(dc, str, x, right, y, f) {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x, y, f, clip(dc, str, f, right - x), Gfx.TEXT_JUSTIFY_LEFT);
    }

    // glance.xml's icons are 6 % of the screen's width.
    hidden function iconSize() {
        return (System.getDeviceSettings().screenWidth * 6) / 100;
    }

    // As the pre-start page draws a session (Icons.forSession): its workout
    // icon, else its archetype category's. Tomorrow carries the same two keys.
    hidden function sessionIcon(s) {
        if (s == null) { return Rez.Drawables.GlGeneric; }
        var icon = s.hasKey("icon") ? s["icon"] : null;
        if (icon != null && icon.equals("kettlebell")) { return Rez.Drawables.GlKettlebell; }
        var c = s.hasKey("archetypeCategory") ? s["archetypeCategory"] : null;
        if (c == null) { return Rez.Drawables.GlGeneric; }
        if (c.equals("strength"))       { return Rez.Drawables.GlStrength; }
        if (c.equals("conditioning"))   { return Rez.Drawables.GlConditioning; }
        if (c.equals("kettlebell"))     { return Rez.Drawables.GlKettlebell; }
        if (c.equals("gpp_durability")) { return Rez.Drawables.GlGppDurability; }
        if (c.equals("movement_skill")) { return Rez.Drawables.GlMovementSkill; }
        if (c.equals("combat_sport"))   { return Rez.Drawables.GlCombatSport; }
        if (c.equals("recovery"))       { return Rez.Drawables.GlRecovery; }
        return Rez.Drawables.GlGeneric;
    }

    // The session's colour as the pre-start page draws it (Theme.sessionAccent):
    // its package's accent, which the app resolved into the glance copy, else
    // its modality's.
    hidden function sessionColor(s) {
        if (s == null) { return Gfx.COLOR_LT_GRAY; }
        if (s.hasKey("accent") && s["accent"] != null) { return s["accent"]; }
        return modalityColor(s.hasKey("modalityId") ? s["modalityId"] : null);
    }

    // `c` at `pct` percent: a to-do segment at 45 (at 30 a lone one all but
    // vanished).
    hidden function dim(c, pct) {
        var r = ((c >> 16) & 0xFF) * pct / 100;
        var g = ((c >> 8) & 0xFF) * pct / 100;
        var b = (c & 0xFF) * pct / 100;
        return (r << 16) | (g << 8) | b;
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

}
