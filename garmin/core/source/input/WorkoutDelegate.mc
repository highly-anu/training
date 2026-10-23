using Toybox.WatchUi as Ui;

// The workout's buttons, mapped as on Garmin's own Strength activity:
//
//   START          before the workout has begun: start it (the timer and the
//                  recording); after: pause and open the stop menu
//                  (Resume / Save / Discard)
//   BACK = LAP     end the set (then rest); during a rest, end the rest; on other
//                  slot types count a round or lap, or move to the next step
//   DOWN / UP      turn the pages; on the step page, walk the list
//   hold UP        the workout menu: Stop Workout, Skip, Set Next, Edit Set,
//                  Settings
//   BACK before the start leaves without recording anything
//
// Touch is off while recording, as on the watch's activities: a tap or a sideways
// swipe on a sweaty wrist must not pause the workout or log a set. Swipes up and
// down still turn the pages (the system maps them to DOWN/UP).
class WorkoutDelegate extends Ui.BehaviorDelegate {

    hidden var _ctl;
    hidden var _view;

    function initialize(ctl, view) {
        BehaviorDelegate.initialize();
        _ctl = ctl;
        _view = view;
    }

    function onSelect() {
        try {
            if (_ctl.state() == WorkoutController.COMPLETE) { _view.leaveIfComplete(); return true; }
            if (_ctl.isReady()) {
                _ctl.start();
                StepAlert.flush(_ctl);     // the first step's alert
                Ui.requestUpdate();
                return true;
            }
            $.openStopMenu(_ctl, _view);
        } catch (e) { _view.fail("START", e); }
        return true;
    }

    function onBack() {
        try {
            var st = _ctl.state();
            if (st == WorkoutController.COMPLETE) { _view.leaveIfComplete(); return true; }
            if (_ctl.isReady()) {
                _ctl.cancel();
                var app = TrainingCompanionApp.instance();
                if (app != null) { app.activeController = null; }
                Ui.popView(Ui.SLIDE_RIGHT);
                return true;
            }
            if (_ctl.isPaused() || st == WorkoutController.DONE) { return true; }
            if (st == WorkoutController.RESTING) {
                _ctl.skipRest();
            } else {
                var r = _view.renderer();
                if (r != null) { r.onLap(_ctl, _ctl.currentExercise()); }
            }
            _view.bindRenderer();
            StepAlert.flush(_ctl);
            Ui.requestUpdate();
        } catch (e) { _view.fail("LAP", e); }
        return true;
    }

    function onNextPage() {
        try { _view.down(); } catch (e) { _view.fail("DOWN", e); }
        return true;
    }

    function onPreviousPage() {
        try { _view.up(); } catch (e) { _view.fail("UP", e); }
        return true;
    }

    function onMenu() {
        var st = _ctl.state();
        if (st == WorkoutController.COMPLETE) { return true; }
        var m = new Ui.Menu2({ :title => "Workout" });
        if (!_ctl.isReady()) {
            m.addItem(new Ui.MenuItem("Stop Workout", null, :stop, {}));
        }
        if (st != WorkoutController.DONE && !_ctl.isReady()) {
            m.addItem(new Ui.MenuItem("Skip", skipLabel(), :skip, {}));
        }
        var ex = _ctl.currentExercise();
        if (st != WorkoutController.DONE && ex != null && ex.isTemplate("sets")) {
            m.addItem(new Ui.MenuItem("Set Next", nextLabel(), :next, {}));
        }
        if (_ctl.lastSet() != null) {
            m.addItem(new Ui.MenuItem("Edit Set", _ctl.lastSetName(), :edit, {}));
        }
        // Garmin keeps its metronome in the activity menu; ours, for paced sets,
        // with the pace itself editable beside it.
        if (st != WorkoutController.DONE && ex != null && ex.targetRpm() != null) {
            m.addItem(new Ui.MenuItem("Pace", ex.targetRpm().toString() + " RPM", :pace, {}));
            m.addItem(new Ui.ToggleMenuItem("Metronome", ex.targetRpm().toString() + " RPM",
                                            :metronome, _ctl.metronomeOn(), {}));
        }
        m.addItem(new Ui.MenuItem("Settings", "Alerts and lead-in", :settings, {}));
        Ui.pushView(m, new WorkoutMenuDelegate(_ctl, _view), Ui.SLIDE_LEFT);
        return true;
    }

    // "3 reps @ 110 kg" — what the next set will log.
    hidden function nextLabel() {
        var t = _ctl.editReps().toString() + " reps";
        if (_ctl.editWeight() != null) { t += " @ " + Text.kg(_ctl.editWeight()) + " kg"; }
        return t;
    }

    hidden function skipLabel() {
        var ex = _ctl.currentExercise();
        if (_ctl.state() == WorkoutController.RESTING && _ctl.restAdvances()) {
            var nx = _ctl.upcomingExercise();
            return (nx != null) ? ("to " + nx.name()) : null;
        }
        return (ex != null) ? ex.name() : null;
    }

    function onTap(evt) { return true; }

    function onSwipe(evt) {
        var d = evt.getDirection();
        return d == Ui.SWIPE_LEFT || d == Ui.SWIPE_RIGHT;
    }
}

// START while recording: pause, then Garmin's stop menu.
function openStopMenu(ctl, view) {
    ctl.pause();
    var m = new Ui.Menu2({ :title => "Paused" });
    m.addItem(new Ui.IconMenuItem("Resume", null, :resume, Native.icon(Rez.Drawables.GmResume), {}));
    m.addItem(new Ui.IconMenuItem("Save", null, :save, Native.icon(Rez.Drawables.GmSave), {}));
    m.addItem(new Ui.IconMenuItem("Discard", null, :discard, Native.icon(Rez.Drawables.GmDiscard), {}));
    Ui.pushView(m, new StopMenuDelegate(ctl, view), Ui.SLIDE_UP);
}
