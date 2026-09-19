using Toybox.Graphics as Gfx;
using Toybox.Math;

// Resolution-independent layout.
//
// The app ships for two round faces — fenix 9 43mm (416x416) and 47/51mm
// (454x454) — and every coordinate in the old code was an absolute pixel offset
// tuned for neither of them ("cy - 82", "btnW = 120", "fillCircle(cx-22, 22, 6)").
//
// Everything here is expressed in 416-design units and scaled UP to the actual
// face. Designing at the smaller size and scaling up means a layout that fits on
// 416 can never clip on 454 — it just gets 9% more air.
//
// This is the ONLY place dc.getWidth() is read. Build it once in View.onLayout()
// and pass the instance to renderers; never construct one in onUpdate().
class Grid {

    public var w, h, cx, cy;

    // Rings
    public var ringR, ringPen, ringRInner, ringPenInner;

    // The three horizontal bands of the face.
    public var yCrown;    // context: exercise n/N, slot role, HR chip
    public var yCore;     // the one number that matters
    public var ySub;      // secondary metric under the core number
    public var yBase;     // set dots / checklist / detail
    public var yHint;     // button hint

    // Elements
    public var iconHero, iconChip, padH, dotR, dotGap, safeInset;

    function initialize(dc) {
        w = dc.getWidth();
        h = dc.getHeight();
        cx = w / 2;
        cy = h / 2;

        ringPen      = u(14);
        ringR        = (w / 2) - u(9);
        ringPenInner = u(8);
        ringRInner   = ringR - ringPen - u(6);

        yCrown = pct(h, 160);
        yCore  = pct(h, 460);
        ySub   = pct(h, 585);
        yBase  = pct(h, 700);
        yHint  = pct(h, 860);

        // NOTE: iconHero/iconChip must stay in sync with the scaleX percentages
        // in resources/drawables/icons_*.xml (13% and 6.7% of screen width).
        // BitmapReference does not expose its dimensions, so the size has to be
        // known here rather than read back from the resource.
        iconHero  = (w * 13) / 100;
        iconChip  = (w * 67) / 1000;
        padH      = u(26);
        dotR      = u(5);
        dotGap    = u(16);
        safeInset = u(35);
    }

    // n is in 416-design units. n * 454 peaks around 189k — no overflow risk.
    hidden function u(n) { return (n * w) / 416; }

    // Thousandths of a dimension, for the vertical band positions.
    hidden function pct(dim, thousandths) { return (dim * thousandths) / 1000; }

    // Width available for centred text at a given y, accounting for the round
    // bezel. Rough but cheap: the chord half-width at that height, inset by the
    // ring. Long archetype names get fitted against this instead of clipping.
    function chordWidth(y) {
        var r = (w / 2) - ringPen - u(10);
        var dy = y - cy;
        if (dy < 0) { dy = -dy; }
        if (dy >= r) { return u(40); }
        var half = Math.sqrt((r * r) - (dy * dy)).toNumber();
        return half * 2;
    }
}
