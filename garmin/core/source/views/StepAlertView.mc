using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Timer;

// The step alert Garmin shows when a workout step begins ("Run  8:00  Zone 3-4",
// "Recover  2:00", "Switch hands"): a full screen for a few seconds, then back to
// the data pages. Any button dismisses it and is not passed on. A new alert while
// one is up replaces its text and restarts its clock rather than stacking.
//
// One timer (the controller holds the other; the platform allows three).
module StepAlert {

    const SHOW_MS = 3000;

    var _view = null;
    var _timer = null;

    function flush(ctl) {
        var a = ctl.takeAlert();
        if (a == null) { return; }
        try {
            if (_view != null) {
                _view.set(a[0], a[1]);
            } else {
                _view = new StepAlertView(a[0], a[1]);
                Ui.pushView(_view, new StepAlertDelegate(), Ui.SLIDE_IMMEDIATE);
            }
            if (_timer == null) { _timer = new Timer.Timer(); }
            _timer.stop();
            _timer.start(new Toybox.Lang.Method(StepAlert, :expire), SHOW_MS, false);
            Ui.requestUpdate();
        } catch (e) {}
    }

    function expire() as Void { dismiss(); }

    // Pop the alert once, whichever comes first: the clock or a button.
    function dismiss() {
        if (_timer != null) { _timer.stop(); }
        if (_view == null) { return; }
        _view = null;
        Ui.popView(Ui.SLIDE_IMMEDIATE);
    }

    function showing() { return _view != null; }
}

class StepAlertView extends Ui.View {

    hidden var _title;
    hidden var _line;
    hidden var _g;

    function initialize(title, line) {
        View.initialize();
        _title = title;
        _line = line;
    }

    function set(title, line) {
        _title = title;
        _line = line;
    }

    function onLayout(dc) {
        _g = new Grid(dc);
        Text.init(_g);
    }

    function onUpdate(dc) {
        Native.clear(dc);
        if (_g == null) { _g = new Grid(dc); Text.init(_g); }
        var g = _g;
        // A white band behind the title, the watch's own alert treatment.
        var bandH = (g.h * 20) / 100;
        var by = (g.h * 42) / 100 - (bandH / 2);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.fillRectangle(0, by, g.w, bandH);
        Native.fitted(dc, g.cx, (g.h * 42) / 100, Text.lineBold(), _title, Gfx.COLOR_BLACK, (g.w * 80) / 100);
        if (_line != null) {
            Native.fitted(dc, g.cx, (g.h * 62) / 100, Text.line(), _line, Gfx.COLOR_WHITE, (g.w * 80) / 100);
        }
    }
}

class StepAlertDelegate extends Ui.InputDelegate {
    function initialize() { InputDelegate.initialize(); }
    function onKey(evt)   { StepAlert.dismiss(); return true; }
    function onTap(evt)   { StepAlert.dismiss(); return true; }
}
