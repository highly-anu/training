using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Timer;
using Toybox.Lang;

// First-run pairing. Mints a pairing code, shows it (and — TODO — a QR), then
// polls until the user claims it while signed in on web/phone.
class PairingView extends Ui.View {

    hidden var _sync;
    hidden var _code;
    hidden var _msg;
    hidden var _pollTimer;

    function initialize() {
        View.initialize();
        _sync = new SyncManager();
        _msg = Ui.loadResource(Rez.Strings.Pairing);
    }

    function onShow() {
        _sync.pair(method(:onPaired));
    }

    function onPaired(success, code) {
        if (success) {
            _code = code;
            _msg = Ui.loadResource(Rez.Strings.PairPrompt);
            _pollTimer = new Timer.Timer();
            _pollTimer.start(method(:onPoll), Config.PAIR_POLL_MS, true);
        } else {
            _msg = Ui.loadResource(Rez.Strings.SyncError);
        }
        Ui.requestUpdate();
    }

    function onPoll() {
        _sync.pollStatus(method(:onStatus));
    }

    function onStatus(success, claimed) {
        if (claimed) {
            if (_pollTimer != null) { _pollTimer.stop(); }
            var lv = new SessionListView();
            Ui.switchToView(lv, new SessionListDelegate(lv), Ui.SLIDE_LEFT);
        }
    }

    function onHide() {
        if (_pollTimer != null) { _pollTimer.stop(); }
    }

    function onUpdate(dc) {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;

        if (_code != null) {
            // TODO(sdk): CIQ 9 adds on-device QR generation. When available, render a
            // QR encoding e.g. `<web>/pair?code=<_code>` here for scan-to-claim.
            // The code text below is the working fallback (user types it on the web).
            dc.drawText(cx, cy - 45, Gfx.FONT_SMALL, _msg, Gfx.TEXT_JUSTIFY_CENTER);
            dc.drawText(cx, cy + 5, Gfx.FONT_NUMBER_MEDIUM, _code, Gfx.TEXT_JUSTIFY_CENTER);
        } else {
            dc.drawText(cx, cy, Gfx.FONT_SMALL, _msg, Gfx.TEXT_JUSTIFY_CENTER);
        }
    }
}

class PairingDelegate extends Ui.BehaviorDelegate {
    hidden var _view;
    function initialize(view) {
        BehaviorDelegate.initialize();
        _view = view;
    }
    // Back exits the app during pairing.
    function onBack() {
        return false;
    }
}
