// amrap (and the amrap_movement components folded into it).
//
// ROUNDS and the time left on the cap; the movements of one round under the rule.
// LAP counts a round; once the cap has run out, LAP moves on.
class AmrapRenderer extends Renderer {

    function initialize() { Renderer.initialize(); }

    function fieldA(ctl, ex) {
        // Ladder protocols count rungs, not rounds.
        if (ArchetypeBehavior.isLadder(ctl.archetypeId())) {
            return ["RUNG", ArchetypeBehavior.ladderRung(ctl.amrapRounds()).toString()];
        }
        return ["ROUNDS", ctl.amrapRounds().toString()];
    }

    function fieldB(ctl, ex) { return ["LEFT", Text.mmss(ctl.exerciseRemainingSec())]; }

    function lines(ctl, ex) {
        if (ArchetypeBehavior.isLadder(ctl.archetypeId())) {
            return [ArchetypeBehavior.ladderTotal(ctl.amrapRounds()).toString() + " reps total",
                    "Next: " + ctl.nextStep()[0]];
        }
        var comps = ctl.componentsForCurrent();
        if (comps != null && comps.size() > 0) {
            var a = "";
            for (var i = 0; i < comps.size() && i < 3; i += 1) {
                var c = comps[i];
                var rpr = c.repsPerRound();
                if (i > 0) { a += "  "; }
                a += ((rpr != null) ? (rpr.toString() + " ") : "") + c.name();
            }
            return [a, "Next: " + ctl.nextStep()[0]];
        }
        return Renderer.lines(ctl, ex);
    }

    function onLap(ctl, ex) {
        var cap = (ex != null && ex.timeMinutes() != null) ? ex.timeMinutes() : 0;
        if (cap > 0 && ctl.exerciseRemainingSec() <= 0) { ctl.skip(); return; }
        ctl.logRound();
    }
}
