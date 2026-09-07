using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Application.Storage;

// Today's session(s): shows the archetype + est. minutes, or a rest-day message.
// SELECT starts the (first) session. Refreshes from the backend on show.
class SessionListView extends Ui.View {

    hidden var _sync;
    hidden var _sessions;   // [WorkoutSession]
    hidden var _status;     // "ok" | "no_program" | "program_expired" | "loading"

    function initialize() {
        View.initialize();
        _sync = new SyncManager();
        _status = "loading";
        // Seed from cache for instant paint; then refresh.
        var cached = Storage.getValue(Config.KEY_TODAY_SESSION);
        applyToday(cached);
    }

    function onShow() {
        _sync.flushBuffer();               // retry any failed uploads
        _sync.fetchToday(method(:onToday));
    }

    function onToday(success, data) {
        applyToday(data);
        Ui.requestUpdate();
    }

    hidden function applyToday(data) {
        if (data == null) { _status = "loading"; _sessions = []; return; }
        _status = data.hasKey("status") ? data["status"] : "no_program";
        _sessions = WorkoutSession.listFromToday(data);
    }

    function sessions() { return _sessions; }

    function startFirstSession() {
        if (_sessions != null && _sessions.size() > 0) {
            var ctl = new WorkoutController(_sessions[0], _sync);
            ctl.start();
            var ev = new ExerciseView(ctl);
            Ui.pushView(ev, new ExerciseDelegate(ctl, ev), Ui.SLIDE_LEFT);
        }
    }

    function onUpdate(dc) {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;

        if (_status.equals("ok") && _sessions != null && _sessions.size() > 0) {
            var s = _sessions[0];
            dc.drawText(cx, cy - 40, Gfx.FONT_TINY, s.modalityId(), Gfx.TEXT_JUSTIFY_CENTER);
            dc.drawText(cx, cy - 12, Gfx.FONT_MEDIUM, s.archetypeName(), Gfx.TEXT_JUSTIFY_CENTER);
            dc.drawText(cx, cy + 20, Gfx.FONT_TINY,
                s.estimatedMinutes() + " min · " + s.exerciseCount() + " moves",
                Gfx.TEXT_JUSTIFY_CENTER);
            dc.drawText(cx, cy + 55, Gfx.FONT_TINY,
                Ui.loadResource(Rez.Strings.StartWorkout) + " ▶",
                Gfx.TEXT_JUSTIFY_CENTER);
        } else {
            var msg = _status.equals("loading")
                ? "…"
                : (_status.equals("ok")
                    ? Ui.loadResource(Rez.Strings.RestDay)
                    : Ui.loadResource(Rez.Strings.NoProgram));
            dc.drawText(cx, cy, Gfx.FONT_MEDIUM, msg, Gfx.TEXT_JUSTIFY_CENTER);
        }
    }
}

class SessionListDelegate extends Ui.BehaviorDelegate {
    hidden var _view;
    function initialize(view) {
        BehaviorDelegate.initialize();
        _view = view;
    }
    function onSelect() {
        _view.startFirstSession();
        return true;
    }
}
