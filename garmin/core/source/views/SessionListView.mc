using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Application;
using Toybox.Application.Storage;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;

// The pre-start page, as Garmin's own activities have one (Strength's,
// photographed on the athlete's fenix 9 Pro, 2026-10-23): the battery at the top,
// the session's icon and name, a rule in its colour, the green START hint, and a
// list below it. With the header focused START starts the workout — the timer,
// after the Countdown Start when it is on — as the watch's own START does. DOWN
// moves into the list (NativeList):
//
//   Workouts           the day's sessions, when there is more than one
//   Steps              the session's exercises; select one to set its reps, weight
//   Training Calendar  the week ahead (the Week menu)
//   Programme          the demo's programme (demo only)
//   Progress           this week, the programme, the methodology's measure
//   Readiness          today's score
//   Settings           tones, vibration, the lead-in
//   Sync               re-fetch today, under the last result (real programme only)
//
// START opens a row; BACK in the list returns to the header, and on the header
// leaves the app. Hold UP still opens the same items as a menu. Refreshes from
// the backend on show; seeds from the same-day cache for an instant paint.
class SessionListView extends Ui.View {

    hidden var _sync;
    hidden var _sessions;   // [WorkoutSession]
    hidden var _status;     // "ok" | "no_program" | "program_expired" | "loading" | "offline"
    hidden var _readiness;  // cached /health/readiness dict, or null
    hidden var _deepLink;   // launched from the complication/glance today shortcut
    hidden var _autoStarted;
    hidden var _g;          // built once in onLayout
    hidden var _index;      // which of the day's sessions is shown
    hidden var _tomorrow;   // the payload's tomorrow preview, or null
    hidden var _focus;      // -1: the header; else the focused row of rows()
    hidden var _rows;       // rows(), built when the day, readiness or sync changes

    // The band of a list with no session behind it (a rest day): the system blue.
    const LIST_ACCENT = 0x4F6FA8;

    function initialize(deepLink) {
        View.initialize();
        _sync = new SyncManager();
        _status = "loading";
        _deepLink = deepLink;
        _autoStarted = false;
        _index = 0;
        _focus = -1;
        // Only seed from cache when the cached date matches today; stale cache
        // (from another day) would briefly show a misleading session.
        var cached = SyncCache.cachedToday();
        if (cached != null) {
            applyToday(cached);
        } else {
            _sessions = [];
        }
        _readiness = Storage.getValue(Config.KEY_READINESS) as Lang.Dictionary?;
        if (DemoSession.enabled()) { applyToday(null); } else { GlanceCache.restoreReal(); }
    }

    function onLayout(dc) {
        _g = new Grid(dc);
        Text.init(_g);
    }

    function onHide() { NativeList.release(); }

    function onShow() {
        if (DemoSession.enabled()) {
            DemoProgram.seedGlanceCache();
            _readiness = DemoSession.readiness();
            _rows = null;
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
        if (!success && data == null) {
            // Nothing for today: say so, rather than spin on "Syncing..." or
            // show another day's sessions.
            _status = "offline";
            _sessions = [];
            _rows = null;
            Ui.requestUpdate();
            return;
        }
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
        if (success) { _readiness = data as Lang.Dictionary?; _rows = null; Ui.requestUpdate(); }
    }

    hidden function applyToday(data as Lang.Dictionary?) as Void {
        _rows = null;
        if (DemoSession.enabled()) {
            _status = "ok";
            _sessions = DemoProgram.week()[0]["sessions"];
            return;
        }
        if (data == null) { _status = "loading"; _sessions = []; return; }
        _status = data.hasKey("status") ? (data["status"] as Lang.String) : "no_program";
        _sessions = WorkoutSession.listFromToday(data);
        _tomorrow = data.hasKey("tomorrow") ? data["tomorrow"] : null;
        if (_index >= _sessions.size()) { _index = 0; }
    }

    function sessions() { return _sessions; }

    // ── the list ─────────────────────────────────────────────────────────────────

    // The rows under the header: [id, label, sub-label, icon]. Built once per
    // change of the day, readiness or sync, not per frame: the week and the
    // day are read from Storage.
    function rows() {
        if (_rows == null) { _rows = buildRows(); }
        return _rows;
    }

    hidden function buildRows() {
        var out = [];
        var s = current();
        if (s != null && _sessions.size() > 1) {
            out.add([:today, "Workouts", s.archetypeName(), Rez.Drawables.GmToday]);
        }
        if (s != null) {
            var n = s.exerciseCount();
            out.add([:workout, "Steps", n.toString() + ((n == 1) ? " exercise" : " exercises"),
                     Rez.Drawables.GmList]);
        }
        if (DemoSession.enabled() || SyncCache.cachedWeek() != null) {
            out.add([:week, "Training Calendar", weekTitle(), Rez.Drawables.GmWeek]);
        }
        if (DemoSession.enabled()) {
            out.add([:programme, "Programme", DemoProgram.programName(), Rez.Drawables.GmList]);
        }
        var p = progress();
        if (p != null) { out.add([:progress, "Progress", $.progressLine(p), Rez.Drawables.GmCheck]); }
        var r = _readiness;
        if (r != null && r.hasKey("score") && r["score"] != null) {
            out.add([:readiness, "Readiness", r["score"].toString() + "  " + $.readinessWord(r["status"]),
                     Rez.Drawables.GmReadiness]);
        }
        out.add([:settings, "Settings", "Alerts and lead-in", Rez.Drawables.GmSettings]);
        if (!DemoSession.enabled()) {
            out.add([:sync, "Sync", SyncCache.syncLine(), Rez.Drawables.GmRefresh]);
        }
        return out;
    }

    // DOWN / UP: into the list from the header, along it, and round again.
    function move(d) {
        _focus = NativeList.step(_focus, d, rows().size());
        Ui.requestUpdate();
    }

    // START: on the header, start the workout; on a row, open it.
    function choose() {
        if (_focus < 0) {
            if (current() != null) { startNow(); }
            return;
        }
        var rs = rows();
        if (_focus >= rs.size()) { _focus = -1; Ui.requestUpdate(); return; }
        $.openPreStartItem(self, rs[_focus][0], false);
    }

    // BACK: from the list to the header; false on the header, which leaves.
    function back() {
        if (_focus < 0) { return false; }
        _focus = -1;
        Ui.requestUpdate();
        return true;
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
        _rows = null;
        Ui.requestUpdate();
    }

    function index()     { return _index; }

    // [ { "offset", "title", "sessions" => [WorkoutSession] } ] from today on,
    // or null when there is no week to show.
    function week() {
        if (DemoSession.enabled()) { return DemoProgram.week(); }
        var raw = SyncCache.cachedWeek();
        if (raw == null) { return null; }
        for (var i = 0; i < raw.size(); i += 1) {
            var rs = raw[i]["sessions"];
            var ss = [];
            for (var j = 0; j < rs.size(); j += 1) { ss.add(new WorkoutSession(rs[j])); }
            raw[i]["sessions"] = ss;
        }
        return raw;
    }

    // The Week menu's title: the demo's phase, or "Week 2 · Base".
    function weekTitle() {
        if (DemoSession.enabled()) { return DemoProgram.programPhase(); }
        var t = SyncCache.cachedToday();
        if (t == null || t["weekNumber"] == null) { return "Week"; }
        var title = "Week " + t["weekNumber"].toString();
        var ph = t["phase"];
        if (ph instanceof Lang.String && ph.length() > 0) {
            title += "  " + ph.substring(0, 1).toUpper() + ph.substring(1, ph.length());
        }
        return title;
    }
    function readiness() { return _readiness; }

    // The server's `progress` for today (week and program counts, the
    // methodology's headline), or null — a demo day and an older server have
    // none.
    function progress() {
        if (DemoSession.enabled()) { return null; }
        var t = SyncCache.cachedToday();
        if (t == null) { return null; }
        var p = t["progress"];
        return (p instanceof Lang.Dictionary) ? p : null;
    }
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
        _rows = null;
        Ui.requestUpdate();
        _sync.fetchToday(method(:onToday));
    }

    // ── helpers ──────────────────────────────────────────────────────────────────

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

        // The list stays up while a sync runs (its Sync row started it); the
        // header waits for the day.
        var rs = rows();
        if (_focus >= rs.size()) { _focus = rs.size() - 1; }
        if (_focus >= 0) {
            drawList(dc, g, rs);
            return;
        }
        if (_status.equals("loading")) {
            Native.text(dc, g.cx, g.cy, Text.line(), "Syncing...", Native.DIM);
            return;
        }
        drawStatus(dc, g);
        if (_status.equals("ok") && _sessions != null && _sessions.size() > 0) {
            drawSession(dc, g, _sessions[_index], rs);
        } else if (_status.equals("ok")) {
            drawRest(dc, g);
        } else if (_status.equals("offline")) {
            // The reason on a line of its own, in words: the code used to trail
            // the instruction in the dimmest font and went unread.
            drawMessage(dc, g, Rez.Drawables.IcUiSync, "Couldn't sync", "Hold UP > Sync");
            Native.text(dc, g.cx, (g.h * 69) / 100, Text.small(),
                        SyncCache.reason(_sync.lastTodayCode), Gfx.COLOR_WHITE);
        } else {
            drawMessage(dc, g, Rez.Drawables.IcUiSync, Ui.loadResource(Rez.Strings.NoProgram),
                        "Generate a plan in the app");
        }
    }

    // The header focused (the photo's "Free" page): the session's icon in its
    // colour, its name, its length, the rule, and the first rows peeking below.
    hidden function drawSession(dc, g, s, rs) {
        var accent = Theme.sessionAccent(s);
        Icons.drawCentered(dc, g.cx, (g.h * 30) / 100, g.iconChip, Icons.forSession(s), accent);
        var ny = (g.h * 410) / 1000;
        Native.fitted(dc, g.cx, ny, Text.lineBold(), s.archetypeName(), Gfx.COLOR_WHITE,
                      Native.chordHalf(g, ny) * 2 - (g.w * 16) / 100);
        var n = s.exerciseCount();
        var sub = s.estimatedMinutes().toString() + " min  " + n.toString()
                  + ((n == 1) ? " exercise" : " exercises");
        var col = Native.DIM;
        if (s.isCompleted()) { sub = "Completed  " + sub; col = Native.GOOD; }
        else if (s.isDeload()) { sub = "Deload  " + sub; col = Native.WARN; }
        var sy = (g.h * 485) / 1000;
        Native.fitted(dc, g.cx, sy, Text.small(), sub, col, Native.chordHalf(g, sy) * 2 - (g.w * 16) / 100);

        // The rule in the session's colour, as under the activity name in Garmin's lists.
        var ry = (g.h * 555) / 1000;
        var half = (g.w * 34) / 100;
        dc.setColor(accent, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth((g.h >= 400) ? 3 : 2);
        dc.drawLine(g.cx - half, ry, g.cx + half, ry);

        NativeList.draw(dc, g, rs, -1, accent, (g.h * 670) / 1000);
        Native.hint(dc, :ready);
    }

    // The list focused: the session's name small at the top over its rule, the
    // focused row at the centre.
    hidden function drawList(dc, g, rs) {
        var s = current();
        var accent = (s != null) ? Theme.sessionAccent(s) : LIST_ACCENT;
        var ty = (g.h * 65) / 1000;
        var title = (s != null) ? s.archetypeName() : "Training";
        Native.fitted(dc, g.cx, ty, Text.small(), title, Gfx.COLOR_WHITE,
                      Native.chordHalf(g, ty) * 2 - (g.w * 8) / 100);
        var ry = (g.h * 115) / 1000;
        var half = Native.chordHalf(g, ry) - (g.w * 10) / 100;
        dc.setColor(accent, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(g.cx - half, ry, g.cx + half, ry);
        NativeList.draw(dc, g, rs, _focus, accent, 0);
    }

    // Battery and its hours left, as at the top of the watch's own pre-start
    // page; a demo build adds its stamp and free memory, so a photo of the page
    // says which build ran and how much room it had.
    hidden function drawStatus(dc, g) {
        var st = System.getSystemStats();
        var t = st.battery.toNumber().toString() + "%";
        if ((st has :batteryInDays) && st.batteryInDays != null) {
            var hrs = (st.batteryInDays * 24).toNumber();
            t += "  " + ((hrs >= 48) ? ((hrs / 24).toString() + "d") : (hrs.toString() + "h"));
        }
        if (DemoSession.enabled()) {
            t = DemoProgram.stamp() + "  " + (st.freeMemory / 1024).toString() + " KB  " + t;
        }
        Native.text(dc, g.cx, (g.h * 120) / 1000, Text.small(), t, Gfx.COLOR_WHITE);
    }

    // Rest day: the charging battery in the recovery green, and what comes next.
    hidden function drawRest(dc, g) {
        Icons.drawCentered(dc, g.cx, (g.h * 30) / 100, g.iconHero, Rez.Drawables.IcUiRest, Native.GOOD);
        Native.text(dc, g.cx, (g.h * 47) / 100, Text.line(), Ui.loadResource(Rez.Strings.RestDay),
                    Gfx.COLOR_WHITE);
        var y = (g.h * 58) / 100;
        var t = _tomorrow;
        if (t instanceof Lang.Dictionary) {
            var n = t.hasKey("sessionCount") ? t["sessionCount"] : 0;
            Native.text(dc, g.cx, y, Text.small(), "TOMORROW", Native.DIM);
            var what = (n == 0) ? "Rest"
                : (t["archetypeName"] + "  " + t["estimatedMinutes"].toString() + " min");
            Native.text(dc, g.cx, y + (g.h * 65) / 1000, Text.small(),
                        Clip.fit(dc, what, Text.small(), (g.w * 76) / 100), Gfx.COLOR_WHITE);
            y += (g.h * 150) / 1000;
        }
        if (_readiness != null && _readiness.hasKey("score") && _readiness["score"] != null) {
            Native.text(dc, g.cx, y, Text.small(), "Readiness " + _readiness["score"].toString(),
                        Theme.readiness(_readiness["status"]));
        }
    }

    hidden function drawMessage(dc, g, icon, title, sub) {
        Icons.drawCentered(dc, g.cx, (g.h * 36) / 100, g.iconChip, icon, Native.DIM);
        Native.text(dc, g.cx, (g.h * 50) / 100, Text.line(), title, Gfx.COLOR_WHITE);
        if (sub != null) { Native.text(dc, g.cx, (g.h * 60) / 100, Text.small(), sub, Native.DIM); }
    }

    // The workout screen, ready but not recording until its START (startNow
    // presses it). A workout already recording (the app was left mid-session) is
    // resumed instead.
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

    // START on the header, and auto-start from the glance: the workout screen,
    // and the timer started (after the Countdown Start when it is on). A workout
    // already recording is shown as it is.
    function startNow() {
        startFirstSession();
        var app = TrainingCompanionApp.instance();
        if (app != null && app.activeController != null) {
            app.activeController.start();
            StepAlert.flush(app.activeController);
        }
    }

    hidden function autoStart() { startNow(); }
}

class SessionListDelegate extends Ui.BehaviorDelegate {
    hidden var _view;
    function initialize(view) {
        BehaviorDelegate.initialize();
        _view = view;
    }
    // START: the workout on the header, the row in the list.
    function onSelect() {
        _view.choose();
        return true;
    }
    // BACK in the list returns to the header; on the header it leaves the app,
    // as on Garmin's own. Exit explicitly: after a workout this is not the only
    // view on the stack.
    function onBack() {
        if (_view.back()) { return true; }
        Toybox.System.exit();
    }
    function onNextPage()     { _view.move(1);  return true; }
    function onPreviousPage() { _view.move(-1); return true; }

    // hold UP: the activity menu.
    function onMenu() {
        $.openActivityMenu(_view);
        return true;
    }
}
