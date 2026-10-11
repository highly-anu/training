using Toybox.Lang;

// The session as Garmin's workout steps: each exercise a block of sets, each set
// followed by its rest, the way the watch's own workout list reads
// ("Now: 2/5 Sets" / "Back Squat" / "3 Reps @ 110 kg" / "Rest" / "3:00").
//
// Pure functions over the session and the controller's progress, shared by the
// workout's step page, its "Next:" line and the menus that preview a session.
module Steps {

    // Exercises counted in sets, each followed by a rest.
    function isSetBased(ex) {
        if (ex == null) { return false; }
        return ex.isTemplate("sets") || ex.isTemplate("hold");
    }

    // Short carries arrive in metres and are counted as laps.
    function isShortDistance(ex) {
        return ex != null && ex.isTemplate("distance")
            && ex.distanceM() != null && ex.distanceKm() == null;
    }

    function setCount(ex) {
        if (ex == null) { return 1; }
        if (isSetBased(ex) || isShortDistance(ex)) {
            var n = ex.sets();
            return (n != null && n > 0) ? n : 1;
        }
        return 1;
    }

    // Rest after each set; 0 for exercises that are not set-based.
    function restSec(ex, modalityId) {
        if (!isSetBased(ex)) { return 0; }
        var r = ex.restSeconds();
        if (r == null) { r = Config.defaultRestSec(modalityId); }
        return (r == null || r < 0) ? 0 : r;
    }

    // A load as the athlete picks the bells up: "2x24" for a double, else "24".
    // Weights are per bell, as the server prescribes them.
    function loadText(ex, w) {
        var b = (ex != null) ? ex.bells() : 1;
        return (b > 1) ? (b.toString() + "x" + Text.kg(w)) : Text.kg(w);
    }

    // Both bells together: 48 for 2x24.
    function totalKg(ex, w) {
        var b = (ex != null) ? ex.bells() : 1;
        return w.toFloat() * b;
    }

    // One set's (or one step's) prescription: "3 Reps @ 110 kg", "5 Reps @ 2x24 kg",
    // "Hold :30", "20:00".
    function prescription(ex) { return describe(ex, false); }

    // The same for what comes next (the step page and the "Next:" line), where a
    // double's load reads as the total: "5 Reps @ 48 kg".
    function preview(ex) { return describe(ex, true); }

    function describe(ex, total) {
        if (ex == null) { return ""; }
        var s = ex.slotType();
        var w = ex.weightKg();
        var at = (w != null) ? (" @ " + (total ? Text.kg(totalKg(ex, w)) : loadText(ex, w)) + " kg") : "";
        if (s.equals("sets_reps")) {
            var reps = ex.reps();
            return ((reps != null) ? reps.toString() : "?") + " Reps" + at;
        }
        if (s.equals("static_hold")) {
            var h = ex.holdSeconds();
            return "Hold " + Text.secs((h != null) ? h : 30) + at;
        }
        if (s.equals("distance")) {
            if (ex.distanceKm() != null) { return Text.kg(ex.distanceKm()) + " km" + packText(ex); }
            if (ex.distanceM() != null)  { return ex.distanceM().toString() + " m" + at; }
        }
        if (s.equals("emom")) {
            var rd = ex.targetRounds();
            var ws = ex.workSec();
            var line = (rd != null) ? (rd.toString() + " x ") : "";
            line += (ws != null && ws > 0) ? Text.mmss(ws) : "EMOM";
            if (ex.targetRpm() != null) { return line + " @ " + ex.targetRpm().toString() + " RPM"; }
            var z = ex.zoneLower();
            if (z != null) { return line + "  " + zoneText(ex); }
            var ir = ex.intervalRestSec();
            if (ir != null && ir > 0) { line += " / " + Text.mmss(ir); }
            return line + at;
        }
        if (s.equals("amrap")) {
            var tm = ex.timeMinutes();
            return ((tm != null) ? (tm.toString() + " min ") : "") + "AMRAP";
        }
        if (s.equals("for_time")) {
            var tr = ex.targetRounds();
            return ((tr != null) ? (tr.toString() + " Rounds ") : "") + "for time";
        }
        var mins = ex.durationMinutes();
        if (mins != null) {
            var z = ex.zoneLower();
            return Text.mmss(mins * 60) + ((z != null) ? ("  Z" + z.toString()) : "");
        }
        var d = ex.loadDescription();
        return (d != null) ? d : "";
    }

    // "Z3-4" / "Z2".
    function zoneText(ex) {
        var z = ex.zoneLower();
        if (z == null) { return ""; }
        var hi = ex.zoneUpper();
        return "Z" + z.toString() + ((hi != null && hi != z) ? ("-" + hi.toString()) : "");
    }

    // An interval block's two rows: [work title, work value], [rest title, rest value]
    // (the rest row null when the block has no rest).
    function intervalRows(ex, ctl) {
        var ws = ex.workSec();
        var work = (ws != null && ws > 0) ? Text.mmss(ws) : "";
        if (ex.targetRpm() != null) { work += "  " + ex.targetRpm().toString() + " RPM"; }
        else if (ex.zoneLower() != null) { work += "  " + zoneText(ex); }
        var ir = ex.intervalRestSec();
        var rest = null;
        if (ir != null && ir > 0) {
            var label = ctl.restLabel(ex);
            rest = [label, (ex.restUntilHr() != null) ? ("until HR " + ex.restUntilHr().toString())
                                                      : Text.mmss(ir)];
        }
        return [[ex.name(), work], rest];
    }

    function packText(ex) {
        var p = ex.packLoadKg();
        return (p != null) ? ("  pack " + Text.kg(p) + " kg") : "";
    }

    // The menus' one-line description of a whole exercise: the server's own
    // "5x3 @ 110 kg" when it sent one.
    function overview(ex) {
        var d = ex.loadDescription();
        if (d != null) { return d; }
        var n = setCount(ex);
        return (isSetBased(ex) && n > 1) ? (n.toString() + " x " + prescription(ex)) : prescription(ex);
    }

    // ── the step list ────────────────────────────────────────────────────────────
    //
    // Rows are [kind, title, value, state, block]: kind :header (a block of sets)
    // or :step; state :done / :now / :upcoming; block the exercise's index. Returns { "rows", "current" } where
    // current is the row index of the step being worked (or rested after).

    function rows(ctl) {
        var out = [];
        var current = -1;
        var list = ctl.session().exercises();
        var cur = ctl.exerciseIndex();
        var st = ctl.state();
        var resting = (st == WorkoutController.RESTING);
        var modality = ctl.modality();
        for (var i = 0; i < list.size(); i += 1) {
            if (ctl.isFoldedComponent(i)) { continue; }
            var ex = list[i];
            var state = (i < cur || st == WorkoutController.DONE
                         || st == WorkoutController.COMPLETE) ? :done
                      : ((i == cur) ? :now : :upcoming);
            var n = setCount(ex);
            var rest = restSec(ex, modality);
            if (ex.isTemplate("interval") && ex.targetRounds() != null && ex.targetRounds() > 1) {
                // A repeat block, as Garmin lists one: work and rest rows under
                // "Now: 3/8 Repeats".
                var rn = ex.targetRounds();
                var rh = (state == :now) ? ("Now: " + ctl.emomRound().toString() + "/" + rn.toString() + " Repeats")
                       : ((state == :done) ? ("Done: " + rn.toString() + " Repeats")
                                           : ("Upcoming: " + rn.toString() + " Repeats"));
                out.add([:header, rh, null, state, i]);
                var ir2 = intervalRows(ex, ctl);
                var onRest = (state == :now) && !ctl.intervalWorking() && ir2[1] != null;
                if (state == :now && !onRest) { current = out.size(); }
                out.add([:step, ir2[0][0], ir2[0][1], state, i]);
                if (ir2[1] != null) {
                    if (onRest) { current = out.size(); }
                    out.add([:step, ir2[1][0], ir2[1][1], state, i]);
                }
                continue;
            }
            if (n > 1 || rest > 0) {
                var head;
                if (state == :now) {
                    var done = ctl.setsDoneFor(ex);
                    var at = resting ? done : done + 1;
                    if (at < 1) { at = 1; }
                    if (at > n) { at = n; }
                    head = "Now: " + at.toString() + "/" + n.toString() + " Sets";
                } else if (state == :done) {
                    head = "Done: " + n.toString() + " Sets";
                } else {
                    head = "Upcoming: " + n.toString() + " Sets";
                }
                out.add([:header, head, null, state, i]);
                if (state == :now && !resting) { current = out.size(); }
                out.add([:step, ex.name(), preview(ex), state, i]);
                if (rest > 0) {
                    if (state == :now && resting) { current = out.size(); }
                    out.add([:step, "Rest", Text.mmss(rest), state, i]);
                } else if (state == :now && resting) {
                    current = out.size() - 1;
                }
            } else {
                if (state == :now) { current = out.size(); }
                out.add([:step, ex.name(), preview(ex), state, i]);
            }
        }
        if (current < 0) { current = lastStepRow(out); }
        return { "rows" => out, "current" => current };
    }

    function lastStepRow(rs) {
        for (var i = rs.size() - 1; i >= 0; i -= 1) {
            if (rs[i][0] == :step) { return i; }
        }
        return 0;
    }
}
