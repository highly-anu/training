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

    function initialize(deepLink) {
        View.initialize();
        _sync = new SyncManager();
        _status = "loading";
        _deepLink = deepLink;
        _autoStarted = false;
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
        if (data == null) { _status = "loading"; _sessions = []; return; }
        _status = data.hasKey("status") ? (data["status"] as Lang.String) : "no_program";
        _sessions = WorkoutSession.listFromToday(data);
    }

    function sessions() { return _sessions; }

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

    // Accent color for a modality id — mirrors the iOS modality palette.
    hidden function modalityColor(modalityId) {
        if (modalityId == null) { return Gfx.COLOR_LT_GRAY; }
        if (modalityId.equals("max_strength") || modalityId.equals("relative_strength")
                || modalityId.equals("combat_sport")) {
            return Gfx.COLOR_RED;
        }
        if (modalityId.equals("strength_endurance") || modalityId.equals("power")
                || modalityId.equals("mixed_modal_conditioning")) {
            return 0xFF8C00;    // orange
        }
        if (modalityId.equals("aerobic_base") || modalityId.equals("durability")
                || modalityId.equals("rehab")) {
            return Gfx.COLOR_GREEN;
        }
        if (modalityId.equals("anaerobic_intervals")) {
            return Gfx.COLOR_YELLOW;
        }
        if (modalityId.equals("mobility") || modalityId.equals("movement_skill")) {
            return 0x5599FF;    // cornflower-blue (readable on black)
        }
        return Gfx.COLOR_LT_GRAY;
    }

    // Readiness dot + score near the top of the screen.
    hidden function drawReadiness(dc, cx) {
        if (_readiness == null || !_readiness.hasKey("status")) { return; }
        var status = _readiness["status"] as Lang.String;
        var color = status.equals("green") ? Gfx.COLOR_GREEN
                  : status.equals("yellow") ? Gfx.COLOR_YELLOW
                  : status.equals("red") ? Gfx.COLOR_RED : Gfx.COLOR_DK_GRAY;
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(cx - 22, 22, 6);
        if (_readiness.hasKey("score")) {
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx - 10, 14, Gfx.FONT_XTINY,
                "Ready " + _readiness["score"], Gfx.TEXT_JUSTIFY_LEFT);
        }
    }

    function startFirstSession() {
        if (_sessions == null || _sessions.size() == 0) { return; }
        var ctl = new WorkoutController(_sessions[0], _sync);
        ctl.start();
        var ev = new ExerciseView(ctl);
        Ui.pushView(ev, new ExerciseDelegate(ctl, ev), Ui.SLIDE_LEFT);
    }

    function onUpdate(dc) {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;

        drawReadiness(dc, cx);

        if (_status.equals("loading")) {
            dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, cy, Gfx.FONT_MEDIUM, "Syncing...", Gfx.TEXT_JUSTIFY_CENTER);
            return;
        }

        if (_status.equals("ok") && _sessions != null && _sessions.size() > 0) {
            drawSessionCard(dc, cx, cy, _sessions[0]);
        } else if (_status.equals("ok")) {
            drawRestDay(dc, cx, cy);
        } else {
            drawNoProgram(dc, cx, cy);
        }
    }

    // Session card: accent bar, archetype name, duration/moves, START button.
    hidden function drawSessionCard(dc, cx, cy, s) {
        var accent = modalityColor(s.modalityId());

        // Thin accent strip above the name.
        dc.setColor(accent, Gfx.COLOR_TRANSPARENT);
        dc.fillRectangle(cx - 55, cy - 82, 110, 4);

        // Archetype name (largest text element).
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 70, Gfx.FONT_MEDIUM, s.archetypeName(), Gfx.TEXT_JUSTIFY_CENTER);

        // Duration · moves.
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 28, Gfx.FONT_TINY,
            s.estimatedMinutes() + " min  |  " + s.exerciseCount() + " moves",
            Gfx.TEXT_JUSTIFY_CENTER);

        // Deload badge.
        if (s.isDeload()) {
            dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, cy - 6, Gfx.FONT_XTINY, "DELOAD", Gfx.TEXT_JUSTIFY_CENTER);
        }

        // START button (filled rectangle with accent color, black label).
        var btnTop = cy + 16;
        var btnH   = 38;
        var btnW   = 120;
        dc.setColor(accent, Gfx.COLOR_TRANSPARENT);
        dc.fillRectangle(cx - btnW / 2, btnTop, btnW, btnH);
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, btnTop + 8, Gfx.FONT_SMALL, "START", Gfx.TEXT_JUSTIFY_CENTER);

        // Footer hint.
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 66, Gfx.FONT_XTINY,
            "SELECT start  |  hold UP refresh",
            Gfx.TEXT_JUSTIFY_CENTER);
    }

    hidden function drawRestDay(dc, cx, cy) {
        // Green circle indicator.
        dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy - 32, 16);
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 44, Gfx.FONT_TINY, "Z", Gfx.TEXT_JUSTIFY_CENTER);

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 4, Gfx.FONT_MEDIUM,
            Ui.loadResource(Rez.Strings.RestDay), Gfx.TEXT_JUSTIFY_CENTER);

        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 44, Gfx.FONT_XTINY, "hold UP to refresh",
            Gfx.TEXT_JUSTIFY_CENTER);
    }

    hidden function drawNoProgram(dc, cx, cy) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 20, Gfx.FONT_MEDIUM,
            Ui.loadResource(Rez.Strings.NoProgram), Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 22, Gfx.FONT_XTINY,
            "Generate a plan in the app", Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, cy + 44, Gfx.FONT_XTINY,
            "hold UP to refresh", Gfx.TEXT_JUSTIFY_CENTER);
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
    // MENU (hold-UP): manually refresh today's session.
    function onMenu() {
        _view.refresh();
        return true;
    }
}
