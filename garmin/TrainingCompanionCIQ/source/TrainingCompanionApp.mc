using Toybox.Application;
using Toybox.WatchUi as Ui;
using Toybox.Application.Storage;

// App entry point. Routes to pairing when the watch isn't yet bound to an account,
// otherwise to today's session list.
class TrainingCompanionApp extends Application.AppBase {

    // True when the app was launched from a watch-face complication or the glance
    // (a deliberate tap on today's session shortcut) rather than the app list.
    hidden var _deepLinkToday;

    // The live WorkoutController, owned by the App rather than by a view, so that
    // a recording session survives view navigation and is always saved on exit.
    public var activeController;

    function initialize() {
        AppBase.initialize();
        _deepLinkToday = false;
        activeController = null;
    }

    // Convenience accessor — views reach the controller through this.
    static function instance() {
        return Application.getApp() as TrainingCompanionApp;
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

    // Last line of defence: if the app is stopping for ANY reason — the user exits
    // via the app list, the system reclaims memory, a crash unwinds — a recording
    // session must still be stopped, saved to the FIT list and uploaded. finish()
    // is idempotent, so this is safe even on the normal completion path.
    function onStop(state) {
        if (activeController != null) {
            activeController.finish();
            activeController = null;
        }
    }

    // Returns [ initialView, initialDelegate ].
    function getInitialView() {
        var token = Storage.getValue(Config.KEY_DEVICE_TOKEN);
        var claimed = Storage.getValue(Config.KEY_CLAIMED);

        // Demo mode bypasses pairing: the point is to reach the workout screens
        // without an account or a synced program.
        if (token == null || claimed != true) {
            if (!DemoSession.enabled()) {
                var pv = new PairingView();
                return [ pv, new PairingDelegate(pv) ];
            }
        }

        // Paired: show today's session (loads from cache, refreshes in background).
        // When deep-linked from the complication/glance, SessionListView can jump
        // straight into the session (opt-in via the autoStartOnLaunch setting).
        var lv = new SessionListView(_deepLinkToday);
        return [ lv, new SessionListDelegate(lv) ];
    }

    // Glance shown from the watch face (CIQ glance-capable devices). Signature
    // verified against SDK 9.2.0; the system only calls it on glance-capable devices.
    (:glance)
    function getGlanceView() {
        return [ new GlanceView() ];
    }

    // Re-fetch today's session when settings change (e.g. apiBaseUrl edited).
    function onSettingsChanged() {
        Ui.requestUpdate();
    }
}
