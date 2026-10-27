using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Lang;
import Rez.Styles;

// "Discard?" — the Personality Library's Delete Confirmation, so it is the watch's
// own page: the red trash hint at the delete button (START), the white back
// arrow at the keep button (DOWN on a fenix 9), the body in the system font.
// Buttons come from the same selectors, so they always match the hints drawn.
class DiscardConfirmView extends Ui.View {

    function initialize() { View.initialize(); }

    function onLayout(dc) { setLayout(Rez.Layouts.DiscardConfirm(dc)); }

    function onUpdate(dc) {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        View.onUpdate(dc);
    }
}

class DiscardConfirmDelegate extends Ui.InputDelegate {

    hidden var _ctl;

    function initialize(ctl) {
        InputDelegate.initialize();
        _ctl = ctl;
    }

    // The buttons come from the same selectors as the hints, so they always match.
    // (Every product in the manifest has a button for both answers.)
    function onKey(evt) {
        var k = evt.getKey();
        if (k == Styles.confirmation_input__delete.button) {
            // As on Garmin's own stop menu: a discarded workout has no summary,
            // only "Discarding" and "Activity Discarded" before the app closes.
            _ctl.discardSession();
            var app = TrainingCompanionApp.instance();
            if (app != null) { app.activeController = null; }
            var ov = new OutcomeView(_ctl, :discarded);
            Ui.switchToView(ov, new OutcomeDelegate(ov), Ui.SLIDE_IMMEDIATE);
            return true;
        }
        if (k == Styles.confirmation_input__keep.button || k == Ui.KEY_ESC) {
            Ui.popView(Ui.SLIDE_IMMEDIATE);
        }
        return true;
    }

    // A tap answers nothing: on a sweaty wrist it must not discard a workout.
    function onTap(evt) { return true; }
}
