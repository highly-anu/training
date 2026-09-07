using Toybox.Application;
using Toybox.WatchUi as Ui;
using Toybox.Application.Storage;

// App entry point. Routes to pairing when the watch isn't yet bound to an account,
// otherwise to today's session list.
class TrainingCompanionApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {}
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
        var lv = new SessionListView();
        return [ lv, new SessionListDelegate(lv) ];
    }

    // Glance shown from the watch face (CIQ glance-capable devices).
    // TODO(sdk): confirm getGlanceView signature for your min API; guard if needed.
    function getGlanceView() {
        return [ new GlanceView() ];
    }

    // Re-fetch today's session when settings change (e.g. apiBaseUrl edited).
    function onSettingsChanged() {
        Ui.requestUpdate();
    }
}
