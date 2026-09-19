using Toybox.Graphics as Gfx;

// amrap (and the amrap_movement components folded into it).
//
// An AMRAP is ONE screen: a countdown, a round counter, and the movements that
// make up a round. The component movements arrive as sibling slots in the
// payload, linked by parentSlotRole — rendering them as separate sequential
// exercises, as the app used to, turns one 20-minute AMRAP into three unrelated
// blocks.
class AmrapRenderer extends Renderer {

    function initialize() { Renderer.initialize(); }

    function core(ctl, ex)     { return Text.mmss(ctl.exerciseRemainingSec()); }
    function coreWide(ctl, ex) { return true; }

    function sub(ctl, ex) {
        // Ladder protocols count rungs, not rounds: a flat "ROUND 7" says nothing
        // about where you are in a 1-20-1 breathing ladder.
        if (ArchetypeBehavior.isLadder(ctl.archetypeId())) {
            var rung = ArchetypeBehavior.ladderRung(ctl.amrapRounds());
            return "RUNG " + rung.toString();
        }
        return "ROUND " + (ctl.amrapRounds() + 1).toString();
    }

    function innerProgress(ctl, ex) {
        var cap = (ex != null && ex.timeMinutes() != null) ? ex.timeMinutes() * 60 : 0;
        if (cap <= 0) { return null; }
        var left = ctl.exerciseRemainingSec();
        return (cap - left).toFloat() / cap.toFloat();
    }

    function drawBase(dc, g, accent, ctl, ex) {
        if (ArchetypeBehavior.isLadder(ctl.archetypeId())) {
            var total = ArchetypeBehavior.ladderTotal(ctl.amrapRounds());
            dc.setColor(Theme.TEXT_DIM, Gfx.COLOR_TRANSPARENT);
            dc.drawText(g.cx, g.yBase, Text.label(),
                        total.toString() + " reps total",
                        Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
            return;
        }

        // The movements of one round, as a checklist.
        var comps = ctl.componentsForCurrent();
        if (comps != null && comps.size() > 0) {
            var y = g.yBase - (g.h * 22 / 1000);
            var step = g.h * 52 / 1000;
            var n = comps.size();
            if (n > 3) { n = 3; }               // three is all that fits legibly
            for (var i = 0; i < n; i += 1) {
                var c = comps[i];
                var rpr = c.repsPerRound();
                var line = ((rpr != null) ? (rpr.toString() + "  ") : "") + c.name();
                dc.setColor(Theme.TEXT_DIM, Gfx.COLOR_TRANSPARENT);
                Text.drawFitted(dc, g.cx, y + (i * step), g.chordWidth(y + (i * step)),
                                line, Theme.TEXT_DIM, (g.w * 46) / 1000,
                                ["RobotoCondensedBold", "RobotoMedium"]);
            }
            return;
        }

        dc.setColor(Theme.TEXT_DIM, Gfx.COLOR_TRANSPARENT);
        dc.drawText(g.cx, g.yBase, Text.label(),
                    ctl.amrapRounds().toString() + " done",
                    Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    function hint(ctl, ex) { return "START  +1 round"; }

    function onSelect(ctl, ex) {
        ctl.logRound();
        Anim.start(Anim.SLOT_PULSE, 1.0, 0.0, 300, Anim.EASE_OUT, null);
        return true;
    }
}
