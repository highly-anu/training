using Toybox.WatchUi as Ui;

// hold UP while recording: Stop Workout, Skip, Set Next, Edit Set.
class WorkoutMenuDelegate extends Ui.Menu2InputDelegate {

    hidden var _ctl;
    hidden var _view;

    function initialize(ctl, view) {
        Menu2InputDelegate.initialize();
        _ctl = ctl;
        _view = view;
    }

    function onSelect(item) {
        var id = item.getId();
        try {
            if (id == :stop) {
                Ui.popView(Ui.SLIDE_IMMEDIATE);
                $.openStopMenu(_ctl, _view);
                return;
            }
            if (id == :edit) {
                Ui.popView(Ui.SLIDE_IMMEDIATE);
                $.editLastSet(_ctl);
                return;
            }
            if (id == :next) {
                Ui.popView(Ui.SLIDE_IMMEDIATE);
                $.editNextSet(_ctl);
                return;
            }
            if (id == :metronome) {
                _ctl.toggleMetronome();
                return;   // a toggle stays in the menu, as Garmin's do
            }
            if (id == :skip) {
                _ctl.skip();
                _view.bindRenderer();
                Ui.popView(Ui.SLIDE_RIGHT);
                StepAlert.flush(_ctl);
                return;
            }
        } catch (e) { _view.fail("menu", e); }
        Ui.popView(Ui.SLIDE_RIGHT);
    }

    function onBack() { Ui.popView(Ui.SLIDE_RIGHT); }
}

// Resume / Save / Discard. Save ends the session; the workout screen beneath sees
// it is complete once this menu pops and hands over to the summary. Discard asks
// first, with Garmin's own delete confirmation. BACK means Resume.
class StopMenuDelegate extends Ui.Menu2InputDelegate {

    hidden var _ctl;
    hidden var _view;

    function initialize(ctl, view) {
        Menu2InputDelegate.initialize();
        _ctl = ctl;
        _view = view;
    }

    function onSelect(item) {
        var id = item.getId();
        if (id == :discard) {
            var cv = new DiscardConfirmView();
            Ui.pushView(cv, new DiscardConfirmDelegate(_ctl), Ui.SLIDE_IMMEDIATE);
            return;
        }
        try {
            if (id == :save) { _ctl.finish(); } else { _ctl.resume(); }
        } catch (e) { _view.fail("stop", e); }
        Ui.popView(Ui.SLIDE_DOWN);
    }

    function onBack() {
        _ctl.resume();
        Ui.popView(Ui.SLIDE_DOWN);
    }
}
