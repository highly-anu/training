using Toybox.Graphics as Gfx;
using Toybox.Lang;

// Everything shared by all nine workout screens, so a renderer only draws its own
// body. Keeping this in one place is what makes the instrument language
// consistent: the same two rings, the same crown, the same hint, every screen.
module Chrome {

    // Crown: exercise index, slot-role label, and the live HR chip.
    function drawCrown(dc, g, accent, idx, total, roleLabel, hr, hrZone, drift) {
        // n/N, left of centre.
        var lab = Text.label();
        dc.setColor(Theme.TEXT_DIM, Gfx.COLOR_TRANSPARENT);
        if (total != null && total > 0) {
            dc.drawText(g.cx - g.padH, g.yCrown, lab,
                        (idx + 1).toString() + "/" + total.toString(),
                        Gfx.TEXT_JUSTIFY_RIGHT);
        }

        // HR chip, right of centre, coloured by the athlete's actual zone.
        if (hr != null) {
            var col = Theme.zoneColor(hrZone);
            Icons.draw(dc, g.cx + g.padH - g.iconChip, g.yCrown - (g.iconChip / 4),
                       Rez.Drawables.IcUiHeart, col);
            dc.setColor(col, Gfx.COLOR_TRANSPARENT);
            dc.drawText(g.cx + g.padH + (g.iconChip / 4), g.yCrown, lab,
                        hr.toString(), Gfx.TEXT_JUSTIFY_LEFT);
            // Drift arrow: the HR has been out of the prescribed band long enough
            // that the athlete should act. Up = ease off, down = push.
            if (drift != null && drift != 0) {
                var ax = g.cx + g.padH + (g.iconChip * 2);
                Icons.draw(dc, ax, g.yCrown - (g.iconChip / 4),
                           drift > 0 ? Rez.Drawables.IcUiChevronRight
                                     : Rez.Drawables.IcUiChevronLeft, col);
            }
        }

        // Slot role, small and dim, under the counter.
        if (roleLabel != null && !roleLabel.equals("")) {
            dc.setColor(Theme.dimmed(accent, 75), Gfx.COLOR_TRANSPARENT);
            dc.drawText(g.cx, g.yCrown + (g.h * 45 / 1000), Text.hint(),
                        roleLabel, Gfx.TEXT_JUSTIFY_CENTER);
        }
    }

    // The big number, with an optional unit set beside it.
    function drawCore(dc, g, value, color, wide) {
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.drawText(g.cx, g.yCore, wide ? Text.heroWide() : Text.hero(),
                    value, Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    function drawSub(dc, g, str, color) {
        if (str == null) { return; }
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.drawText(g.cx, g.ySub, Text.sub(), str,
                    Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    // Set / round dots. `pop` (0.0-1.0) animates the most recently filled dot.
    function drawDots(dc, g, y, n, filled, accent, pop) {
        if (n == null || n <= 0) { return; }
        // Above ~10 the dots stop being countable at a glance; show "3/12".
        if (n > 10) {
            dc.setColor(Theme.TEXT_DIM, Gfx.COLOR_TRANSPARENT);
            dc.drawText(g.cx, y, Text.label(),
                        filled.toString() + "/" + n.toString(),
                        Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
            return;
        }
        var step = (g.dotR * 2) + g.dotGap;
        var x = g.cx - (((n - 1) * step) / 2);
        for (var i = 0; i < n; i += 1) {
            var rad = g.dotR;
            if (i < filled) {
                dc.setColor(accent, Gfx.COLOR_TRANSPARENT);
                // The just-completed dot pops.
                if (pop != null && pop > 0.0 && i == filled - 1) {
                    rad = (g.dotR * (1.0 + (0.5 * pop))).toNumber();
                }
                dc.fillCircle(x + (i * step), y, rad);
            } else {
                dc.setColor(Theme.dimmed(accent, 28), Gfx.COLOR_TRANSPARENT);
                dc.fillCircle(x + (i * step), y, rad);
            }
        }
    }

    // Footer: what SELECT does right now. Garmin's own guidance is to hint the
    // action when there isn't room to show both information and navigation.
    function drawHint(dc, g, str) {
        if (str == null) { return; }
        dc.setColor(Theme.TEXT_HINT, Gfx.COLOR_TRANSPARENT);
        dc.drawText(g.cx, g.yHint, Text.hint(), str,
                    Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    // Page-loop indicator, drawn on the left bezel.
    function drawPageDots(dc, g, page, total) {
        if (total == null || total <= 1) { return; }
        var step = g.dotR * 3;
        var y0 = g.cy - (((total - 1) * step) / 2);
        var x = g.safeInset;
        for (var i = 0; i < total; i += 1) {
            dc.setColor(i == page ? Theme.TEXT : Theme.TEXT_HINT, Gfx.COLOR_TRANSPARENT);
            dc.fillCircle(x, y0 + (i * step), i == page ? g.dotR : (g.dotR * 2 / 3));
        }
    }

    // A WORK / REST capsule — the EMOM and Tabata state readout.
    function drawCapsule(dc, g, y, label, color) {
        var f = Text.label();
        var tw = dc.getTextWidthInPixels(label, f);
        var padX = g.padH / 2;
        var hgt = (g.h * 70) / 1000;
        var wid = tw + (padX * 2);
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(g.cx - (wid / 2), y - (hgt / 2), wid, hgt, hgt / 2);
        dc.setColor(Theme.BG, Gfx.COLOR_TRANSPARENT);
        dc.drawText(g.cx, y, f, label,
                    Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    // 'positional_sparring' -> 'POSITIONAL SPARRING'
    function roleLabel(role) {
        if (role == null || role.equals("")) { return null; }
        var out = "";
        for (var i = 0; i < role.length(); i += 1) {
            var ch = role.substring(i, i + 1);
            out += ch.equals("_") ? " " : ch;
        }
        return out.toUpper();
    }
}
