import Toybox.Lang;
import Toybox.WatchUi;

// UP / DOWN (or a vertical swipe) scroll the entries on a page, START (or a tap) goes to the
// next page, BACK to the previous one (and leaves the app from the first), a long press of UP
// (long press on a touch watch) takes a fresh reading.
class SpikeDelegate extends WatchUi.BehaviorDelegate {
    private var _view as SpikeView;

    function initialize(view as SpikeView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onNextPage() as Boolean {
        _view.scroll(1);
        return true;
    }

    function onPreviousPage() as Boolean {
        _view.scroll(-1);
        return true;
    }

    function onSelect() as Boolean {
        _view.turn(1);
        return true;
    }

    function onBack() as Boolean {
        if (_view.pageIndex() == 0) { return false; }
        _view.turn(-1);
        return true;
    }

    function onMenu() as Boolean {
        _view.refresh("M");
        return true;
    }
}
