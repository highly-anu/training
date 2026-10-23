using Toybox.Graphics as Gfx;
using Toybox.Application;
using Toybox.Lang;

// A list drawn as the watch draws its own activity lists (photographed on the
// athlete's fenix 9 Pro, 2026-10-23: Strength's pre-start list), for the pages
// where the system Menu2 cannot do the job — a header START acts on, numbers
// beside the rows. Each row is an icon left of a thin vertical rule, then a
// label over a sub-label, left-aligned; the focused row sits at the centre on a
// band in the activity's colour with a bar of it on the rule.
//
// rows: [[id, label, sub-label or null, icon Rez id, a number String, or null], ...]
module NativeList {

    const ICON_X = 270;     // thousandths of the width
    const RULE_X = 365;
    const TEXT_X = 400;
    const ROW_H  = 210;     // thousandths of the height
    const SUB_COLOR = 0xC9C9CE;

    var _icons = {};        // Rez id -> BitmapReference, from the graphics pool

    function rowHeight(g) { return (g.h * ROW_H) / 1000; }

    // The rows with `focus` at y = cy, or — when focus is -1 (the header has it)
    // — from `topY` down, none focused.
    function draw(dc, g, rows, focus, accent, topY) {
        var rh = rowHeight(g);
        for (var i = 0; i < rows.size(); i += 1) {
            var y = (focus >= 0) ? (g.cy + (i - focus) * rh) : (topY + i * rh);
            if (y + rh / 2 < 0 || y - rh / 2 > g.h) { continue; }
            drawRow(dc, g, rows[i], y, rh, i == focus, accent);
        }
    }

    function drawRow(dc, g, row, y, rh, focused, accent) {
        var ruleX = (g.w * RULE_X) / 1000;
        var textX = (g.w * TEXT_X) / 1000;
        var top = y - rh / 2;
        var right = g.cx + Native.chordHalf(g, y) - (g.w * 4) / 100;
        if (focused) {
            dc.setColor(Theme.dimmed(accent, 32), Gfx.COLOR_TRANSPARENT);
            dc.fillRectangle(ruleX, top + 2, right - ruleX, rh - 4);
            dc.setColor(accent, Gfx.COLOR_TRANSPARENT);
            dc.fillRectangle(ruleX - 2, top + 2, 5, rh - 4);
        } else {
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawLine(ruleX, top + 4, ruleX, top + rh - 4);
        }
        if (row[3] instanceof Lang.String) { drawAside(dc, g, ruleX, y, row[3]); }
        else if (row[3] != null) { drawIcon(dc, (g.w * ICON_X) / 1000, y, row[3], (g.w * 74) / 454); }
        var w = right - textX;
        if (w <= 0) { return; }
        var label = Text.line();
        var sub = Text.small();
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        if (row[2] == null) {
            dc.drawText(textX, y, label, Clip.fit(dc, row[1], label, w),
                        Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER);
            return;
        }
        var lh = dc.getFontHeight(label);
        var sh = dc.getFontHeight(sub);
        var y0 = y - (lh + sh) / 2;
        dc.drawText(textX, y0 + lh / 2, label, Clip.fit(dc, row[1], label, w),
                    Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER);
        dc.setColor(focused ? Gfx.COLOR_WHITE : SUB_COLOR, Gfx.COLOR_TRANSPARENT);
        dc.drawText(textX, y0 + lh + sh / 2, sub, Clip.fit(dc, row[2], sub, w),
                    Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    // A number in place of the icon, right-aligned against the rule, as the
    // post-save list shows each page's headline ("45:12", "1.6", "112").
    function drawAside(dc, g, ruleX, y, str) {
        var right = ruleX - (g.w * 3) / 100;
        var left = g.cx - Native.chordHalf(g, y) + (g.w * 3) / 100;
        var f = Text.hrNum();
        if (dc.getTextWidthInPixels(str, f) > right - left) { f = Text.small(); }
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(right, y, f, str, Gfx.TEXT_JUSTIFY_RIGHT | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    // The menu icons are system_size__menu_icon (74 px on a 454 px face); a
    // BitmapReference that cannot say its size is taken to be that.
    function drawIcon(dc, x, y, rid, size) {
        try {
            var b = _icons.hasKey(rid) ? _icons[rid] : null;
            if (b == null) {
                b = Application.loadResource(rid);
                _icons[rid] = b;
            }
            if (b == null) { return; }
            var bw = (b has :getWidth) ? b.getWidth() : size;
            var bh = (b has :getHeight) ? b.getHeight() : size;
            dc.drawBitmap(x - bw / 2, y - bh / 2, b);
        } catch (e) {}
    }

    // Let the bitmaps go when the page is hidden (a workout needs the room).
    function release() { _icons = {}; }

    // The next focus moving by `d`: -1 is the header, the rows 0..n-1; past
    // either end it wraps, as Garmin's lists do.
    function step(focus, d, n) {
        var f = focus + d;
        if (f >= n) { return -1; }
        if (f < -1) { return n - 1; }
        return f;
    }
}
