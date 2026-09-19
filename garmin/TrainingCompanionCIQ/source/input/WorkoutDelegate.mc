using Toybox.WatchUi as Ui;

// The unified input model for all nine workout screens.
//
// Buttons stay authoritative — they work sweaty, gloved and in motion — and touch
// adds the affordances that are genuinely better indoors.
//
//   SELECT / tap   the screen's ONE primary action, never overloaded
//   UP / DOWN      adjust the focused field where there is one, else page
//   swipe up/down  always pages Exercise <-> Progress <-> Metrics
//   swipe left     next exercise (the device leaves swipeLeft unmapped)
//   BACK / swipe right   end-workout confirmation while recording
//   hold UP        session menu
//
// Spending UP/DOWN on editing is what makes an inline set logger possible: a
// heavy set gets logged without pushing a separate view.
class WorkoutDelegate extends Ui.BehaviorDelegate {

    hidden var _ctl;
    hidden var _view;

    function initialize(ctl, view) {
        BehaviorDelegate.initialize();
        _ctl = ctl;
        _view = view;
    }

    function onSelect() {
        if (_ctl.state() == WorkoutController.RESTING) {
            _ctl.skipRest();
            Ui.requestUpdate();
            return true;
        }
        var r = _view.renderer();
        var ex = _ctl.currentExercise();
        if (r != null) { r.onSelect(_ctl, ex); }
        _view.bindRenderer();
        maybeComplete();
        Ui.requestUpdate();
        return true;
    }

    function onNextPage() {
        if (isEditing()) { _ctl.adjustEdit(-1); Ui.requestUpdate(); return true; }
        _view.setPage(_view.page() + 1);
        return true;
    }

    function onPreviousPage() {
        if (isEditing()) { _ctl.adjustEdit(1); Ui.requestUpdate(); return true; }
        _view.setPage(_view.page() - 1);
        return true;
    }

    // Touch. The device maps tap/swipeUp/swipeDown/swipeRight at system level;
    // swipeLeft carries no behavior id, so it is ours to claim.
    function onSwipe(evt) {
        var d = evt.getDirection();
        if (d == Ui.SWIPE_LEFT) {
            _ctl.nextExercise();
            _view.bindRenderer();
            maybeComplete();
            Ui.requestUpdate();
            return true;
        }
        return false;   // let the system map the rest to page/back behaviors
    }

    // Tapping a value focuses it, replacing the old "BACK cycles the edit field",
    // which fought the platform's back semantics.
    function onTap(evt) {
        if (isEditing() && _ctl.editFieldCount() > 1) {
            _ctl.cycleEditField();
            Ui.requestUpdate();
            return true;
        }
        return onSelect();
    }

    // BACK never silently abandons a recording session.
    function onBack() {
        confirmEnd();
        return true;
    }

    function onMenu() {
        var m = new Ui.Menu2({ :title => "Session" });
        m.addItem(new Ui.MenuItem("Skip exercise", null, :skip, {}));
        m.addItem(new Ui.MenuItem("Mark lap", null, :lap, {}));
        m.addItem(new Ui.MenuItem("End workout", null, :end, {}));
        Ui.pushView(m, new WorkoutMenuDelegate(_ctl, _view), Ui.SLIDE_UP);
        return true;
    }

    hidden function confirmEnd() {
        Ui.pushView(new Ui.Confirmation(Ui.loadResource(Rez.Strings.EndWorkoutQ)),
                    new EndWorkoutConfirm(_ctl), Ui.SLIDE_UP);
    }

    hidden function isEditing() {
        if (_ctl.state() != WorkoutController.ACTIVE) { return false; }
        var r = _view.renderer();
        return r != null && r.editable(_ctl, _ctl.currentExercise());
    }

    hidden function maybeComplete() {
        if (_ctl.state() == WorkoutController.COMPLETE) {
            var app = TrainingCompanionApp.instance();
            if (app != null) { app.activeController = null; }
            Ui.switchToView(new SessionCompleteView(_ctl), new SessionCompleteDelegate(),
                            Ui.SLIDE_UP);
        }
    }
}
