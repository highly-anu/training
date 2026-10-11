using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Application;
using Toybox.Application.Storage;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;

// The pre-start page, as Garmin's own activities have one: the session's icon,
// name and length, a rule in its colour, readiness, and the green START hint that
// says the activity is ready. START opens the workout (Do Workout / Steps, where
// reps and weights are set); UP/DOWN move between the day's
// sessions; hold UP opens the activity menu (Workout, Today, Week, Readiness);
// BACK leaves the app. Refreshes from the backend on show; seeds from the
// same-day cache for an instant paint.
class SessionListView extends Ui.View {

    hidden var _sync;
    hidden var _sessions;   // [WorkoutSession]
    hidden var _status;     // "ok" | "no_program" | "program_expired" | "loading"
    hidden var _readiness;  // cached /health/readiness dict, or null
    hidden var _deepLink;   // launched from the complication/glance today shortcut
    hidden var _autoStarted;
    hidden var _g;          // built once in onLayout
    hidden var _index;      // which of the day's sessions is shown

    function initialize(deepLink) {
        View.initialize();
        _sync = new SyncManager();
        _status = "loading";
        _deepLink = deepLink;
        _autoStarted = false;
        _index = 0;
        // Only seed from cache when the cached date matches today; stale cache
        // (from another day) would briefly show a misleading session.
        var cached = Storage.getValue(Config.KEY_TODAY_SESSION) as Lang.Dictionary?;
        var cachedDate = Storage.getValue(Config.KEY_TODAY_DATE) as Lang.String?;
        if (cached != null && cachedDate != null && cachedDate.equals(todayDateStr())) {
            applyToday(cached);
        } else {
            _sessions = [];
        }
        _readiness = Storage.getValue(Config.KEY_READINESS) as Lang.Dictionary?;
        if (DemoSession.enabled()) { applyToday(null); }
    }

    function onLayout(dc) {
        _g = new Grid(dc);
        Text.init(_g);
    }

    function onShow() {
        if (DemoSession.enabled()) {
            DemoProgram.seedGlanceCache();
            _readiness = DemoSession.readiness();
            maybeAutoStart();
            return;
        }
        _sync.flushBuffer();               // retry any failed uploads
        _sync.fetchToday(method(:onToday));
        // Wellness first, then readiness: readiness then scores this morning's
        // resting HR, and only two requests are in flight beside the flush.
        _sync.sendWellness(method(:onWellnessSent));
        maybeAutoStart();
    }

    function onWellnessSent(success, data) as Void {
        _sync.fetchReadiness(method(:onReadiness));
    }

    function onToday(success, data) as Void {
        applyToday(data as Lang.Dictionary?);
        maybeAutoStart();
        Ui.requestUpdate();
    }

    // When deep-linked from the complication/glance AND the athlete has opted into
    // autoStartOnLaunch, jump straight into today's session (once).
    hidden function maybeAutoStart() {
        if (_autoStarted || !_deepLink) { return; }
        if (Application.Properties.getValue("autoStartOnLaunch") != true) { return; }
        if (_status.equals("ok") && _sessions != null && _sessions.size() > 0) {
            _autoStarted = true;
            autoStart();
        }
    }

    function onReadiness(success, data) as Void {
        if (success) { _readiness = data as Lang.Dictionary?; Ui.requestUpdate(); }
    }

    hidden function applyToday(data as Lang.Dictionary?) as Void {
        if (DemoSession.enabled()) {
            _status = "ok";
            _sessions = DemoProgram.week()[0]["sessions"];
            return;
        }
        if (data == null) { _status = "loading"; _sessions = []; return; }
        _status = data.hasKey("status") ? (data["status"] as Lang.String) : "no_program";
        _sessions = WorkoutSession.listFromToday(data);
        if (_index >= _sessions.size()) { _index = 0; }
    }

    function sessions() { return _sessions; }

    // Move between the sessions scheduled on the same day.
    function cycle(delta) {
        if (_sessions == null || _sessions.size() <= 1) { return; }
        var n = _sessions.size();
        _index = ((_index + delta) % n + n) % n;
        Ui.requestUpdate();
    }

    // The demo programme changed: show its day 0 and refresh the glance's cache.
    function reloadDemo() {
        _index = 0;
        applyToday(null);
        DemoProgram.seedGlanceCache();
        Ui.requestUpdate();
    }

    function select(i) {
        if (_sessions != null && i >= 0 && i < _sessions.size()) { _index = i; }
        Ui.requestUpdate();
    }

    function index()     { return _index; }
    function readiness() { return _readiness; }
    function status()    { return _status; }

    // The session START would begin, or null.
    function current() {
        if (!_status.equals("ok") || _sessions == null || _sessions.size() == 0) { return null; }
        return _sessions[(_index < _sessions.size()) ? _index : 0];
    }

    // Re-fetch today's session (the activity menu's Sync).
    function refresh() {
        if (DemoSession.enabled()) { return; }
        _status = "loading";
        Ui.requestUpdate();
        _sync.fetchToday(method(:onToday));
    }

    // ── helpers ──────────────────────────────────────────────────────────────────

    // Today's date as "YYYY-MM-DD" in UTC (matches the server date field).
    hidden function todayDateStr() {
        var info = Gregorian.utcInfo(Time.now(), Time.FORMAT_SHORT);
        return info.year.format("%04d") + "-"
             + info.month.format("%02d") + "-"
             + info.day.format("%02d");
    }

    // Accent color for a modality id.
    //
    // This used to be a local 5-bucket table that disagreed with every other
    // client — power rendered orange here but #eab308 yellow on iOS and the web,
    // aerobic_base rendered COLOR_GREEN against #0ea5e9 sky. Theme carries the
    // canonical twelve.
    hidden function modalityColor(modalityId) {
        return Theme.accent(modalityId);
    }

    function onUpdate(dc) {
        try { draw(dc); } catch (e) { Clip.drawError(dc, "list " + _index, e); }
    }

    hidden function draw(dc) {
        Native.clear(dc);
        if (_g == null) { _g = new Grid(dc); Text.init(_g); }
        var g = _g;

        if (_status.equals("loading")) {
            Native.text(dc, g.cx, g.cy, Text.line(), "Syncing...", Native.DIM);
            return;
        }
        if (_status.equals("ok") && _sessions != null && _sessions.size() > 0) {
            drawSession(dc, g, _sessions[_index]);
        } else if (_status.equals("ok")) {
            drawMessage(dc, g, Rez.Drawables.IcCatRecovery, Ui.loadResource(Rez.Strings.RestDay), null);
        } else {
            drawMessage(dc, g, Rez.Drawables.IcUiSync, Ui.loadResource(Rez.Strings.NoProgram),
                        "Generate a plan in the app");
        }
    }

    hidden function drawSession(dc, g, s) {
        var accent = Theme.sessionAccent(s);
        Icons.drawCentered(dc, g.cx, (g.h * 14) / 100, g.iconChip,
                           Icons.categoryKey(s.archetypeCategory()), accent);
        var day = "TODAY";
        if (_sessions.size() > 1) {
            day += "  " + (_index + 1).toString() + " OF " + _sessions.size().toString();
        }
        Native.text(dc, g.cx, (g.h * 225) / 1000, Text.small(), day, Native.DIM);

        // The name on up to two lines, then its length.
        var lineH = (g.h * 80) / 1000;
        var ny = (g.h * 285) / 1000;
        var lines = Text.drawWrapped2(dc, g.cx, ny, (g.w * 76) / 100, lineH,
                                      s.archetypeName(), Gfx.COLOR_WHITE, Text.line());
        var my = ny + (lines * lineH) + (g.h * 40) / 1000;
        var n = s.exerciseCount();
        Native.text(dc, g.cx, my, Text.small(),
                    s.estimatedMinutes().toString() + " min  " + n.toString()
                        + ((n == 1) ? " exercise" : " exercises"), Native.DIM);

        // The rule in the session's colour, as under the activity name in Garmin's menus.
        var ry = my + (g.h * 55) / 1000;
        var half = (g.w * 30) / 100;
        dc.setColor(accent, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth((g.h >= 400) ? 3 : 2);
        dc.drawLine(g.cx - half, ry, g.cx + half, ry);

        var y = ry + (g.h * 70) / 1000;
        if (_readiness != null && _readiness.hasKey("score") && _readiness["score"] != null) {
            Native.text(dc, g.cx, y, Text.line(), "Readiness " + _readiness["score"].toString(),
                        Theme.readiness(_readiness["status"]));
            y += (g.h * 80) / 1000;
        }
        if (s.isCompleted()) {
            Native.text(dc, g.cx, y, Text.small(), "Completed", Native.GOOD);
        } else if (s.isDeload()) {
            Native.text(dc, g.cx, y, Text.small(), "Deload week", Native.WARN);
        }

        if (DemoSession.enabled()) {
            // Build stamp and free memory, so a photo of this page says which build
            // ran and how much room it had.
            var st = System.getSystemStats();
            Native.text(dc, g.cx, (g.h * 92) / 100, Text.small(),
                        DemoProgram.stamp() + "  " + (st.freeMemory / 1024).toString() + " KB", 0x5F6368);
        }
        Native.pageDots(dc, g, _index, _sessions.size());
        Native.hint(dc, :ready);
    }

    hidden function drawMessage(dc, g, icon, title, sub) {
        Icons.drawCentered(dc, g.cx, (g.h * 36) / 100, g.iconChip, icon, Native.DIM);
        Native.text(dc, g.cx, (g.h * 50) / 100, Text.line(), title, Gfx.COLOR_WHITE);
        if (sub != null) { Native.text(dc, g.cx, (g.h * 60) / 100, Text.small(), sub, Native.DIM); }
    }

    // Do Workout: the workout screen, ready but not recording until START. A
    // workout already recording (the app was left mid-session) is resumed instead.
    function startFirstSession() {
        var app = TrainingCompanionApp.instance();
        var ctl = (app != null) ? app.activeController : null;
        if (ctl == null) {
            var s = current();
            if (s == null) { return; }
            ctl = new WorkoutController(s, _sync);
            ctl.prepare();
            if (app != null) { app.activeController = ctl; }
        }
        var ev = new ExerciseScreen(ctl);
        Ui.pushView(ev, new WorkoutDelegate(ctl, ev), Ui.SLIDE_LEFT);
    }

    // Auto-start from the glance skips the menu and begins at once.
    hidden function autoStart() {
        startFirstSession();
        var app = TrainingCompanionApp.instance();
        if (app != null && app.activeController != null) { app.activeController.start(); }
    }
}

class SessionListDelegate extends Ui.BehaviorDelegate {
    hidden var _view;
    function initialize(view) {
        BehaviorDelegate.initialize();
        _view = view;
    }
    // START: the workout menu (Do Workout / Steps), as Garmin opens a workout.
    function onSelect() {
        if (_view.current() != null) { $.openWorkoutMenu(_view); }
        return true;
    }
    // BACK on the pre-start page leaves the app, as on Garmin's own. Exit
    // explicitly: after a workout this is not the only view on the stack.
    function onBack() {
        Toybox.System.exit();
    }
    function onNextPage()     { _view.cycle(1);  return true; }
    function onPreviousPage() { _view.cycle(-1); return true; }

    // hold UP: the activity menu.
    function onMenu() {
        $.openActivityMenu(_view);
        return true;
    }
}
