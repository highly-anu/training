using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;

// Confirmation after finishing. The upload (or buffering) is already in flight
// from WorkoutController.finish(); this is a simple acknowledgement screen.
class SessionCompleteView extends Ui.View {
    function initialize() { View.initialize(); }

    function onUpdate(dc) {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 20, Gfx.FONT_LARGE, "✓", Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 25, Gfx.FONT_SMALL,
            Ui.loadResource(Rez.Strings.Complete), Gfx.TEXT_JUSTIFY_CENTER);
    }
}

class SessionCompleteDelegate extends Ui.BehaviorDelegate {
    function initialize() { BehaviorDelegate.initialize(); }
    // Any key returns to the session list.
    function onSelect() { return backToList(); }
    function onBack()   { return backToList(); }

    hidden function backToList() {
        var lv = new SessionListView();
        Ui.switchToView(lv, new SessionListDelegate(lv), Ui.SLIDE_DOWN);
        return true;
    }
}
