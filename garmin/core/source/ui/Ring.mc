using Toybox.Graphics as Gfx;
using Toybox.Math;

// Arc primitives for the bezel instrument.
//
// Garmin's drawArc uses MATH convention: 0 deg is 3 o'clock and degrees increase
// COUNTER-clockwise (90 = 12 o'clock, 180 = 9, 270 = 6). Screen y grows downward,
// so a point at angle t is (cx + r*cos t, cy - r*sin t) — note the minus on y.
//
// A ring that starts at 12 o'clock and fills clockwise therefore runs from 90 to a
// DECREASING end angle, drawn with ARC_CLOCKWISE.
module Ring {

    const ORIGIN = 90;   // 12 o'clock

    // Normalise into [0, 360).
    //
    // Deliberately NOT `d % 360`: Monkey C's modulo is integer-only and throws
    // UnexpectedTypeException("Expected Number/Long, given Number/Float") on the
    // Float angles the segment loop produces. Inputs here are always within a
    // turn or two of range, so the loops run at most once.
    function norm(d) {
        var x = d;
        while (x < 0)      { x += 360.0; }
        while (x >= 360.0) { x -= 360.0; }
        return x;
    }

    // Continuous progress ring. p in [0.0, 1.0].
    //
    // The two clamps are not cosmetic. The SDK says both that "all parameters are
    // truncated towards zero" AND that "a complete circle will be drawn if
    // degreeStart and degreeEnd are equal". At p = 0.999 the end angle is 90.36,
    // which truncates to 90 — equal to the start — so the ring would flash to a
    // full circle just before completing. The 358 clamp prevents that; the 2
    // clamp keeps the first frame of a sweep visible at a 14px pen.
    function drawProgress(dc, cx, cy, r, pen, trackColor, sweepColor, p, rounded) {
        dc.setPenWidth(pen);

        // Track drawn as a circle rather than a 0->360 arc: drawCircle honours
        // setPenWidth and sidesteps the equal-angle rule entirely.
        if (trackColor != null) {
            dc.setColor(trackColor, Gfx.COLOR_TRANSPARENT);
            dc.drawCircle(cx, cy, r);
        }

        if (p == null || p <= 0.0) { return; }
        dc.setColor(sweepColor, Gfx.COLOR_TRANSPARENT);
        if (p >= 1.0) {
            dc.drawCircle(cx, cy, r);
            return;
        }

        var sweep = 360.0 * p;
        if (sweep < 2.0)   { sweep = 2.0; }
        if (sweep > 358.0) { sweep = 358.0; }
        var e = norm(ORIGIN - sweep);
        dc.drawArc(cx, cy, r, Gfx.ARC_CLOCKWISE, ORIGIN, e);

        if (rounded) {
            var h = pen / 2;
            capAt(dc, cx, cy, r, ORIGIN, h);
            capAt(dc, cx, cy, r, e, h);
        }
    }

    // Round cap. drawArc has no cap style, so the ends get a filled circle of
    // half the pen width, anti-aliased by the same setAntiAlias(true).
    function capAt(dc, cx, cy, r, deg, rad) {
        var a = Math.toRadians(deg);
        var x = cx + (r * Math.cos(a)).toNumber();
        var y = cy - (r * Math.sin(a)).toNumber();   // minus: screen y grows down
        dc.fillCircle(x, y, rad);
    }

    // One segment per set / round / interval.
    //
    // Above 24 segments the arcs become sub-degree and the gaps dominate, so it
    // degrades to a continuous ring rather than rendering mush.
    function drawSegments(dc, cx, cy, r, pen, n, filled, trackColor, fillColor) {
        if (n == null || n <= 0) { return; }
        if (n > 24) {
            drawProgress(dc, cx, cy, r, pen, trackColor, fillColor,
                         filled.toFloat() / n, true);
            return;
        }

        var span = 360.0 / n;
        var gap = 6.0;
        if (n > 16)     { gap = 2.0; }
        else if (n > 8) { gap = 3.0; }
        if (gap > span / 2.0) { gap = span / 2.0; }

        dc.setPenWidth(pen);
        for (var i = 0; i < n; i += 1) {
            var s = norm(ORIGIN - (i * span) - (gap / 2.0));
            var e = norm(ORIGIN - ((i + 1) * span) + (gap / 2.0));
            // Never let a segment collapse to start == end; that draws a full circle.
            if (s.toNumber() == e.toNumber()) { continue; }
            dc.setColor(i < filled ? fillColor : trackColor, Gfx.COLOR_TRANSPARENT);
            // Square caps on segments — round caps would eat the gaps.
            dc.drawArc(cx, cy, r, Gfx.ARC_CLOCKWISE, s, e);
        }
    }

    // A short tick at a given fraction of the ring — used to mark a target
    // (the prescribed distance on a ruck, the AMRAP cap) on a ring that can overrun.
    function drawMarker(dc, cx, cy, r, pen, p, color) {
        if (p == null || p <= 0.0 || p >= 1.0) { return; }
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(pen);
        var d = norm(ORIGIN - (360.0 * p));
        var a = Math.toRadians(d);
        var ca = Math.cos(a);
        var sa = Math.sin(a);
        var r0 = r - pen;
        var r1 = r + pen;
        dc.drawLine(cx + (r0 * ca).toNumber(), cy - (r0 * sa).toNumber(),
                    cx + (r1 * ca).toNumber(), cy - (r1 * sa).toNumber());
    }
}
