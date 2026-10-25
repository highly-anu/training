using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
import Rez.Styles;

// "Skip Zone 2 Run?" — asked when LAP would leave a step that has not finished
// on its own: a timed block with time left, an interval block with rounds to
// go, a distance short of its target (Renderer.lapSkipsEarly). The Connect IQ
// guidelines keep confirmations for the friction a big decision needs; losing
// the rest of a step to a brushed button is one. A step that ends only on LAP
// still ends at once, and Skip in the hold-UP menu (already two presses) never
// asks.
//
// START skips; DOWN, or BACK/LAP again, keeps the step, so a double press of LAP
// skips nothing. If the step ends by itself while this is up, the answer skips
// nothing either: the step it asked about is already over.
class SkipConfirmView extends Ui.View {

    hidden var _ex;

    function initialize(ex) {
        View.initialize();
        _ex = ex;
    }

    function onLayout(dc) {
        setLayout(Rez.Layouts.SkipConfirm(dc));
        var body = findDrawableById("body");
        if (body != null && _ex != null) { (body as Ui.TextArea).setText("Skip " + _ex.name() + "?"); }
    }

    function onUpdate(dc) {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        View.onUpdate(dc);
    }
}

class SkipConfirmDelegate extends Ui.InputDelegate {

    hidden var _ctl;
    hidden var _view;
    hidden var _ex;

    function initialize(ctl, view, ex) {
        InputDelegate.initialize();
        _ctl = ctl;
        _view = view;
        _ex = ex;
    }

    function onKey(evt) {
        var k = evt.getKey();
        if (k == Styles.confirmation_input__confirm.button) {
            Ui.popView(Ui.SLIDE_IMMEDIATE);
            try {
                if (_ctl.currentExercise() == _ex) { _ctl.skip(); }
                _view.bindRenderer();
                StepAlert.flush(_ctl);
                Ui.requestUpdate();
            } catch (e) { _view.fail("skip", e); }
            return true;
        }
        if (k == Styles.confirmation_input__reject.button || k == Ui.KEY_ESC) {
            Ui.popView(Ui.SLIDE_IMMEDIATE);
        }
        return true;
    }

    // A tap answers nothing, as on the Discard page.
    function onTap(evt) { return true; }
}
