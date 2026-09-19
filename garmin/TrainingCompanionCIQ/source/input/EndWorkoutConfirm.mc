using Toybox.WatchUi as Ui;

// Response handler for the "End workout?" confirmation.
//
// CONFIRM_NO simply pops the confirmation — the workout view is still on the
// stack beneath it, and the recording session was never touched.
// CONFIRM_YES finishes the session (stop + save the FIT + upload) and switches
// to the completion screen, so there is no way to leave a session recording
// with no view driving it.
class EndWorkoutConfirm extends Ui.ConfirmationDelegate {

    hidden var _ctl;

    function initialize(ctl) {
        ConfirmationDelegate.initialize();
        _ctl = ctl;
    }

    function onResponse(response) {
        if (response == Ui.CONFIRM_YES) {
            _ctl.finish();
            var app = TrainingCompanionApp.instance();
            if (app != null) { app.activeController = null; }
            Ui.switchToView(new SessionCompleteView(_ctl),
                            new SessionCompleteDelegate(), Ui.SLIDE_UP);
        }
        return true;
    }
}
