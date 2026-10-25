using Toybox.Lang;

// The one renderer: page 1 of the workout, drawn from the exercise's screen spec.
//
// Every id here is a vocabulary id (data/commons/watch_vocabulary.json). The
// package chooses ids; this file says what each one shows, so no package can
// change the page's grammar -- Garmin's data page: the title line, two fields
// (capitals over a number), the rule and two lines -- only what fills it. Each
// slot type's default spec reproduces the renderer it had before packages owned
// their screens (SetsReps, Emom, Amrap, ForTime, Distance, StaticHold,
// TimeDomain, RoundTimer).
class SpecRenderer extends Renderer {

    function initialize() { Renderer.initialize(); }

    hidden function spec(ex) { return (ex != null) ? ex.spec() : ScreenSpec.synthesise(null); }

    // ── title ────────────────────────────────────────────────────────────────────

    function title(ctl, ex) {
        if (ex == null) { return null; }
        var parts = spec(ex)["title"];
        var t = "";
        for (var i = 0; i < parts.size(); i += 1) {
            var p = titlePart(ctl, ex, parts[i]);
            if (p == null) { continue; }
            t += (t.length() > 0) ? ("  " + p) : p;
        }
        return (t.length() > 0) ? t : ex.name();
    }

    hidden function titlePart(ctl, ex, id) {
        if (id.equals("name")) { return ex.name(); }
        if (id.equals("load")) {
            // Sets show the working weight (Edit Set changes it); the rest the plan's.
            var w = ex.isTemplate("sets") ? ctl.editWeight() : ex.weightKg();
            return (w != null) ? (Steps.loadText(ex, w) + " kg") : null;
        }
        if (id.equals("side")) {
            return ex.sideTracked() ? (ctl.sideIsLeft() ? "Left" : "Right") : null;
        }
        if (id.equals("switch_side")) {
            return (ex.switchAtSec() != null) ? (ctl.sideIsLeft() ? "Left" : "Right") : null;
        }
        if (id.equals("wave_pct")) {
            var wave = ex.behaviour("load_wave");
            var i = ctl.emomRound() - 1;
            return (wave != null && i >= 0 && i < wave.size()) ? (wave[i].toString() + "%") : null;
        }
        if (id.equals("zone_or_load")) {
            var z = ex.zoneLower();
            if (z != null) {
                var hi = ex.zoneUpper();
                return "Z" + z.toString() + ((hi != null && hi != z) ? ("-" + hi.toString()) : "");
            }
            return (ex.weightKg() != null) ? (Steps.loadText(ex, ex.weightKg()) + " kg") : null;
        }
        if (id.equals("pack")) {
            return (ex.packLoadKg() != null) ? ("pack " + Text.kg(ex.packLoadKg()) + " kg") : null;
        }
        return null;
    }

    // ── fields ───────────────────────────────────────────────────────────────────

    function fieldA(ctl, ex)     { return field(ctl, ex, spec(ex)["a"]); }
    function fieldB(ctl, ex)     { return field(ctl, ex, spec(ex)["b"]); }
    function gaugeField(ctl, ex) { return field(ctl, ex, spec(ex)["gauge"]); }

    hidden function field(ctl, ex, id) {
        if (id == null) { return null; }
        if (id.equals("reps"))   { return ["REPS", ctl.editReps().toString()]; }
        if (id.equals("set"))    { return setField(ctl, ex); }
        if (id.equals("rpe_or_set")) {
            if (ex != null && ex.targetRpe() != null && ctl.editWeight() == null) {
                return ["RPE", Text.kg(ctl.editRpe())];
            }
            return setField(ctl, ex);
        }
        if (id.equals("cumulative")) {
            var cum = (ex != null) ? ex.behaviour("cumulative_target") : null;
            var done = ctl.repsDoneFor(ex).toString();
            return ["TOTAL", (cum != null) ? (done + "/" + cum.toString()) : done];
        }
        if (id.equals("rounds")) { return ["ROUNDS", ctl.amrapRounds().toString()]; }
        if (id.equals("rounds_of_target")) {
            var t = (ex != null) ? ex.targetRounds() : null;
            return ["ROUNDS", ctl.amrapRounds().toString() + ((t != null) ? ("/" + t.toString()) : "")];
        }
        if (id.equals("rung"))     { return ["RUNG", Ladder.rung(ctl.amrapRounds(), peak(ex)).toString()]; }
        if (id.equals("cap_left")) { return ["LEFT", Text.mmss(ctl.exerciseRemainingSec())]; }
        if (id.equals("elapsed"))  { return ["TIME", Text.mmss(elapsed(ctl))]; }
        if (id.equals("time_left")) {
            // A timed step counts down and ends itself, as Garmin's do.
            var mins = (ex != null) ? ex.durationMinutes() : null;
            if (mins != null && mins > 0) {
                var left = (mins * 60) - elapsed(ctl);
                return ["TIME LEFT", Text.mmss((left > 0) ? left : 0)];
            }
            return ["TIME", Text.mmss(elapsed(ctl))];
        }
        if (id.equals("zone_or_time")) {
            if (ex == null) { return null; }
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
        if (id.equals("distance")) {
            if (Steps.isShortDistance(ex)) {
                return ["LAPS", ctl.amrapRounds().toString() + "/" + Steps.setCount(ex).toString()];
            }
            return ["KM", Text.kg(ctl.distanceKm())];
        }
        if (id.equals("distance_target")) {
            if (ex == null) { return null; }
            if (Steps.isShortDistance(ex)) { return ["METRES", ex.distanceM().toString()]; }
            if (ex.distanceKm() != null) { return ["OF KM", Text.kg(ex.distanceKm())]; }
            return ["TIME", Text.mmss(elapsed(ctl))];
        }
        if (id.equals("distance_km")) { return ["KM", Text.kg(ctl.distanceKm())]; }
        if (id.equals("hold")) {
            return ["HOLD", Text.secs(ctl.holdRunning() ? ctl.holdRemaining() : ctl.holdTarget())];
        }
        if (id.equals("interval")) {
            if (!ctl.intervalWorking() && ctl.intervalRestSec() > 0) {
                if (ctl.gateRest()) { return ["REST", Text.mmss(ctl.restPhaseElapsed())]; }
                return [ctl.restLabel(ex).toUpper(), intervalRounds(ctl)];
            }
            if (ex != null && ex.targetRpm() != null) { return ["RPM", ex.targetRpm().toString()]; }
            return [ctl.isRunInterval(ex) ? "INTERVAL" : "ROUND", intervalRounds(ctl)];
        }
        if (id.equals("interval_left")) {
            if (ctl.gateRest() && !ctl.intervalWorking()) {
                var hr = ctl.currentHR();
                return ["HR TO " + ex.restUntilHr().toString(), (hr != null) ? hr.toString() : "--"];
            }
            return ["TIME LEFT", Text.secs(ctl.intervalLeft())];
        }
        if (id.equals("interval_round")) {
            return [ctl.isRunInterval(ex) ? "INTERVAL" : "ROUND", intervalRounds(ctl)];
        }
        if (id.equals("block_left")) {
            var l = blockLeft(ctl, ex);
            return (l != null) ? ["LEFT", Text.mmss(l)] : ["TIME", Text.mmss(elapsed(ctl))];
        }
        if (id.equals("rpm")) {
            var r = (ex != null) ? ex.targetRpm() : null;
            return ["RPM", (r != null) ? r.toString() : "--"];
        }
        if (id.equals("pack_kg")) {
            var p = (ex != null) ? ex.packLoadKg() : null;
            return ["PACK KG", (p != null) ? Text.kg(p) : "--"];
        }
        if (id.equals("hr")) {
            var h = ctl.currentHR();
            return ["HR", (h != null) ? h.toString() : "--"];
        }
        return null;
    }

    // ── the lines under the rule ─────────────────────────────────────────────────

    function lines(ctl, ex) {
        var id = spec(ex)["lines"];
        if (ex == null || id == null) { return Renderer.lines(ctl, ex); }
        var next = "Next: " + ctl.nextStep()[0];
        if (id.equals("focus")) {
            return (ex.focus() != null) ? [ex.focus(), next] : Renderer.lines(ctl, ex);
        }
        if (id.equals("last_then_next")) {
            // What was done last time, to beat — until this exercise's first
            // set is done (and never over a rest, which says what comes next).
            if (ex.last() != null && ctl.setsDoneFor(ex) == 0 && ctl.state() != WorkoutController.RESTING) {
                return ["Last time", ex.last()];
            }
            return Renderer.lines(ctl, ex);
        }
        if (id.equals("components")) {
            // The step's own movement leads when it has a count (Fran's
            // thrusters, Cindy's pull-ups), then the movements folded into it;
            // each shows this round's reps (a scheme's entry for the round).
            var comps = ctl.componentsForCurrent();
            var all = (ex.repsInRound(0) != null) ? [ex] : [];
            if (comps != null) { all.addAll(comps); }
            if (all.size() == 0) { return Renderer.lines(ctl, ex); }
            var round = ctl.amrapRounds();
            var a = "";
            for (var i = 0; i < all.size() && i < 3; i += 1) {
                var c = all[i];
                var rpr = c.repsInRound(round);
                if (i > 0) { a += "  "; }
                a += ((rpr != null) ? (rpr.toString() + " ") : "") + c.name();
            }
            return [a, next];
        }
        if (id.equals("ladder_total")) {
            return [Ladder.total(ctl.amrapRounds(), peak(ex)).toString() + " reps total", next];
        }
        if (id.equals("standard_target")) {
            // A test step: the best to beat and the number for the next level.
            var st = ex.standard();
            if (st == null) { return Renderer.lines(ctl, ex); }
            var best = st["best"];
            var target = st["target"];
            return [(best != null) ? ("Best " + best) : "First result", (target != null) ? target : next];
        }
        if (id.equals("hold_prompt")) {
            if (ctl.holdRunning()) { return ["Holding", "LAP ends early"]; }
            return ["Press LAP", "to start the hold"];
        }
        if (id.equals("interval_next")) {
            var more = ctl.emomTotal() <= 0 || ctl.emomRound() < ctl.emomTotal();
            if (ctl.intervalWorking() && ctl.intervalRestSec() > 0) {
                return ["Next: " + ctl.restLabel(ex), ctl.restValue(ex)];
            }
            if (more) { return ["Next: " + ctl.workLabel(ex), ctl.workValue(ex)]; }
            return Renderer.lines(ctl, ex);
        }
        if (id.equals("phases")) {
            var ph = spec(ex).hasKey("phases") ? spec(ex)["phases"] : null;
            if (ph == null || ph.size() == 0) { return Renderer.lines(ctl, ex); }
            var s = "";
            for (var i = 0; i < ph.size(); i += 1) { s += ((i > 0) ? " > " : "") + ph[i]; }
            return [s, next];
        }
        return Renderer.lines(ctl, ex);    // next_step, or an id this build lacks
    }

    // ── LAP ──────────────────────────────────────────────────────────────────────

    function onLap(ctl, ex) {
        var id = spec(ex)["lap"];
        if (ex == null || id == null || id.equals("skip")) { ctl.skip(); return; }
        if (id.equals("complete_set")) { ctl.completeSet(); return; }
        if (id.equals("toggle_hold")) {
            if (ctl.holdRunning()) { ctl.stopHoldEarly(); } else { ctl.startHold(); }
            return;
        }
        if (id.equals("log_round")) { logRound(ctl, ex); return; }
        if (id.equals("next_side")) { ctl.toggleSide(); return; }
        ctl.skip();
    }

    // Whether LAP would move on from a step that ends by itself before it has:
    // a block with time left, an interval block (it ends after its last round),
    // a distance short of its target. A step with no end of its own — an open
    // block, a distance with no target, a test's clock — is ended by LAP, and
    // the actions that do not move on (a set, a hold, a side, a round) never ask.
    function lapSkipsEarly(ctl, ex) {
        if (ex == null) { return false; }
        var id = spec(ex)["lap"];
        var longDistance = ex.isTemplate("distance") && !Steps.isShortDistance(ex);
        if (id != null && (id.equals("complete_set") || id.equals("toggle_hold") || id.equals("next_side")
                           || (id.equals("log_round") && !longDistance))) {
            return false;
        }
        if (longDistance) {
            var km = ex.distanceKm();
            return km != null && ctl.distanceKm() < km;
        }
        if (ex.isTemplate("interval")) { return ctl.emomTotal() > 0; }
        var l = blockLeft(ctl, ex);
        return l != null && l > 0;
    }

    // Counts a round or lap; moves on once the step's countable target is reached,
    // or at once when it has none.
    hidden function logRound(ctl, ex) {
        if (ex.isTemplate("rounds")) {
            var cap = (ex.timeMinutes() != null) ? ex.timeMinutes() : 0;
            if (cap > 0 && ctl.exerciseRemainingSec() <= 0) { ctl.skip(); return; }
            ctl.logRound();
        } else if (ex.isTemplate("for_time")) {
            var t = ex.targetRounds();
            // A test over a distance with no rounds to count (2 km, 3 miles):
            // LAP stops the clock, which is the result. A for-time workout
            // (Fran) keeps LAP for its rounds.
            if (t == null && ex.standard() != null && (ex.distanceKm() != null || ex.distanceM() != null)) {
                ctl.skip();
                return;
            }
            ctl.logRound();
            if (t != null && ctl.amrapRounds() >= t) { ctl.skip(); }
        } else if (ex.isTemplate("distance")) {
            if (!Steps.isShortDistance(ex)) { ctl.skip(); return; }
            ctl.logRound();
            if (ctl.amrapRounds() >= Steps.setCount(ex)) { ctl.skip(); }
        } else if (ex.isTemplate("round_timer")) {
            var l = blockLeft(ctl, ex);
            if (l != null && l == 0) { ctl.skip(); return; }
            ctl.logRound();
        } else {
            ctl.logRound();
        }
    }

    // ── helpers ──────────────────────────────────────────────────────────────────

    hidden function intervalRounds(ctl) {
        var total = ctl.emomTotal();
        return ctl.emomRound().toString() + ((total > 0) ? ("/" + total.toString()) : "");
    }

    hidden function blockLeft(ctl, ex) {
        if (ex == null || ex.durationMinutes() == null) { return null; }
        var l = (ex.durationMinutes() * 60) - elapsed(ctl);
        return (l > 0) ? l : 0;
    }

    hidden function peak(ex) {
        var l = (ex != null) ? ex.behaviour("ladder") : null;
        return (l instanceof Lang.Dictionary && l.hasKey("peak")) ? l["peak"] : 20;
    }
}

// Ladder arithmetic: rungs climb 1..peak and come back down to 1.
module Ladder {
    // The rung for a completed-round index (0-based).
    function rung(roundIdx, peak) {
        var r = roundIdx + 1;
        if (r <= peak) { return r; }
        var down = peak - (r - peak);
        return (down < 1) ? 1 : down;
    }

    // Cumulative reps after n completed rungs.
    function total(rounds, peak) {
        var t = 0;
        for (var i = 0; i < rounds; i += 1) { t += rung(i, peak); }
        return t;
    }
}
