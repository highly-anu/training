using Toybox.WatchUi as Ui;

// Save, on a test day: the standards the session tested, each with what the
// watch captured — select one to enter or correct it (the reps of a timed
// step are the athlete's count; the watch cannot see them) — then Save
// results or Not a test. The answer rides in the upload (`standardResults`),
// and the server makes each a result only then (src/standard_results.py);
// without an answer they wait on the phone and the web. BACK resumes, as the
// stop menu does.
function openResultsMenu(ctl, view) {
    var m = new Ui.Menu2({ :title => "Results" });
    var steps = ctl.testSteps();
    for (var i = 0; i < steps.size(); i += 1) {
        var ex = steps[i];
        m.addItem(new Ui.MenuItem(ex.standard()["name"], $.resultLabel(ctl, ex), i, {}));
    }
    m.addItem(new Ui.IconMenuItem("Save results", null, :save, Native.icon(Rez.Drawables.GmSave), {}));
    m.addItem(new Ui.MenuItem("Not a test", "Save the workout only", :dismiss, {}));
    Ui.switchToView(m, new ResultsMenuDelegate(ctl, view, steps), Ui.SLIDE_LEFT);
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

    function initialize(ctl, view, steps) {
        Menu2InputDelegate.initialize();
        _ctl = ctl;
        _view = view;
        _steps = steps;
    }

    function onSelect(item) {
        var id = item.getId();
        if (id == :save || id == :dismiss) {
            try {
                _ctl.setResultDecision((id == :save) ? "save" : "dismiss");
                _ctl.finish();
            } catch (e) { _view.fail("results", e); }
            Ui.popView(Ui.SLIDE_DOWN);
            return;
        }
        try { $.editResult(_ctl, _steps[id], item); } catch (e) { _view.fail("result", e); }
    }

    function onBack() {
        _ctl.resume();
        Ui.popView(Ui.SLIDE_DOWN);
    }
}
