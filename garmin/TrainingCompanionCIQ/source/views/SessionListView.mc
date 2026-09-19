using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Application;
using Toybox.Application.Storage;
using Toybox.Lang;
using Toybox.Time;
using Toybox.Time.Gregorian;

// Today's session(s): shows the archetype + est. minutes, or a rest-day message.
// SELECT starts the (first) session. MENU (hold-UP) refreshes from the server.
// Refreshes from the backend on show; seeds from same-day cache for instant paint.
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
        _sync.flushBuffer();               // retry any failed uploads
        _sync.fetchToday(method(:onToday));
        _sync.fetchReadiness(method(:onReadiness));
        maybeAutoStart();
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
            startFirstSession();
        }
    }

    function onReadiness(success, data) as Void {
        if (success) { _readiness = data as Lang.Dictionary?; Ui.requestUpdate(); }
    }

    hidden function applyToday(data as Lang.Dictionary?) as Void {
        if (DemoSession.enabled()) {
            _status = "ok";
            _sessions = [ DemoSession.build() ];
            return;
        }
        if (data == null) { _status = "loading"; _sessions = []; return; }
        _status = data.hasKey("status") ? (data["status"] as Lang.String) : "no_program";
        _sessions = WorkoutSession.listFromToday(data);
        if (_index >= _sessions.size()) { _index = 0; }
    }

    function sessions() { return _sessions; }

    // Move between multiple sessions scheduled on the same day.
    function cycle(delta) {
        if (_sessions == null || _sessions.size() <= 1) { return; }
        var n = _sessions.size();
        _index = ((_index + delta) % n + n) % n;
        Ui.requestUpdate();
    }

    // Re-fetch today's session (called from MENU button).
    function refresh() {
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

    // Readiness as an arc on the bezel plus a score, rather than a loose dot.
    hidden function drawReadiness(dc, g) {
        if (_readiness == null || !_readiness.hasKey("status")) { return; }
        var status = _readiness["status"] as Lang.String;
        var col = Theme.readiness(status);
        var score = _readiness.hasKey("score") ? _readiness["score"] : null;

        if (score != null) {
            // A short arc at the top of the bezel, proportional to the score.
            Ring.drawProgress(dc, g.cx, g.cy, g.ringR, g.ringPen,
                              null, col, score.toFloat() / 100.0, true);
            dc.setColor(col, Gfx.COLOR_TRANSPARENT);
            dc.drawText(g.cx, g.yCrown, Text.hint(),
                        "READY " + score.toString(),
                        Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
        } else {
            dc.setColor(col, Gfx.COLOR_TRANSPARENT);
            dc.fillCircle(g.cx, g.yCrown, g.dotR);
        }
    }

    function onUpdate(dc) {
        dc.setColor(Theme.TEXT, Theme.BG);
        dc.clear();
        if (dc has :setAntiAlias) { dc.setAntiAlias(true); }
        if (_g == null) { _g = new Grid(dc); Text.init(_g); }
        var g = _g;

        if (_status.equals("loading")) {
            dc.setColor(Theme.TEXT_DIM, Gfx.COLOR_TRANSPARENT);
            dc.drawText(g.cx, g.cy, Text.label(), "Syncing...",
                        Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
            return;
        }

        if (_status.equals("ok") && _sessions != null && _sessions.size() > 0) {
            drawSessionCard(dc, g, _sessions[_index]);
        } else if (_status.equals("ok")) {
            drawRestDay(dc, g);
        } else {
            drawNoProgram(dc, g);
        }
    }

    // Today's session. Everything is laid out off the Grid, so it fits 416 and
    // 454 alike — the previous version hardcoded pixel offsets (cy-82, btnW=120)
    // tuned for neither, which clipped the archetype name and let the START
    // button collide with the footer hint.
    hidden function drawSessionCard(dc, g, s) {
        var accent = Theme.accent(s.modalityId());

        drawReadiness(dc, g);

        // Category icon above the name.
        var iy = g.yCrown + (g.h * 85 / 1000);
        Icons.drawCentered(dc, g.cx, iy, g.iconChip,
                           Icons.categoryKey(s.archetypeCategory()), accent);

        // Archetype name, fitted and wrapped to two lines instead of clipped.
        var ny = iy + (g.h * 70 / 1000);
        var lineH = (g.h * 62 / 1000);
        var lines = Text.drawWrapped2(dc, g.cx, ny, g.chordWidth(ny), lineH,
                                      s.archetypeName(), Theme.TEXT, Text.label());

        // Duration + move count.
        var my = ny + (lines * lineH) + (g.h * 22 / 1000);
        dc.setColor(Theme.TEXT_DIM, Gfx.COLOR_TRANSPARENT);
        dc.drawText(g.cx, my, Text.hint(),
                    s.estimatedMinutes().toString() + " MIN  -  "
                        + s.exerciseCount().toString()
                        + ((s.exerciseCount() == 1) ? " MOVE" : " MOVES"),
                    Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);

        if (s.isDeload()) {
            Icons.drawCentered(dc, g.cx - (g.iconChip), my + (g.h * 48 / 1000),
                               g.iconChip, Rez.Drawables.IcUiDeload, Theme.READY_YELLOW);
            dc.setColor(Theme.READY_YELLOW, Gfx.COLOR_TRANSPARENT);
            dc.drawText(g.cx + (g.iconChip / 2), my + (g.h * 48 / 1000), Text.hint(),
                        "DELOAD", Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER);
        }

        // START as a ghost button: an outline, not a solid accent block. On an
        // AMOLED panel luminance is power, and a large filled rectangle is the
        // most expensive thing on the screen.
        var bw = (g.w * 42) / 100;
        var bh = (g.h * 11) / 100;
        var bx = g.cx - (bw / 2);
        var by = g.yBase - (bh / 2);
        dc.setColor(accent, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(g.h * 7 / 1000);
        dc.drawRoundedRectangle(bx, by, bw, bh, bh / 2);
        dc.drawText(g.cx, g.yBase, Text.label(), "START",
                    Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);

        // Multi-session days: show which of the day's sessions this is, and let
        // UP/DOWN move between them. Only _sessions[0] was ever reachable before.
        if (_sessions.size() > 1) {
            Chrome.drawDots(dc, g, g.yBase + (g.h * 78 / 1000),
                            _sessions.size(), _index + 1, accent, 0.0);
        }

        Chrome.drawHint(dc, g, "START begin  -  hold UP refresh");
    }

    hidden function drawRestDay(dc, g) {
        drawReadiness(dc, g);
        Icons.drawCentered(dc, g.cx, g.cy - (g.h * 60 / 1000), g.iconHero,
                           Rez.Drawables.IcCatRecovery, Theme.MOBILITY);
        dc.setColor(Theme.TEXT, Gfx.COLOR_TRANSPARENT);
        dc.drawText(g.cx, g.cy + (g.h * 40 / 1000), Text.label(),
                    Ui.loadResource(Rez.Strings.RestDay),
                    Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
        Chrome.drawHint(dc, g, "hold UP to refresh");
    }

    hidden function drawNoProgram(dc, g) {
        dc.setColor(Theme.TEXT_DIM, Gfx.COLOR_TRANSPARENT);
        dc.drawText(g.cx, g.cy - (g.h * 30 / 1000), Text.label(),
                    Ui.loadResource(Rez.Strings.NoProgram),
                    Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Theme.TEXT_HINT, Gfx.COLOR_TRANSPARENT);
        dc.drawText(g.cx, g.cy + (g.h * 30 / 1000), Text.hint(),
                    "Generate a plan in the app",
                    Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
        Chrome.drawHint(dc, g, "hold UP to refresh");
    }

    function startFirstSession() {
        var app = TrainingCompanionApp.instance();
        var ctl = (app != null) ? app.activeController : null;

        if (ctl == null) {
            if (_sessions == null || _sessions.size() == 0) { return; }
            var i = (_index < _sessions.size()) ? _index : 0;
            ctl = new WorkoutController(_sessions[i], _sync);
            ctl.start();
            if (app != null) { app.activeController = ctl; }
        }

        var ev = new ExerciseScreen(ctl);
        Ui.pushView(ev, new WorkoutDelegate(ctl, ev), Ui.SLIDE_LEFT);
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
    // Consume BACK at the root view so the system doesn't exit the app.
    // (The user exits intentionally via the app list, not by accident.)
    function onBack() {
        return true;
    }
    // UP/DOWN move between multiple sessions scheduled on the same day.
    function onNextPage()     { _view.cycle(1);  return true; }
    function onPreviousPage() { _view.cycle(-1); return true; }

    // MENU (hold-UP): manually refresh today's session.
    function onMenu() {
        _view.refresh();
        return true;
    }
}
