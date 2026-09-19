using Toybox.Graphics as Gfx;
using Toybox.Lang;

// Typography.
//
// The fenix 9 exposes scalable system fonts (BionicBold/BionicMedium are Garmin's
// number faces, RobotoCondensed* the text faces), so numerals can be sized as a
// fraction of the screen instead of snapping to the six fixed bitmap sizes.
//
// getVectorFont() is declared `VectorFont or Null` even for faces the device
// advertises, and the whole API is guarded — every accessor here degrades to a
// bitmap font rather than returning null to a caller.
//
// Resolve fonts ONCE in View.onLayout() and hold the handles; never per frame.
module Text {

    var _hero;      // core number
    var _heroWide;  // core number when it's a wide mm:ss
    var _sub;       // secondary metric
    var _label;     // crown labels / exercise name
    var _hint;      // footer hint
    var _ready;

    function init(g) {
        if (_ready == true) { return; }
        _hero     = vector(["BionicBold", "BionicMedium"], (g.w * 26) / 100);
        _heroWide = vector(["BionicBold", "BionicMedium"], (g.w * 21) / 100);
        _sub      = vector(["BionicMedium", "BionicBold"], (g.w * 10) / 100);
        _label    = vector(["RobotoCondensedBold", "RobotoMedium"], (g.w * 68) / 1000);
        _hint     = vector(["RobotoCondensedRegular", "RobotoRegular"], (g.w * 45) / 1000);
        _ready = true;
    }

    function vector(faces, px) {
        if (!(Gfx has :getVectorFont)) { return null; }
        var f = Gfx.getVectorFont({ :face => faces, :size => px });
        return f;   // may still be null; callers fall back
    }

    function hero()     { return (_hero     != null) ? _hero     : Gfx.FONT_NUMBER_HOT; }
    function heroWide() { return (_heroWide != null) ? _heroWide : Gfx.FONT_NUMBER_HOT; }
    function sub()      { return (_sub      != null) ? _sub      : Gfx.FONT_NUMBER_MILD; }
    function label()    { return (_label    != null) ? _label    : Gfx.FONT_SMALL; }
    function hint()     { return (_hint     != null) ? _hint     : Gfx.FONT_XTINY; }

    // An arbitrarily-sized vector font, for one-off fitting.
    function sized(faces, px) { return vector(faces, px); }

    // Draw centred text, shrinking the font until it fits maxW.
    //
    // Archetype names run long ("Gym Jones Accumulation Circuit (Goblet Squat /
    // Bear Crawl / Carry)") and used to be drawn as a single un-wrapped
    // FONT_MEDIUM line, so they simply clipped off both edges of a round screen.
    function drawFitted(dc, x, y, maxW, str, color, basePx, faces) {
        if (str == null) { return; }
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        var px = basePx;
        var f = sized(faces, px);
        if (f == null) {
            // No vector fonts: step down the bitmap ladder instead.
            var ladder = [Gfx.FONT_MEDIUM, Gfx.FONT_SMALL, Gfx.FONT_TINY, Gfx.FONT_XTINY];
            for (var i = 0; i < ladder.size(); i += 1) {
                if (dc.getTextWidthInPixels(str, ladder[i]) <= maxW || i == ladder.size() - 1) {
                    dc.drawText(x, y, ladder[i], str, Gfx.TEXT_JUSTIFY_CENTER);
                    return;
                }
            }
            return;
        }
        // Five shrink steps, then give up and let it ride.
        for (var i = 0; i < 5; i += 1) {
            if (dc.getTextWidthInPixels(str, f) <= maxW) { break; }
            px = (px * 85) / 100;
            var next = sized(faces, px);
            if (next == null) { break; }
            f = next;
        }
        dc.drawText(x, y, f, str, Gfx.TEXT_JUSTIFY_CENTER);
    }

    // Wrap to at most two lines on a word boundary, centred. Returns lines drawn.
    function drawWrapped2(dc, x, y, maxW, lineH, str, color, font) {
        if (str == null) { return 0; }
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        if (dc.getTextWidthInPixels(str, font) <= maxW) {
            dc.drawText(x, y, font, str, Gfx.TEXT_JUSTIFY_CENTER);
            return 1;
        }
        // Find the space nearest the middle that lets the first line fit.
        var best = -1;
        for (var i = 0; i < str.length(); i += 1) {
            if (!str.substring(i, i + 1).equals(" ")) { continue; }
            if (dc.getTextWidthInPixels(str.substring(0, i), font) <= maxW) { best = i; }
        }
        if (best < 0) {
            dc.drawText(x, y, font, str, Gfx.TEXT_JUSTIFY_CENTER);
            return 1;
        }
        dc.drawText(x, y, font, str.substring(0, best), Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(x, y + lineH, font, str.substring(best + 1, str.length()),
                    Gfx.TEXT_JUSTIFY_CENTER);
        return 2;
    }

    // "4:07" / "1:02:33"
    function mmss(sec) {
        if (sec == null) { sec = 0; }
        if (sec < 0) { sec = 0; }
        var h = sec / 3600;
        var m = (sec % 3600) / 60;
        var s = sec % 60;
        if (h > 0) {
            return h.format("%d") + ":" + m.format("%02d") + ":" + s.format("%02d");
        }
        return m.format("%d") + ":" + s.format("%02d");
    }

    // ":47" — a bare seconds countdown, for EMOM intervals and holds.
    function secs(sec) {
        if (sec == null || sec < 0) { sec = 0; }
        if (sec >= 60) { return mmss(sec); }
        return ":" + sec.format("%02d");
    }

    // Trim trailing zeroes: 82.5 -> "82.5", 80.0 -> "80"
    function kg(v) {
        if (v == null) { return ""; }
        var f = v.toFloat();
        if (f == f.toNumber().toFloat()) { return f.toNumber().format("%d"); }
        return f.format("%.1f");
    }
}
