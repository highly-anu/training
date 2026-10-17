using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;

// One number at a time, the way Garmin's Strength edits a set: UP/DOWN change it,
// START accepts and moves to the next, BACK steps back a field and, from the first,
// leaves without saving. Three uses:
//
//   editPlan      before starting, from the workout's Steps list: this exercise's
//                 reps (or hold), weight and RPE for the whole run
//   editNextSet   hold UP > Set Next: what the next sets of this exercise log
//   editLastSet   hold UP > Edit Set: correct the set just logged
//   editPace      hold UP > Pace: the RPM a paced step and its metronome run at
//
// Fields are [id, label, value, step, lo, hi]; ids sets / reps / hold / weight /
// rpe / rpm. A double's weight is one bell's, as the server prescribes it.

function setsField(v, lo) { return ["sets", "SETS", v, 1, lo, 30]; }
function repsField(v)   { return ["reps", "REPS", v, 1, 0, 100]; }
function holdField(v)   { return ["hold", "SECONDS", v, 5, 0, 600]; }
// The step is the package's (WorkoutExercise.weightStep): kettlebells come in
// half-pood (4 kg) steps by default. A double edits the weight of one bell.
function weightField(v, ex) {
    var b = (ex != null) ? ex.bells() : 1;
    return ["weight", (b > 1) ? "KG PER BELL" : "WEIGHT KG", v.toFloat(),
            (ex != null) ? ex.weightStep() : Vocab.WEIGHT_STEP_KG, 0.0, 500.0];
}
function rpeField(v)    { return ["rpe", "RPE", v.toFloat(), 0.5, 5.0, 10.0]; }
function rpmField(v)    { return ["rpm", "RPM", v, 1, 1, 120]; }

// Reps arrive from the server as text ("5", "8-12", "max"): take the leading number.
function leadingNumber(r, dflt) {
    if (r == null) { return dflt; }
    if (r instanceof Toybox.Lang.Number) { return r; }
    if (r instanceof Toybox.Lang.Float) { return r.toNumber(); }
    var n = 0;
    var any = false;
    var str = r.toString();
    for (var i = 0; i < str.length(); i += 1) {
        var d = "0123456789".find(str.substring(i, i + 1));
        if (d == null) { break; }
        n = (n * 10) + d;
        any = true;
    }
    return any ? n : dflt;
}

function editPlan(ex, item) {
    var fs = [];
    if (Steps.isSetBased(ex) || Steps.isShortDistance(ex)) { fs.add($.setsField(Steps.setCount(ex), 1)); }
    if (ex.isTemplate("sets")) { fs.add($.repsField($.leadingNumber(ex.reps(), 8))); }
    if (ex.isTemplate("hold")) {
        fs.add($.holdField((ex.holdSeconds() != null) ? ex.holdSeconds() : 30));
    }
    if (ex.weightKg() != null) { fs.add($.weightField(ex.weightKg(), ex)); }
    if (ex.targetRpe() != null) { fs.add($.rpeField(ex.targetRpe())); }
    if (ex.targetRpm() != null) { fs.add($.rpmField(ex.targetRpm())); }
    var v = new EditSetView("Plan", ex.name(), fs, new PlanTarget(ex, item), "Plan updated");
    Ui.pushView(v, new EditSetDelegate(v), Ui.SLIDE_LEFT);
}

function editNextSet(ctl) {
    var ex = ctl.currentExercise();
    if (ex == null) { return; }
    var fs = [];
    // How many sets this exercise runs to: never fewer than the next one.
    if (Steps.isSetBased(ex) || Steps.isShortDistance(ex)) {
        var done = ctl.currentSetCount();
        fs.add($.setsField(Steps.setCount(ex), done + 1));
    }
    fs.add($.repsField(ctl.editReps()));
    if (ctl.editWeight() != null) { fs.add($.weightField(ctl.editWeight(), ex)); }
    if (ctl.editRpe() != null) { fs.add($.rpeField(ctl.editRpe())); }
    var n = ctl.currentSetCount() + 1;
    var v = new EditSetView("Next: set " + n.toString(), ex.name(), fs, new WorkingTarget(ctl, ex), "Next sets updated");
    Ui.pushView(v, new EditSetDelegate(v), Ui.SLIDE_LEFT);
}

// The pace of the step being worked: the metronome, the RPM field and the step
// text all read the edited value from the next beat on.
function editPace(ctl) {
    var ex = ctl.currentExercise();
    if (ex == null || ex.targetRpm() == null) { return; }
    var v = new EditSetView("Pace", ex.name(), [$.rpmField(ex.targetRpm())],
                            new WorkingTarget(ctl, ex), "Pace updated");
    Ui.pushView(v, new EditSetDelegate(v), Ui.SLIDE_LEFT);
}

// Results > a test step: what it produced, entered or corrected — the reps a
// timed step's athlete counted, a clock as minutes and seconds.
function editResult(ctl, ex, item) {
    var kind = ex.standard()["result"];
    var v = ctl.resultValue(ex);
    var fs;
    if (kind != null && kind.equals("duration")) {
        var sec = (v != null) ? v : 0;
        fs = [["min", "MIN", sec / 60, 1, 0, 300], ["sec", "SEC", sec % 60, 1, 0, 59]];
    } else if (kind != null && kind.equals("distance")) {
        fs = [["km", "KM", (v != null) ? v.toFloat() : 0.0, 0.01, 0.0, 100.0]];
    } else if (kind != null && kind.equals("hold")) {
        fs = [$.holdField((v != null) ? v : 0)];
    } else {
        var label = (kind != null && kind.equals("rounds")) ? "ROUNDS" : "REPS";
        fs = [["reps", label, (v != null) ? v : 0, 1, 0, 999]];
    }
    var view = new EditSetView("Result", ex.standard()["name"], fs, new ResultTarget(ctl, ex, item), "Result kept");
    Ui.pushView(view, new EditSetDelegate(view), Ui.SLIDE_LEFT);
}

function editLastSet(ctl) {
    var set = ctl.lastSet();
    if (set == null) { return; }
    var ex = ctl.currentExercise();
    var hold = ex != null && ex.name().equals(ctl.lastSetName()) && ex.isTemplate("hold");
    var fs = [];
    if (set["reps"] != null) { fs.add(hold ? $.holdField(set["reps"]) : $.repsField(set["reps"])); }
    var same = ex != null && ex.name().equals(ctl.lastSetName());
    if (set["weightKg"] != null) { fs.add($.weightField(set["weightKg"], same ? ex : null)); }
    var rpe = set["rpe"];
    if (rpe == null && ex != null && ex.name().equals(ctl.lastSetName())) { rpe = ex.targetRpe(); }
    if (rpe != null) { fs.add($.rpeField(rpe)); }
    var v = new EditSetView("Set " + ctl.lastSetNumber().toString(), ctl.lastSetName(), fs,
                            new LastSetTarget(ctl), "Set updated");
    Ui.pushView(v, new EditSetDelegate(v), Ui.SLIDE_LEFT);
}

class PlanTarget {
    hidden var _ex;
    hidden var _item;
    function initialize(ex, item) { _ex = ex; _item = item; }
    function applyEdit(vals) {
        _ex.setPlan(vals);
        if (_item != null) { _item.setSubLabel(Steps.overview(_ex)); }
    }
}

class WorkingTarget {
    hidden var _ctl;
    hidden var _ex;
    function initialize(ctl, ex) { _ctl = ctl; _ex = ex; }
    function applyEdit(vals) {
        if (vals.hasKey("sets")) { _ex.setPlan({ "sets" => vals["sets"] }); }
        if (vals.hasKey("rpm"))  { _ex.setPlan({ "rpm" => vals["rpm"] }); }
        _ctl.setWorking(vals);
    }
}

class ResultTarget {
    hidden var _ctl;
    hidden var _ex;
    hidden var _item;
    function initialize(ctl, ex, item) { _ctl = ctl; _ex = ex; _item = item; }
    function applyEdit(vals) {
        var v;
        if (vals.hasKey("min"))       { v = vals["min"] * 60 + vals["sec"]; }
        else if (vals.hasKey("km"))   { v = vals["km"]; }
        else if (vals.hasKey("hold")) { v = vals["hold"]; }
        else                          { v = vals["reps"]; }
        _ctl.setResult(_ex, v);
        if (_item != null) { _item.setSubLabel($.resultLabel(_ctl, _ex)); }
    }
}

class LastSetTarget {
    hidden var _ctl;
    function initialize(ctl) { _ctl = ctl; }
    function applyEdit(vals) {
        var set = _ctl.lastSet();
        if (set == null) { return; }
        var reps = vals.hasKey("reps") ? vals["reps"] : (vals.hasKey("hold") ? vals["hold"] : set["reps"]);
        var w = vals.hasKey("weight") ? vals["weight"] : set["weightKg"];
        var rpe = vals.hasKey("rpe") ? vals["rpe"] : set["rpe"];
        _ctl.editLastSet(reps, w, rpe);
    }
}

class EditSetView extends Ui.View {

    hidden var _g;
    hidden var _heading;
    hidden var _title;
    hidden var _fields;
    hidden var _target;
    hidden var _done;
    hidden var _i;

    function initialize(heading, title, fields, target, doneMsg) {
        View.initialize();
        _heading = heading;
        _title = title;
        _fields = fields;
        _target = target;
        _done = doneMsg;
        _i = 0;
    }

    function onLayout(dc) {
        _g = new Grid(dc);
        Text.init(_g);
    }

    function step(d) {
        if (_fields.size() == 0) { return; }
        var f = _fields[_i];
        var v = f[2] + (d * f[3]);
        if (v < f[4]) { v = f[4]; }
        if (v > f[5]) { v = f[5]; }
        f[2] = v;
        Ui.requestUpdate();
    }

    // START: next field, or save and close after the last.
    function accept() {
        if (_i + 1 < _fields.size()) { _i += 1; Ui.requestUpdate(); return; }
        if (_fields.size() > 0) {
            var vals = {};
            for (var k = 0; k < _fields.size(); k += 1) {
                var f = _fields[k];
                vals[f[0]] = isCount(f) ? f[2].toNumber() : f[2];
            }
            try { _target.applyEdit(vals); Native.toast(_done, true); } catch (e) {}
        }
        Ui.popView(Ui.SLIDE_RIGHT);
    }

    hidden function isCount(f) {
        return f[0].equals("sets") || f[0].equals("reps") || f[0].equals("hold") || f[0].equals("rpm")
            || f[0].equals("min") || f[0].equals("sec");
    }

    // BACK: previous field, or leave without saving.
    function back() {
        if (_i > 0) { _i -= 1; Ui.requestUpdate(); return; }
        Ui.popView(Ui.SLIDE_RIGHT);
    }

    function onUpdate(dc) {
        try { draw(dc); } catch (e) { Clip.drawError(dc, "edit", e); }
    }

    hidden function draw(dc) {
        Native.clear(dc);
        if (_g == null) { _g = new Grid(dc); Text.init(_g); }
        var g = _g;
        Native.text(dc, g.cx, (g.h * 17) / 100, Text.small(), _heading, Native.DIM);
        Native.fitted(dc, g.cx, (g.h * 25) / 100, Text.lineBold(), _title, Gfx.COLOR_WHITE, (g.w * 66) / 100);
        if (_fields.size() == 0) {
            Native.text(dc, g.cx, g.cy, Text.line(), "Nothing to set", Gfx.COLOR_WHITE);
            return;
        }
        var f = _fields[_i];
        Native.text(dc, g.cx, (g.h * 355) / 1000, Text.fieldLabel(), f[1], Gfx.COLOR_WHITE);

        var v = isCount(f) ? f[2].toNumber().toString() : Text.kg(f[2]);
        var vy = (g.h * 545) / 1000;
        Native.text(dc, g.cx, vy, Text.bigNum(), v, Gfx.COLOR_WHITE);

        // Up and down carets, as on the watch's number pickers.
        var c = (g.w * 4) / 100;
        var gap = (g.h * 14) / 100;
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.fillPolygon([[g.cx - c, vy - gap], [g.cx + c, vy - gap], [g.cx, vy - gap - c]]);
        dc.fillPolygon([[g.cx - c, vy + gap], [g.cx + c, vy + gap], [g.cx, vy + gap + c]]);

        // Which field of how many.
        if (_fields.size() > 1) {
            var r = (g.w * 1) / 100 + 2;
            var x0 = g.cx - ((_fields.size() - 1) * r * 2);
            dc.setPenWidth(2);
            for (var k = 0; k < _fields.size(); k += 1) {
                var x = x0 + (k * r * 4);
                if (k == _i) { dc.fillCircle(x, (g.h * 78) / 100, r); }
                else { dc.drawCircle(x, (g.h * 78) / 100, r); }
            }
        }
        Native.hint(dc, :start);
    }
}

class EditSetDelegate extends Ui.BehaviorDelegate {
    hidden var _view;
    function initialize(view) {
        BehaviorDelegate.initialize();
        _view = view;
    }
    function onPreviousPage() { _view.step(1);  return true; }
    function onNextPage()     { _view.step(-1); return true; }
    function onSelect()       { _view.accept(); return true; }
    function onBack()         { _view.back();   return true; }
    function onMenu()         { return true; }
    function onTap(evt)       { return true; }
}
