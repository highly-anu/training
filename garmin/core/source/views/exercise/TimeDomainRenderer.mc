// time_domain and skill_practice — everything Uphill Athlete, Kelly Starrett and
// Ido Portal prescribe: hold this block for this long, often in a zone. A block
// with a duration counts down and ends itself; LAP moves on early.
class TimeDomainRenderer extends Renderer {

    function initialize() { Renderer.initialize(); }

    function fieldA(ctl, ex) {
        if (ArchetypeBehavior.isDistanceLed(ctl.archetypeId())) {
            return ["KM", Text.kg(ctl.distanceKm())];
        }
        // A timed step counts down and ends itself, as Garmin's do.
        var mins = (ex != null) ? ex.durationMinutes() : null;
        if (mins != null && mins > 0) {
            var left = (mins * 60) - elapsed(ctl);
            return ["TIME LEFT", Text.mmss((left > 0) ? left : 0)];
        }
        return ["TIME", Text.mmss(elapsed(ctl))];
    }

    function fieldB(ctl, ex) {
        if (ex == null) { return null; }
        if (ArchetypeBehavior.isDistanceLed(ctl.archetypeId())) {
            return ["TIME", Text.mmss(elapsed(ctl))];
        }
        var lo = ex.zoneLower();
        if (lo != null) {
            var hi = ex.zoneUpper();
            return ["ZONE", (hi != null && hi != lo) ? (lo.toString() + "-" + hi.toString())
                                                     : lo.toString()];
        }
        // Counting down on the left, the time spent on the right; an open block
        // already shows its time on the left.
        return (ex.durationMinutes() != null) ? ["TIME", Text.mmss(elapsed(ctl))] : null;
    }

    function lines(ctl, ex) {
        if (ex != null && ex.focus() != null) { return [ex.focus(), "Next: " + ctl.nextStep()[0]]; }
        return Renderer.lines(ctl, ex);
    }
}
