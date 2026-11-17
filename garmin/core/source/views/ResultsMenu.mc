using Toybox.WatchUi as Ui;
using Toybox.Lang;

// Save, on a test day: the standards the session tested, each with what the
// watch captured — select one to enter or correct it (the reps of a timed
// step are the athlete's count; the watch cannot see them) — then Save
// results or Not a test. The answer rides in the upload (`standardResults`),
// and the server makes each a result only then (src/standard_results.py);
// without an answer they wait on the phone and the web. BACK resumes, as the
// stop menu does.
//
// The steps whose reps the athlete counts (a step's `logs`: a timed
// kettlebell set's cadence) are listed too, after the tests; on a day with
// counts and no test there is just Save.
const COUNT_ID = 1000;     // a count step's item id: COUNT_ID + its index

function openResultsMenu(ctl, view) {
    var m = new Ui.Menu2({ :title => "Results" });
    var steps = ctl.testSteps();
    var counts = ctl.countSteps();
    for (var i = 0; i < steps.size(); i += 1) {
        var ex = steps[i];
        m.addItem(new Ui.MenuItem(ex.standard()["name"], $.resultLabel(ctl, ex), i, {}));
    }
    for (var i = 0; i < counts.size(); i += 1) {
        m.addItem(new Ui.MenuItem(counts[i].name(), $.countLabel(ctl, counts[i]), COUNT_ID + i, {}));
    }
    if (steps.size() > 0) {
        m.addItem(new Ui.IconMenuItem("Save results", null, :save, Native.icon(Rez.Drawables.GmSave), {}));
        m.addItem(new Ui.MenuItem("Not a test", "Save the workout only", :dismiss, {}));
    } else {
        m.addItem(new Ui.IconMenuItem("Save", null, :saveonly, Native.icon(Rez.Drawables.GmSave), {}));
    }
    Ui.switchToView(m, new ResultsMenuDelegate(ctl, view, steps, counts), Ui.SLIDE_LEFT);
}

// "84 reps", or what is still to enter.
function countLabel(ctl, ex) {
    var v = ctl.countValue(ex);
    if (v == null) { return "Enter reps"; }
    return v.toString() + ((v == 1) ? " rep" : " reps");
}

// "7:32", or what is still to enter.
function resultLabel(ctl, ex) {
    var t = ctl.resultText(ex);
    if (t != null) { return t; }
    var kind = ex.standard()["result"];
    if (kind == null) { return "Nothing to enter"; }
    if (kind.equals("duration")) { return "Enter the time"; }
    if (kind.equals("hold")) { return "Enter the hold"; }
    return "Enter " + kind;
}

class ResultsMenuDelegate extends Ui.Menu2InputDelegate {

    hidden var _ctl;
    hidden var _view;
    hidden var _steps;
    hidden var _counts;

    function initialize(ctl, view, steps, counts) {
        Menu2InputDelegate.initialize();
        _ctl = ctl;
        _view = view;
        _steps = steps;
        _counts = counts;
    }

    function onSelect(item) {
        var id = item.getId();
        if (id == :save || id == :dismiss || id == :saveonly) {
            try {
                if (id != :saveonly) { _ctl.setResultDecision((id == :save) ? "save" : "dismiss"); }
                _ctl.finish();
            } catch (e) { _view.fail("results", e); }
            Ui.popView(Ui.SLIDE_DOWN);
            return;
        }
        if (id instanceof Lang.Number && id >= COUNT_ID) {
            var at = id - COUNT_ID;
            try { $.editCount(_ctl, _counts[at], item); } catch (e) { _view.fail("count", e); }
            return;
        }
        try { $.editResult(_ctl, _steps[id], item); } catch (e) { _view.fail("result", e); }
    }

    function onBack() {
        _ctl.resume();
        Ui.popView(Ui.SLIDE_DOWN);
    }
}
