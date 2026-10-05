import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// The AppBase subclass is compiled into the background process too, so everything it touches
// there is (:background); the view-returning and foreground-only methods opt out of the
// background check instead. Foreground bookkeeping starts in getInitialView, not onStart:
// the docs do not say whether onStart/onStop also run when the service is launched.
(:background)
class SpikeApp extends Application.AppBase {
    private var _opened as Boolean = false;

    function initialize() {
        AppBase.initialize();
    }

    (:typecheck(disableBackgroundCheck))
    function getInitialView() as [Views] or [Views, InputDelegates] {
        _opened = true;
        Foreground.open();
        var view = new $.SpikeView();
        return [view, new $.SpikeDelegate(view)];
    }

    (:typecheck(disableBackgroundCheck))
    function onStop(state as Dictionary?) as Void {
        if (_opened) { Foreground.close(); }
    }

    (:typecheck(disableBackgroundCheck))
    function onBackgroundData(data as Application.PersistableType) as Void {
        Foreground.received(data);
    }

    function getServiceDelegate() as [System.ServiceDelegate] {
        return [new $.SpikeService()];
    }
}
