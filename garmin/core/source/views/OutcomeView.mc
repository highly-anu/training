using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.System;
using Toybox.Timer;
using Toybox.Lang;

// What the watch shows between the stop menu and what follows it, as Garmin's
// own activities do (photographed on the athlete's fenix 9 Pro, 2026-10-23):
//
//   Save     "Saving" while an arc sweeps the bezel, then "Activity Saved" in a
//            green ring, then the post-save list (SummaryListView)
//   Discard  "Discarding" while a red arc sweeps it, then "Activity Discarded"
//            in a green ring, then the app closes
//
// The save and the discard have already happened when this shows (the
// recording's save() returns before the menu pops); the sweep is the watch's
// pacing, not a progress bar. A failed save says so in red instead. Any button
// skips ahead. The workout's own timers are stopped by now, so the one this
// view runs is free.
class OutcomeView extends Ui.View {

    const SWEEP_MS = 1200;
    const HOLD_MS  = 1400;
    const FRAME_MS = 50;

    hidden var _ctl;
    hidden var _kind;       // :saved | :discarded
    hidden var _t0;
    hidden var _timer;
    hidden var _left = false;

    function initialize(ctl, kind) {
        View.initialize();
        _ctl = ctl;
        _kind = kind;
    }

    function onShow() {
        _t0 = System.getTimer();
        try {
            if (_timer == null) { _timer = new Timer.Timer(); }
            _timer.start(method(:onFrame), FRAME_MS, true);
        } catch (e) {
            // No timer to be had: go straight on rather than sit here.
            _timer = null;
            leave();
        }
    }

    function onHide() { stop(); }

    hidden function stop() {
        if (_timer != null) { try { _timer.stop(); } catch (e) {} }
    }

    function onFrame() as Void {
        if (System.getTimer() - _t0 >= SWEEP_MS + HOLD_MS) { leave(); return; }
        Ui.requestUpdate();
    }

    // On to the post-save list, or out of the app after a discard.
    function leave() {
        if (_left) { return; }
        _left = true;
        stop();
        if (_kind == :discarded) { System.exit(); }
        var lv = new SummaryListView(_ctl);
        Ui.switchToView(lv, new SummaryListDelegate(lv, _ctl), Ui.SLIDE_UP);
    }

    hidden function failed() {
        var e = _ctl.lastError();
        return _kind == :saved && e != null && e.find("save") == 0;
    }

    function onUpdate(dc) {
        try { draw(dc); } catch (e) { Clip.drawError(dc, "outcome", e); }
    }

    hidden function draw(dc) {
        Native.clear(dc);
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        var r = cx - (w * 3) / 100;
        var pen = (w * 3) / 100;
        if (pen < 4) { pen = 4; }
        var t = System.getTimer() - _t0;
        var discard = _kind == :discarded;
        dc.setPenWidth(pen);
        if (t < SWEEP_MS) {
            // The sweep: clockwise from 12 o'clock.
            var deg = (360 * t) / SWEEP_MS;
            if (deg > 0) {
                dc.setColor(discard ? Native.Z5 : Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
                dc.drawArc(cx, cy, r, Gfx.ARC_CLOCKWISE, 90, 90 - deg);
            }
            Native.text(dc, cx, cy, Text.line(), discard ? "Discarding" : "Saving",
                        Gfx.COLOR_WHITE);
            return;
        }
        var bad = failed();
        dc.setColor(bad ? Native.Z5 : Native.GOOD, Gfx.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, r);
        var title;
        if (discard) { title = "Activity\nDiscarded"; }
        else if (bad) { title = "Activity\nNot Saved"; }
        else if (DemoSession.enabled()) { title = "Demo\nEnded"; }
        else { title = "Activity\nSaved"; }
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy, Text.line(), title, Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }
}

class OutcomeDelegate extends Ui.BehaviorDelegate {

    hidden var _view;

    function initialize(view) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onKey(evt) { _view.leave(); return true; }
    function onTap(evt) { return true; }
}
