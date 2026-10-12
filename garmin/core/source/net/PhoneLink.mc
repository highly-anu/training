using Toybox.Communications as Comm;
using Toybox.Application;
using Toybox.Application.Storage;
using Toybox.System;
using Toybox.Lang;

// Watch side of the Phase-3 phone companion ("glue app") link.
//
// The planned phone app signs the athlete in (Supabase) and hands the watch a
// device token that is already claimed to their account, over the BLE phone-app
// message channel — so the athlete skips the manual 6-char pairing code. This
// class is the watch-side endpoint the glue app talks to; it is self-contained and
// only needs registering while the pairing screen is up.
//
// Protocol (dictionaries over Communications phone-app messages):
//   Watch -> Phone : { "type": "authRequest", "code": <pendingCode|null> }
//   Phone -> Watch : { "type": "auth",    "deviceToken": "ciqdev_...", "apiBaseUrl"?: "..." }
//   Phone -> Watch : { "type": "claimed" }   // phone claimed the code the watch minted
//
// registerForPhoneAppMessages is @since 1.4.0 and transmit @since 1.0.0, both well
// under our minApiLevel 4.0, but calls are still `has`-guarded for safety.
class PhoneLink {

    hidden var _onPaired;   // Method(): called once the watch is bound via the phone

    function initialize() {}

    // Begin listening for phone messages. `cb` is invoked (no args) once a token or
    // claim arrives, so the caller can advance past the pairing screen.
    function register(cb) {
        _onPaired = cb;
        if (Comm has :registerForPhoneAppMessages) {
            Comm.registerForPhoneAppMessages(method(:onMessage));
        }
    }

    function unregister() {
        _onPaired = null;
        if (Comm has :registerForPhoneAppMessages) {
            try {
                Comm.registerForPhoneAppMessages(null);
            } catch (e) {
                // Some devices reject a null listener; harmless — leave it registered.
            }
        }
    }

    // True when a phone is connected over BLE (so pushing an auth request is worthwhile).
    function phoneConnected() {
        var s = System.getDeviceSettings();
        return (s != null) && (s has :phoneConnected) && s.phoneConnected;
    }

    // Ask the phone app to sign in and claim/mint a token for us. Best-effort: no-op
    // when no phone is connected. `pendingCode` lets the phone claim a code the watch
    // has already minted, if the token-push path is not used.
    function requestAuth(pendingCode) {
        if (!phoneConnected() || !(Comm has :transmit)) { return; }
        Comm.transmit(
            { "type" => "authRequest", "code" => pendingCode },
            {},
            new PhoneTxListener()
        );
    }

    // Incoming phone message. Binds the watch when the phone supplies a claimed token
    // (or confirms our minted code was claimed), then notifies the caller.
    function onMessage(msg as Comm.PhoneAppMessage) as Void {
        var data = (msg != null) ? msg.data : null;
        if (!(data instanceof Lang.Dictionary)) { return; }
        var type = data.hasKey("type") ? data["type"] : null;
        if (type == null) { return; }

        if (type.equals("auth") && data.hasKey("deviceToken") && data["deviceToken"] != null) {
            Storage.setValue(Config.KEY_DEVICE_TOKEN, data["deviceToken"]);
            Storage.setValue(Config.KEY_CLAIMED, true);
            if (data.hasKey("apiBaseUrl") && data["apiBaseUrl"] != null) {
                Application.Properties.setValue("apiBaseUrl", data["apiBaseUrl"]);
            }
            System.println("CIQ_PHONE_AUTH token received");
            notifyPaired();
        } else if (type.equals("claimed")) {
            Storage.setValue(Config.KEY_CLAIMED, true);
            System.println("CIQ_PHONE_CLAIMED");
            notifyPaired();
        }
    }

    hidden function notifyPaired() {
        if (_onPaired != null) { _onPaired.invoke(); }
    }
}

// ConnectionListener for outbound transmits — logs the result to the sim console.
class PhoneTxListener extends Comm.ConnectionListener {
    function initialize() { ConnectionListener.initialize(); }
    function onComplete() { System.println("CIQ_PHONE_TX ok"); }
    function onError()    { System.println("CIQ_PHONE_TX error"); }
}
