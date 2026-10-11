using Toybox.Graphics as Gfx;
using Toybox.Lang;

// Typography.
//
// Garmin draws text in Roboto and numbers in Bionic (the device's simulator.json:
// FONT_MEDIUM is Roboto-Regular, FONT_NUMBER_HOT Bionic_Medium on the 47mm). The
// fenix 9 exposes both as scalable system faces, so numerals can be sized as a
// fraction of the screen instead of snapping to the six fixed bitmap sizes. The
// two solar (MIP) models carry different weights — BionicSemiBold and Roboto
// Condensed only — so every face list names a fallback that exists there; before,
// their hero numbers silently dropped to a bitmap font.
//
// getVectorFont() is declared `VectorFont or Null` even for faces the device
// advertises, and the whole API is guarded — every accessor here degrades to a
// bitmap font rather than returning null to a caller.
//
// Resolve fonts ONCE in View.onLayout() and hold the handles; never per frame.
module Text {

    const NUM_FACES  = ["BionicMedium", "BionicSemiBold", "BionicBold"];
    const TEXT_FACES = ["RobotoRegular", "RobotoCondensedRegular", "RobotoCondensedBold"];
    const BOLD_FACES = ["RobotoMedium", "RobotoCondensedBold", "RobotoRegular"];

    var _hero;      // core number
    var _heroWide;  // core number when it's a wide mm:ss
    var _sub;       // secondary metric
    var _label;     // crown labels / exercise name
    var _hint;      // footer hint
    var _ready;

    // The native activity grammar (data pages, summary, step list).
    var _fieldLabel;   // "REPS", "SET" — capitals over a field
    var _fieldValue;   // the field's number
    var _fieldValueS;  // the same, one step down, for long values
    var _fieldValueXS;
    var _bigNum;       // the gauge page's timer, the summary's duration
    var _hrNum;        // the heart-rate readout under the gauge
    var _line;         // "Next: Rest" and other running text
    var _lineBold;     // titles, the exercise name
    var _small;        // time of day, footers, list values

    function init(g) {
        if (_ready == true) { return; }
        _hero     = vector(NUM_FACES, (g.w * 26) / 100);
        _heroWide = vector(NUM_FACES, (g.w * 21) / 100);
        _sub      = vector(NUM_FACES, (g.w * 10) / 100);
        _label    = vector(["RobotoCondensedBold", "RobotoMedium"], (g.w * 68) / 1000);
        _hint     = vector(["RobotoCondensedRegular", "RobotoRegular"], (g.w * 45) / 1000);

        _fieldLabel   = vector(TEXT_FACES, (g.w * 66) / 1000);
        _fieldValue   = vector(NUM_FACES,  (g.w * 175) / 1000);
        _fieldValueS  = vector(NUM_FACES,  (g.w * 135) / 1000);
        _fieldValueXS = vector(NUM_FACES,  (g.w * 100) / 1000);
        _bigNum       = vector(NUM_FACES,  (g.w * 225) / 1000);
        _hrNum        = vector(NUM_FACES,  (g.w * 105) / 1000);
        _line         = vector(TEXT_FACES, (g.w * 76) / 1000);
        _lineBold     = vector(BOLD_FACES, (g.w * 70) / 1000);
        _small        = vector(TEXT_FACES, (g.w * 64) / 1000);
        _ready = true;
    }

    function fieldLabel()   { return (_fieldLabel   != null) ? _fieldLabel   : Gfx.FONT_TINY; }
    function fieldValue()   { return (_fieldValue   != null) ? _fieldValue   : Gfx.FONT_NUMBER_HOT; }
    function fieldValueS()  { return (_fieldValueS  != null) ? _fieldValueS  : Gfx.FONT_NUMBER_MEDIUM; }
    function fieldValueXS() { return (_fieldValueXS != null) ? _fieldValueXS : Gfx.FONT_NUMBER_MILD; }
    function bigNum()       { return (_bigNum       != null) ? _bigNum       : Gfx.FONT_NUMBER_THAI_HOT; }
    function hrNum()        { return (_hrNum        != null) ? _hrNum        : Gfx.FONT_NUMBER_MILD; }
    function line()         { return (_line         != null) ? _line         : Gfx.FONT_SMALL; }
    function lineBold()     { return (_lineBold     != null) ? _lineBold     : Gfx.FONT_SMALL; }
    function small()        { return (_small        != null) ? _small        : Gfx.FONT_TINY; }

    // The largest field-value font in which `str` fits `maxW`.
    function fitValue(dc, str, maxW) {
        var fs = [fieldValue(), fieldValueS(), fieldValueXS()];
        for (var i = 0; i < fs.size(); i += 1) {
            if (dc.getTextWidthInPixels(str, fs[i]) <= maxW) { return fs[i]; }
        }
        return fs[fs.size() - 1];
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
