using Toybox.Application;
using Toybox.WatchUi as Ui;
using Toybox.Application.Storage;

// App entry point. Routes to pairing when the watch isn't yet bound to an account,
// otherwise to today's session list.
class TrainingCompanionApp extends Application.AppBase {

    // True when the app was launched from a watch-face complication or the glance
    // (a deliberate tap on today's session shortcut) rather than the app list.
    hidden var _deepLinkToday;

    function initialize() {
        AppBase.initialize();
        _deepLinkToday = false;
    }

    // `state` carries the launch context. :launchedFromComplication (the complication
    // index) or :launchedFromGlance mark a tap on our today shortcut — deep-link to it.
    function onStart(state) {
        if (state != null
                && (state.hasKey(:launchedFromComplication)
                    || state.hasKey(:launchedFromGlance))) {
            _deepLinkToday = true;
        }
    }

    function onStop(state) {}

    // Returns [ initialView, initialDelegate ].
    function getInitialView() {
        var token = Storage.getValue(Config.KEY_DEVICE_TOKEN);
        var claimed = Storage.getValue(Config.KEY_CLAIMED);

        if (token == null || claimed != true) {
            var pv = new PairingView();
            return [ pv, new PairingDelegate(pv) ];
        }

        // Paired: show today's session (loads from cache, refreshes in background).
        // When deep-linked from the complication/glance, SessionListView can jump
        // straight into the session (opt-in via the autoStartOnLaunch setting).
        var lv = new SessionListView(_deepLinkToday);
        return [ lv, new SessionListDelegate(lv) ];
    }

    // Glance shown from the watch face (CIQ glance-capable devices). Signature
    // verified against SDK 9.2.0; the system only calls it on glance-capable devices.
    function getGlanceView() {
        return [ new GlanceView() ];
    }

    // Re-fetch today's session when settings change (e.g. apiBaseUrl edited).
    function onSettingsChanged() {
        Ui.requestUpdate();
    }
}
