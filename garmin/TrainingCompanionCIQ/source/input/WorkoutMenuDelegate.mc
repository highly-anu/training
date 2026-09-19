using Toybox.WatchUi as Ui;

// Hold-UP session menu.
//
// Replaces the old behaviour where a single hold-UP called finish() outright —
// one accidental long press ended the session with no confirmation and no undo.
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
        if (id == :skip) {
            _ctl.nextExercise();
            _view.bindRenderer();
        } else if (id == :lap) {
            _ctl.logRound();
        } else if (id == :end) {
            Ui.pushView(new Ui.Confirmation(Ui.loadResource(Rez.Strings.EndWorkoutQ)),
                        new EndWorkoutConfirm(_ctl), Ui.SLIDE_UP);
            return;
        }
        Ui.popView(Ui.SLIDE_DOWN);
    }

    function onBack() {
        Ui.popView(Ui.SLIDE_DOWN);
    }
}
