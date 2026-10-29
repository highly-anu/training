using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.System;
using Toybox.Math;
using Toybox.Lang;
import Rez.Styles;

// Garmin's activity grammar, drawn the way the watch draws its own Strength
// workout (photographed on the athlete's fenix 9 Pro, 2026-10-09):
//
//   - a heart and the live HR at the top, or the five-zone gauge across it
//   - capitals in Roboto over numbers in Bionic, in one or two fields
//   - a hairline rule, then running text ("Next: Rest" / "1:00")
//   - the button hints Garmin draws at the bezel: a white arc at START, a green
//     arc at LAP — the Personality Library's own assets and positions
//   - vertical page dots on the left, shown briefly after a page turn
//
// Every position is a fraction of the screen so the same code serves the
// 416/454/466 px AMOLED and 260/280 px MIP faces.
module Native {

    // Garmin's zone colours on the fenix gauge (from the photos), not the web
    // app's palette: the gauge is meant to read like the watch's own.
    const Z1 = 0xB4AAE6;   // lavender
    const Z2 = 0x2E9BE6;   // blue
    const Z3 = 0x2ECC40;   // green
    const Z4 = 0xFF8C1A;   // orange
    const Z5 = 0xE8323C;   // red

    const HEART_RED  = 0xE8323C;
    const RULE       = 0xFFFFFF;
    const DIM        = 0x9AA0A6;
    const BLOCK_NOW  = 0xF5B400;   // the yellow of the current block in the step list
    const CURSOR     = 0x2E9BE6;   // the blue bar beside the focused step
    const GOOD       = 0x2ECC40;
    const WARN       = 0xF5B400;
    const NEXT_PAGE  = 0x9DB8FF;   // the light blue of the next page's name, a summary page's foot
    const BAND       = 0x5A5FE0;   // the rules around Training Effect's benefit word
    const AREA       = 0x22304A;   // the fill under the heart-rate line

    // Bitmaps for the button hints, loaded once.
    var _hintStart = null;
    var _hintReady = null;
    var _hintLap   = null;

    function zoneColor(z) {
        if (z == null) { return HEART_RED; }
        if (z <= 1) { return Z1; }
        if (z == 2) { return Z2; }
        if (z == 3) { return Z3; }
        if (z == 4) { return Z4; }
        return Z5;
    }

    function clear(dc) {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        if (dc has :setAntiAlias) { dc.setAntiAlias(true); }
    }

    // ── button hints ─────────────────────────────────────────────────────────────

    // :start (white, at START), :ready (green, at START: "press to begin"),
    // :lap (green, at LAP/BACK). The Personality Library places each at its button.
    function hint(dc, which) {
        try {
            if (which == :lap) {
                if (_hintLap == null) { _hintLap = Toybox.Application.loadResource(Rez.Drawables.GmHintLap); }
                dc.drawBitmap(Styles.system_loc__hint_button_right_bottom.x,
                              Styles.system_loc__hint_button_right_bottom.y, _hintLap);
            } else if (which == :ready) {
                if (_hintReady == null) { _hintReady = Toybox.Application.loadResource(Rez.Drawables.GmHintStartReady); }
                dc.drawBitmap(Styles.system_loc__hint_button_right_top.x,
                              Styles.system_loc__hint_button_right_top.y, _hintReady);
            } else {
                if (_hintStart == null) { _hintStart = Toybox.Application.loadResource(Rez.Drawables.GmHintStart); }
                dc.drawBitmap(Styles.system_loc__hint_button_right_top.x,
                              Styles.system_loc__hint_button_right_top.y, _hintStart);
            }
        } catch (e) {
            // A missing hint is cosmetic; never let it take a screen down.
        }
    }

    function releaseHints() { _hintStart = null; _hintReady = null; _hintLap = null; }

    // ── text and fields ──────────────────────────────────────────────────────────

    function text(dc, x, y, font, str, color) {
        if (str == null) { return; }
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, str, Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    // Centred, ellipsised to fit maxW.
    function fitted(dc, x, y, font, str, color, maxW) {
        if (str == null) { return; }
        text(dc, x, y, font, Clip.fit(dc, str, font, maxW), color);
    }

    // One field: capitals over a number. f is [label, value] or null.
    function field(dc, x, yLabel, yValue, f, maxW) {
        if (f == null) { return; }
        text(dc, x, yLabel, Text.fieldLabel(), f[0], Gfx.COLOR_WHITE);
        var v = (f[1] == null) ? "--" : f[1].toString();
        text(dc, x, yValue, Text.fitValue(dc, v, maxW), v, Gfx.COLOR_WHITE);
    }

    // Two fields side by side, or one centred when b is null.
    function fields(dc, g, yLabel, yValue, a, b) {
        if (a != null && b != null) {
            var off = (g.w * 21) / 100;
            var maxW = (g.w * 40) / 100;
            field(dc, g.cx - off, yLabel, yValue, a, maxW);
            field(dc, g.cx + off, yLabel, yValue, b, maxW);
        } else {
            field(dc, g.cx, yLabel, yValue, (a != null) ? a : b, (g.w * 70) / 100);
        }
    }

    // ── summary pages (photographed on the athlete's fenix 9 Pro, 2026-10-29) ──

    // A page's title as the watch's own: capitals, a short dash either side of
    // its first line, onto two lines at the space when it is wide
    // ("TRAINING / EFFECT"). Returns the y of its last line.
    function pageTitle(dc, g, str) {
        var f = Text.small();
        var lines = titleLines(dc, g, str, f);
        var step = (g.h * 72) / 1000;
        var y0 = (lines.size() == 1) ? (g.h * 15) / 100 : (g.h * 13) / 100;
        for (var i = 0; i < lines.size(); i += 1) {
            text(dc, g.cx, y0 + (i * step), f, lines[i], Gfx.COLOR_WHITE);
        }
        var half = dc.getTextWidthInPixels(lines[0], f) / 2;
        var gap = (g.w * 3) / 100;
        var dash = (g.w * 35) / 1000;
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth((g.h >= 400) ? 2 : 1);
        dc.drawLine(g.cx - half - gap - dash, y0, g.cx - half - gap, y0);
        dc.drawLine(g.cx + half + gap, y0, g.cx + half + gap + dash, y0);
        return y0 + ((lines.size() - 1) * step);
    }

    // The next page's name at the foot, light blue, wrapped as the title is.
    function nextPage(dc, g, str) {
        var f = Text.small();
        var lines = titleLines(dc, g, str, f);
        var step = (g.h * 72) / 1000;
        var y0 = (lines.size() == 1) ? (g.h * 875) / 1000 : (g.h * 84) / 100;
        for (var i = 0; i < lines.size(); i += 1) {
            text(dc, g.cx, y0 + (i * step), f, lines[i], NEXT_PAGE);
        }
    }

    // One line, or two split at the first space when wider than 45 % of the face.
    function titleLines(dc, g, str, f) {
        var at = str.find(" ");
        if (at == null || dc.getTextWidthInPixels(str, f) <= (g.w * 45) / 100) { return [str]; }
        return [str.substring(0, at), str.substring(at + 1, str.length())];
    }

    // The upright rule between two fields.
    function vrule(dc, g, x, y0, y1) {
        dc.setColor(RULE, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth((g.h >= 400) ? 2 : 1);
        dc.drawLine(x, y0, x, y1);
    }

    // The hairline rule across the face at y, inset from the bezel.
    function rule(dc, g, y, frac) {
        var half = (chordHalf(g, y) * frac) / 100;
        dc.setColor(RULE, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth((g.h >= 400) ? 2 : 1);
        dc.drawLine(g.cx - half, y, g.cx + half, y);
    }

    // Half the visible width of a round face at height y.
    function chordHalf(g, y) {
        var r = g.w / 2;
        var dy = y - g.cy;
        if (dy < 0) { dy = -dy; }
        if (dy >= r) { return 0; }
        return Math.sqrt((r * r) - (dy * dy)).toNumber();
    }

    // ♥ 59 — the heart in the athlete's zone colour, the number in Bionic.
    function heartRate(dc, g, y, hr, zone) {
        var s = (hr != null) ? hr.toString() : "--";
        var f = Text.hrNum();
        var tw = dc.getTextWidthInPixels(s, f);
        var icon = g.iconChip;
        var gap = icon / 4;
        var x0 = g.cx - ((icon + gap + tw) / 2);
        Icons.draw(dc, x0, y - (icon / 2), Rez.Drawables.IcUiHeart, zoneColor(zone));
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x0 + icon + gap, y, f, s, Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    // ── page dots ────────────────────────────────────────────────────────────────

    // Vertical, on the left: the current page a filled dot in a ring, the others
    // hollow — as on the watch's own summary loop.
    function pageDots(dc, g, page, total) {
        if (total == null || total <= 1) { return; }
        var r = (g.w * 11) / 1000;
        if (r < 2) { r = 2; }
        var step = r * 4;
        var x = (g.w * 9) / 100;
        var y0 = g.cy - (((total - 1) * step) / 2);
        dc.setPenWidth(2);
        for (var i = 0; i < total; i += 1) {
            var y = y0 + (i * step);
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            if (i == page) {
                dc.fillCircle(x, y, r);
                dc.drawCircle(x, y, r + 3);
            } else {
                dc.drawCircle(x, y, r);
            }
        }
    }

    // ── heart-rate zone gauge ────────────────────────────────────────────────────

    // Five zone segments across the top of the bezel, 10 o'clock to 2 o'clock;
    // the current zone thicker and a white tick at the live position (p in [0,1]).
    function zoneGauge(dc, g, p, zone) {
        var r = (g.w / 2) - ((g.w * 45) / 1000);
        var pen = (g.w * 22) / 1000;
        if (pen < 3) { pen = 3; }
        var start = 150;
        var span = 120;
        var seg = span / 5;
        for (var i = 0; i < 5; i += 1) {
            var a0 = start - (i * seg) - 1;
            var a1 = start - ((i + 1) * seg) + 1;
            var on = (zone != null && zone == i + 1);
            dc.setPenWidth(on ? pen * 2 : pen);
            dc.setColor(zoneColor(i + 1), Gfx.COLOR_TRANSPARENT);
            dc.drawArc(g.cx, g.cy, r, Gfx.ARC_CLOCKWISE, a0, a1);
        }
        if (p != null) {
            var deg = start - (span * p);
            var rad = Math.toRadians(deg);
            var r0 = r - (pen * 2);
            var r1 = r + pen;
            var c = Math.cos(rad);
            var s = Math.sin(rad);
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            dc.setPenWidth((pen * 2) / 3 + 1);
            dc.drawLine(g.cx + (r0 * c), g.cy - (r0 * s), g.cx + (r1 * c), g.cy - (r1 * s));
        }
    }

    // ── misc ─────────────────────────────────────────────────────────────────────

    // A menu icon for IconMenuItem: a Drawable, as in Garmin's own Menu2 sample,
    // rather than a bitmap loaded into the app heap (1.1.0 passed loaded bitmaps
    // and START, which opens the stop menu, crashed on the watch).
    function icon(rid) { return new MenuIcon(rid); }

    // "3:54p" or "15:54", per the watch's own time format.
    function timeOfDay() {
        var t = System.getClockTime();
        var h = t.hour;
        var m = t.min.format("%02d");
        if (System.getDeviceSettings().is24Hour) { return h.toString() + ":" + m; }
        var suffix = (h < 12) ? "a" : "p";
        h = h % 12;
        if (h == 0) { h = 12; }
        return h.toString() + ":" + m + suffix;
    }

    // The system toast, with one of the Personality Library's icons. Absent on a
    // product without the API: then nothing is shown and nothing breaks.
    function toast(msg, good) {
        try {
            if (Ui has :showToast) {
                Ui.showToast(msg, { :icon => good ? Rez.Drawables.GmToastCheck
                                                  : Rez.Drawables.GmToastWarning });
            }
        } catch (e) {}
    }

    // A title-cased day label: "Today", "Fri 10".
    function dayName(offset) {
        if (offset == 0) { return "Today"; }
        var s = Clip.dayLabel(offset);
        return s.substring(0, 1) + s.substring(1, 3).toLower() + s.substring(3, s.length());
    }
}

// Draws one icon centred in the area the menu gives it. The bitmap is loaded from
// the graphics pool (Application.loadResource returns a BitmapReference, not heap
// pixels) on first draw, and any failure leaves the row without an icon instead of
// taking the app down.
class MenuIcon extends Ui.Drawable {

    hidden var _rid;
    hidden var _bmp;

    function initialize(rid) {
        Drawable.initialize({});
        _rid = rid;
        _bmp = null;
    }

    function draw(dc) {
        try {
            if (_bmp == null) { _bmp = Toybox.Application.loadResource(_rid); }
            if (_bmp == null) { return; }
            dc.drawBitmap((dc.getWidth() - _bmp.getWidth()) / 2,
                          (dc.getHeight() - _bmp.getHeight()) / 2, _bmp);
        } catch (e) {}
    }
}
