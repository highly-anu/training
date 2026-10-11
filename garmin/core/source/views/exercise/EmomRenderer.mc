// emom — every interval block: EMOM strength waves, Tabata, Uphill's threshold and
// hill repeats, kettlebell timed sets at a target RPM, anti-glycolic swings.
//
// Laid out as Garmin's repeat steps: INTERVAL 3/8 (or RPM 14 on a paced set) and
// TIME LEFT, the target on the title line, "Next: Recover 2:00" under the rule. A
// rest with an HR target shows how long it has run and the HR still to come down.
// The phases run themselves; LAP leaves the block.
class EmomRenderer extends Renderer {

    function initialize() { Renderer.initialize(); }

    function title(ctl, ex) {
        if (ex == null) { return null; }
        var t = ex.name();
        var wave = ArchetypeBehavior.loadWave(ctl.archetypeId());
        if (wave != null) {
            var i = ctl.emomRound() - 1;
            if (i >= 0 && i < wave.size()) { t += "  " + wave[i].toString() + "%"; }
        }
        if (ex.switchAtSec() != null) { t += ctl.sideIsLeft() ? "  Left" : "  Right"; }
        var z = ex.zoneLower();
        if (z != null) {
            var hi = ex.zoneUpper();
            t += "  Z" + z.toString() + ((hi != null && hi != z) ? ("-" + hi.toString()) : "");
        } else if (ex.weightKg() != null) {
            t += "  " + Steps.loadText(ex, ex.weightKg()) + " kg";
        }
        return t;
    }

    hidden function rounds(ctl) {
        var total = ctl.emomTotal();
        return ctl.emomRound().toString() + ((total > 0) ? ("/" + total.toString()) : "");
    }

    function fieldA(ctl, ex) {
        if (!ctl.intervalWorking() && ctl.intervalRestSec() > 0) {
            if (ctl.gateRest()) { return ["REST", Text.mmss(ctl.restPhaseElapsed())]; }
            return [ctl.restLabel(ex).toUpper(), rounds(ctl)];
        }
        if (ex != null && ex.targetRpm() != null) { return ["RPM", ex.targetRpm().toString()]; }
        return [ctl.isRunInterval(ex) ? "INTERVAL" : "ROUND", rounds(ctl)];
    }

    function fieldB(ctl, ex) {
        if (ctl.gateRest() && !ctl.intervalWorking()) {
            var hr = ctl.currentHR();
            return ["HR TO " + ex.restUntilHr().toString(), (hr != null) ? hr.toString() : "--"];
        }
        return ["TIME LEFT", Text.secs(ctl.intervalLeft())];
    }

    function gaugeField(ctl, ex) {
        return [ctl.isRunInterval(ex) ? "INTERVAL" : "ROUND", rounds(ctl)];
    }

    function lines(ctl, ex) {
        if (ex == null) { return Renderer.lines(ctl, ex); }
        var more = ctl.emomTotal() <= 0 || ctl.emomRound() < ctl.emomTotal();
        if (ctl.intervalWorking() && ctl.intervalRestSec() > 0) {
            return ["Next: " + ctl.restLabel(ex), ctl.restValue(ex)];
        }
        if (more) { return ["Next: " + ctl.workLabel(ex), ctl.workValue(ex)]; }
        return Renderer.lines(ctl, ex);
    }
}
