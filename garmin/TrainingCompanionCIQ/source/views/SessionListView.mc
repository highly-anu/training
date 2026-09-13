using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Application;
using Toybox.Application.Storage;
using Toybox.Lang;

// Today's session(s): shows the archetype + est. minutes, or a rest-day message.
// SELECT starts the (first) session. Refreshes from the backend on show.
class SessionListView extends Ui.View {

    hidden var _sync;
    hidden var _sessions;   // [WorkoutSession]
    hidden var _status;     // "ok" | "no_program" | "program_expired" | "loading"
    hidden var _readiness;  // cached /health/readiness dict, or null
    hidden var _deepLink;   // launched from the complication/glance today shortcut
    hidden var _autoStarted;

    function initialize(deepLink) {
        View.initialize();
        _sync = new SyncManager();
        _status = "loading";
        _deepLink = deepLink;
        _autoStarted = false;
        // Seed from cache for instant paint; then refresh.
        var cached = Storage.getValue(Config.KEY_TODAY_SESSION) as Lang.Dictionary?;
        applyToday(cached);
        _readiness = Storage.getValue(Config.KEY_READINESS) as Lang.Dictionary?;
    }

    function onShow() {
        _sync.flushBuffer();               // retry any failed uploads
        _sync.fetchToday(method(:onToday));
        _sync.fetchReadiness(method(:onReadiness));
        maybeAutoStart();                  // in case the cache already has today's session
    }

    function onToday(success, data) as Void {
        applyToday(data as Lang.Dictionary?);
        maybeAutoStart();
        Ui.requestUpdate();
    }

    // When deep-linked from the complication/glance AND the athlete has opted into
    // autoStartOnLaunch, jump straight into today's session (once). Default is safe:
    // the deep-link just lands on this today screen and waits for a SELECT.
    hidden function maybeAutoStart() {
        if (_autoStarted || !_deepLink) { return; }
        if (Application.Properties.getValue("autoStartOnLaunch") != true) { return; }
        if (_status.equals("ok") && _sessions != null && _sessions.size() > 0) {
            _autoStarted = true;
            startFirstSession();
        }
    }

    function onReadiness(success, data) as Void {
        if (success) { _readiness = data as Lang.Dictionary?; Ui.requestUpdate(); }
    }

    hidden function applyToday(data as Lang.Dictionary?) as Void {
        if (data == null) { _status = "loading"; _sessions = []; return; }
        _status = data.hasKey("status") ? (data["status"] as Lang.String) : "no_program";
        _sessions = WorkoutSession.listFromToday(data);
    }

    function sessions() { return _sessions; }

    // Readiness dot + score near the top of the screen (green/yellow/red from cache).
    hidden function drawReadiness(dc, cx) {
        if (_readiness == null || !_readiness.hasKey("status")) { return; }
        var status = _readiness["status"] as Lang.String;
        var color = status.equals("green") ? Gfx.COLOR_GREEN
                  : status.equals("yellow") ? Gfx.COLOR_YELLOW
                  : status.equals("red") ? Gfx.COLOR_RED : Gfx.COLOR_DK_GRAY;
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(cx - 22, 22, 5);
        if (_readiness.hasKey("score")) {
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx - 10, 12, Gfx.FONT_XTINY,
                "Readiness " + _readiness["score"], Gfx.TEXT_JUSTIFY_LEFT);
        }
    }

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

        drawReadiness(dc, cx);

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
