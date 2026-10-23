using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Lang;

// After "Activity Saved": Garmin's post-save list (photographed on the
// athlete's fenix 9 Pro, 2026-10-23) — Done, All Stats, then a row per page
// the package keeps, each with its headline number in a column left of the
// rule. START on Done (or BACK) leaves the app; on a row it opens the All
// Stats loop at that page, and BACK there comes back here.
//
//   Done             the check; the sync's state below it
//   All Stats        the time
//   Training Effect  the aerobic TE, its benefit below
//   Heart Rate       the average, the max below
//   Sets             the sets logged (Exercises when none were)
class SummaryListView extends Ui.View {

    hidden var _ctl;
    hidden var _g;
    hidden var _focus = 0;
    hidden var _pages;      // the All Stats loop's pages, from a SummaryView

    function initialize(ctl) {
        View.initialize();
        _ctl = ctl;
        _pages = SummaryView.pagesFor(ctl);
    }

    function onLayout(dc) {
        _g = new Grid(dc);
        Text.init(_g);
    }

    function onHide() { NativeList.release(); Native.releaseHints(); }

    hidden function hasPage(id) {
        for (var i = 0; i < _pages.size(); i += 1) {
            if (_pages[i][0] == id) { return true; }
        }
        return false;
    }

    // Built per frame: every value is in the controller's memory, and the
    // Done row follows the upload as it answers.
    function rows() {
        var out = [[:done, "Done", syncText(), Rez.Drawables.GmCheck]];
        out.add([:summary, "All Stats", null, Text.mmss(_ctl.elapsedSec())]);
        var te = _ctl.trainingEffect();
        if (te != null && hasPage(:te)) {
            out.add([:te, "Training Effect", SummaryView.benefit(te.toFloat())[0],
                     te.toFloat().format("%.1f")]);
        }
        if (hasPage(:hr)) {
            var avg = _ctl.avgHR();
            var max = _ctl.peakHR();
            out.add([:hr, "Heart Rate", (max != null) ? ("Max. " + max.toString()) : null,
                     (avg != null) ? avg.toString() : "--"]);
        }
        if (hasPage(:exercises)) {
            var n = _ctl.totalSetsLogged();
            out.add([:exercises, (n > 0) ? "Sets" : "Exercises", null,
                     (n > 0) ? n.toString() : _ctl.session().exercises().size().toString()]);
        }
        return out;
    }

    hidden function syncText() {
        if (DemoSession.enabled()) { return "Demo - not saved"; }
        if (_ctl.lastError() != null) { return _ctl.lastError(); }
        var ok = _ctl.uploadOk();
        if (ok == null) { return "Syncing..."; }
        return ok ? "Synced" : "Sync failed - will retry";
    }

    function move(d) {
        var n = rows().size();
        _focus = ((_focus + d) % n + n) % n;
        Ui.requestUpdate();
    }

    function focused() { return rows()[_focus][0]; }

    function onUpdate(dc) {
        try { draw(dc); } catch (e) { Clip.drawError(dc, "saved", e); }
    }

    hidden function draw(dc) {
        Native.clear(dc);
        if (_g == null) { _g = new Grid(dc); Text.init(_g); }
        var g = _g;
        var rs = rows();
        if (_focus >= rs.size()) { _focus = rs.size() - 1; }
        // Above Done, the session it was.
        if (_focus == 0) {
            var s = _ctl.session();
            Native.fitted(dc, g.cx, (g.h * 22) / 100, Text.lineBold(), s.archetypeName(),
                          Gfx.COLOR_WHITE, (g.w * 60) / 100);
        }
        NativeList.draw(dc, g, rs, _focus, Theme.sessionAccent(_ctl.session()), 0);
        Native.hint(dc, :start);
    }
}

class SummaryListDelegate extends Ui.BehaviorDelegate {

    hidden var _view;
    hidden var _ctl;

    function initialize(view, ctl) {
        BehaviorDelegate.initialize();
        _view = view;
        _ctl = ctl;
    }

    function onNextPage()     { _view.move(1);  return true; }
    function onPreviousPage() { _view.move(-1); return true; }
    function onBack()         { $.leaveSummary(_ctl); return true; }
    function onTap(evt)       { return true; }

    function onSelect() {
        var id = _view.focused();
        if (id == :done) { $.leaveSummary(_ctl); return true; }
        var sv = new SummaryView(_ctl);
        sv.show(id);
        Ui.pushView(sv, new SummaryDelegate(sv, _ctl), Ui.SLIDE_LEFT);
        return true;
    }
}

// Leave the app. An upload still in flight would die with it: buffer it for
// the next open (the server dedups a repeat by the workout's id).
function leaveSummary(ctl) {
    try { ctl.parkPendingUpload(); } catch (e) {}
    Toybox.System.exit();
}
