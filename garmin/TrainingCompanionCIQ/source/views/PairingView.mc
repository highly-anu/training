using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Timer;
using Toybox.Lang;
using Toybox.ScanCode;

// First-run pairing. Mints a pairing code, shows it plus a scan-to-claim QR (on
// CIQ 6+ devices), then polls until the user claims it while signed in on web/phone.
class PairingView extends Ui.View {

    hidden var _sync;
    hidden var _code;
    hidden var _msg;
    hidden var _pollTimer;
    hidden var _qr;      // BufferedBitmap of the pairing QR, or null
    hidden var _phone;   // PhoneLink: bind via the phone glue app instead of a code

    function initialize() {
        View.initialize();
        _sync = new SyncManager();
        _phone = new PhoneLink();
        _msg = Ui.loadResource(Rez.Strings.Pairing);
    }

    function onShow() {
        // Listen for the phone glue app pushing a claimed token (skips the code).
        _phone.register(method(:onPhonePaired));
        _sync.pair(method(:onPaired));
    }

    function onPaired(success, code) as Void {
        if (success) {
            _code = code;
            _qr = buildQr(code);
            _msg = Ui.loadResource(Rez.Strings.PairPrompt);
            _pollTimer = new Timer.Timer();
            _pollTimer.start(method(:onPoll), Config.PAIR_POLL_MS, true);
            // Nudge the phone app to sign in and bind this code, if a phone is connected.
            _phone.requestAuth(code);
        } else {
            _msg = Ui.loadResource(Rez.Strings.SyncError);
        }
        Ui.requestUpdate();
    }

    // Phone glue app bound the watch (pushed a token or claimed the code): advance.
    function onPhonePaired() as Void {
        if (_pollTimer != null) { _pollTimer.stop(); }
        var lv = new SessionListView();
        Ui.switchToView(lv, new SessionListDelegate(lv), Ui.SLIDE_LEFT);
    }

    // Render a QR for scan-to-claim. Guarded: ScanCode.createQrCodeImage is CIQ 6.0+,
    // so pre-6 devices (down to our minApiLevel 4.0) simply fall back to the code text.
    hidden function buildQr(code) {
        if (!(Toybox has :ScanCode) || !(ScanCode has :createQrCodeImage)) {
            return null;
        }
        try {
            return ScanCode.createQrCodeImage(
                Config.pairQrValue(code),
                ScanCode.QR_CODE_ECC_MEDIUM,
                120,
                { :color => Gfx.COLOR_BLACK, :backgroundColor => Gfx.COLOR_WHITE }
            );
        } catch (e) {
            return null;
        }
    }

    function onPoll() as Void {
        _sync.pollStatus(method(:onStatus));
    }

    function onStatus(success, claimed) as Void {
        if (claimed) {
            if (_pollTimer != null) { _pollTimer.stop(); }
            var lv = new SessionListView();
            Ui.switchToView(lv, new SessionListDelegate(lv), Ui.SLIDE_LEFT);
        }
    }

    function onHide() {
        if (_pollTimer != null) { _pollTimer.stop(); }
        _phone.unregister();
    }

    function onUpdate(dc) {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;

        if (_code != null) {
            if (_qr != null) {
                // QR + code beneath it: scan to claim, or type the code on the web.
                var qw = _qr.getWidth();
                var qh = _qr.getHeight();
                dc.drawBitmap(cx - (qw / 2), 14, _qr);
                dc.drawText(cx, 14 + qh + 4, Gfx.FONT_NUMBER_MEDIUM, _code,
                    Gfx.TEXT_JUSTIFY_CENTER);
            } else {
                // No on-device QR: the user types the code on the web/phone app.
                dc.drawText(cx, cy - 45, Gfx.FONT_SMALL, _msg, Gfx.TEXT_JUSTIFY_CENTER);
                dc.drawText(cx, cy + 5, Gfx.FONT_NUMBER_MEDIUM, _code, Gfx.TEXT_JUSTIFY_CENTER);
            }
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
