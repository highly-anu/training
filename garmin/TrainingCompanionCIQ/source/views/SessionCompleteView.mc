using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;

// The finish screen.
//
// It used to be a green tick and the word "complete" — no duration, no HR, no
// set count, and no indication of whether the upload actually landed. After an
// hour of work that is the one screen the athlete wants something from.
class SessionCompleteView extends Ui.View {

    hidden var _ctl;
    hidden var _g;

    function initialize(ctl) {
        View.initialize();
        _ctl = ctl;
    }

    function onLayout(dc) {
        _g = new Grid(dc);
        Text.init(_g);
    }

    function onShow() {
        // A closing flourish: the ring sweeps to full as the screen appears.
        Anim.start(Anim.SLOT_RING, 0.0, 1.0, 900, Anim.EASE_OUT, null);
    }

    function onHide() { Anim.stopAll(); }

    function onUpdate(dc) {
        dc.setColor(Theme.TEXT, Theme.BG);
        dc.clear();
        if (dc has :setAntiAlias) { dc.setAntiAlias(true); }
        if (_g == null) { _g = new Grid(dc); Text.init(_g); }
        var g = _g;

        var accent = (_ctl != null) ? Theme.accent(_ctl.modality()) : Theme.MOBILITY;
        var sweep = Anim.settled(Anim.SLOT_RING) ? 1.0 : Anim.value(Anim.SLOT_RING);
        Ring.drawProgress(dc, g.cx, g.cy, g.ringR, g.ringPen,
                          Theme.dimmed(accent, 22), accent, sweep, true);

        Icons.drawCentered(dc, g.cx, g.yCrown + (g.h * 60 / 1000), g.iconChip,
                           Rez.Drawables.IcUiCheck, Theme.READY_GREEN);

        if (_ctl == null) {
            dc.setColor(Theme.TEXT, Gfx.COLOR_TRANSPARENT);
            dc.drawText(g.cx, g.cy, Text.label(),
                        Ui.loadResource(Rez.Strings.Complete),
                        Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
            return;
        }

        // Duration is the headline — it is what the athlete just spent.
        Chrome.drawCore(dc, g, Text.mmss(_ctl.elapsedSec()), Theme.TEXT, true);

        var avg = _ctl.avgHR();
        var peak = _ctl.peakHR();
        if (avg != null) {
            dc.setColor(Theme.TEXT_DIM, Gfx.COLOR_TRANSPARENT);
            var hr = "AVG " + avg.toString();
            if (peak != null) { hr += "   PEAK " + peak.toString(); }
            dc.drawText(g.cx, g.ySub, Text.hint(), hr,
                        Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
        }

        var line = _ctl.totalSetsLogged().toString() + " sets";
        if (_ctl.distanceKm() > 0.05) {
            line += "   " + Text.kg(_ctl.distanceKm()) + " km";
        }
        dc.setColor(Theme.TEXT_DIM, Gfx.COLOR_TRANSPARENT);
        dc.drawText(g.cx, g.yBase, Text.label(), line,
                    Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);

        // Say plainly whether the session reached the server. A failure is
        // buffered and retried, so this is information, not an error.
        var ok = _ctl.uploadOk();
        var msg = "syncing...";
        var col = Theme.TEXT_HINT;
        if (ok != null) {
            if (ok) { msg = "synced"; col = Theme.READY_GREEN; }
            else    { msg = Ui.loadResource(Rez.Strings.SyncError); col = Theme.READY_YELLOW; }
        }
        dc.setColor(col, Gfx.COLOR_TRANSPARENT);
        dc.drawText(g.cx, g.yHint, Text.hint(), msg,
                    Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }
}

class SessionCompleteDelegate extends Ui.BehaviorDelegate {
    function initialize() { BehaviorDelegate.initialize(); }
    // Any key returns to the session list.
    function onSelect() { return backToList(); }
    function onBack()   { return backToList(); }

    hidden function backToList() {
        var lv = new SessionListView(false);
        Ui.switchToView(lv, new SessionListDelegate(lv), Ui.SLIDE_DOWN);
        return true;
    }
}
