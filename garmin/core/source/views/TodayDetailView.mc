using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Application.Storage;
using Toybox.Lang;

// What a press on the glance opens, as a press on Garmin's own glances opens a
// page of detail rather than an activity: the day's sessions, each with its
// icon in its colour, its length and its exercises (ticked once done), then the
// week and readiness. START opens the pre-start page; BACK goes back to the
// glance loop. With "Start session on complication tap" on, a glance press
// still goes straight into the session instead (SessionListView).
//
//   Today
//   [kettlebell] Single-Bell Clean & Press
//                23 min · 4 exercises
//   [run]        Zone 2 Run
//                Done · 45 min
//   3/5 this week · Readiness 72
class TodayDetailView extends Ui.View {

    hidden var _sync;
    hidden var _sessions;   // [WorkoutSession]
    hidden var _status;     // as SessionListView's
    hidden var _tomorrow;
    hidden var _readiness;
    hidden var _g;

    const MAX_ROWS = 3;

    function initialize() {
        View.initialize();
        _sync = new SyncManager();
        _status = "loading";
        _sessions = [];
        if (DemoSession.enabled()) {
            _status = "ok";
            _sessions = DemoProgram.week()[0]["sessions"];
            _readiness = DemoSession.readiness();
        } else {
            apply(SyncCache.cachedToday());
            _readiness = Storage.getValue(Config.KEY_READINESS) as Lang.Dictionary?;
        }
    }

    function onLayout(dc) {
        _g = new Grid(dc);
        Text.init(_g);
    }

    function onShow() {
        if (DemoSession.enabled()) { return; }
        _sync.flushBuffer();
        _sync.fetchToday(method(:onToday));
    }

    function onToday(success, data) as Void {
        if (!success && data == null) {
            if (_status.equals("loading")) { _status = "offline"; }
        } else {
            apply(data as Lang.Dictionary?);
        }
        Ui.requestUpdate();
    }

    hidden function apply(data as Lang.Dictionary?) as Void {
        if (data == null) { return; }
        _status = data.hasKey("status") ? (data["status"] as Lang.String) : "no_program";
        _sessions = WorkoutSession.listFromToday(data);
        _tomorrow = data.hasKey("tomorrow") ? data["tomorrow"] : null;
    }

    function onUpdate(dc) {
        try { draw(dc); } catch (e) { Clip.drawError(dc, "today", e); }
    }

    hidden function draw(dc) {
        Native.clear(dc);
        if (_g == null) { _g = new Grid(dc); Text.init(_g); }
        var g = _g;
        if (_status.equals("loading")) {
            Native.text(dc, g.cx, g.cy, Text.line(), "Syncing...", Native.DIM);
            return;
        }
        if (!_status.equals("ok")) {
            Native.text(dc, g.cx, (g.h * 45) / 100, Text.line(),
                        _status.equals("offline") ? "Couldn't sync" : "No program", Gfx.COLOR_WHITE);
            Native.text(dc, g.cx, (g.h * 56) / 100, Text.small(), "START to open", Native.DIM);
            Native.hint(dc, :ready);
            return;
        }
        var n = _sessions.size();
        Native.text(dc, g.cx, (g.h * 14) / 100, Text.small(), (n == 0) ? "Rest day" : "Today",
                    Gfx.COLOR_WHITE);
        if (n == 0) {
            drawRest(dc, g);
        } else {
            drawSessions(dc, g);
        }
        drawFooter(dc, g);
        Native.hint(dc, :ready);
    }

    // A row per session, its icon at the left and two lines beside it.
    hidden function drawSessions(dc, g) {
        var n = _sessions.size();
        var shown = (n > MAX_ROWS) ? MAX_ROWS : n;
        var rowH = (g.h * 16) / 100;
        var y0 = (g.h * 50) / 100 - (rowH * shown) / 2;
        var ix = (g.w * 15) / 100;
        var tx = ix + g.iconChip + (g.w * 3) / 100;
        var nameH = dc.getFontHeight(Text.lineBold());
        for (var i = 0; i < shown; i += 1) {
            var s = _sessions[i];
            var y = y0 + i * rowH;
            var done = s.isCompleted();
            var accent = Theme.sessionAccent(s);
            Icons.draw(dc, ix, y + (nameH - g.iconChip) / 2, Icons.forSession(s), done ? Native.GOOD : accent);
            var maxW = (g.w * 85) / 100 - tx;
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            dc.drawText(tx, y, Text.lineBold(), Clip.fit(dc, s.archetypeName(), Text.lineBold(), maxW),
                        Gfx.TEXT_JUSTIFY_LEFT);
            var k = s.exerciseCount();
            var sub = s.estimatedMinutes().toString() + " min · " + k.toString()
                      + ((k == 1) ? " exercise" : " exercises");
            if (done) { sub = "Done · " + s.estimatedMinutes().toString() + " min"; }
            dc.setColor(done ? Native.GOOD : Native.DIM, Gfx.COLOR_TRANSPARENT);
            dc.drawText(tx, y + nameH, Text.small(), Clip.fit(dc, sub, Text.small(), maxW),
                        Gfx.TEXT_JUSTIFY_LEFT);
        }
        if (n > shown) {
            Native.text(dc, g.cx, y0 + shown * rowH, Text.small(), "+" + (n - shown).toString() + " more",
                        Native.DIM);
        }
    }

    // Rest day: the recovery icon, and what comes tomorrow.
    hidden function drawRest(dc, g) {
        Icons.drawCentered(dc, g.cx, (g.h * 36) / 100, g.iconHero, Rez.Drawables.IcUiRest, Native.GOOD);
        var t = _tomorrow;
        if (!(t instanceof Lang.Dictionary)) { return; }
        var c = t.hasKey("sessionCount") ? t["sessionCount"] : 0;
        Native.text(dc, g.cx, (g.h * 52) / 100, Text.small(), "TOMORROW", Native.DIM);
        var what = (c == 0) ? "Rest"
            : (t["archetypeName"] + "  " + t["estimatedMinutes"].toString() + " min"
               + ((c > 1) ? ("  +" + (c - 1).toString()) : ""));
        Native.text(dc, g.cx, (g.h * 60) / 100, Text.line(),
                    Clip.fit(dc, what, Text.line(), (g.w * 76) / 100), Gfx.COLOR_WHITE);
    }

    // "3/5 this week" over "Readiness 72", from the server's progress and the
    // readiness the app last fetched; each only when it is known.
    hidden function drawFooter(dc, g) {
        var lines = [];
        var t = DemoSession.enabled() ? null : SyncCache.cachedToday();
        var p = (t != null) ? t["progress"] : null;
        if (p instanceof Lang.Dictionary && p["week"] instanceof Lang.Dictionary) {
            var wk = p["week"];
            if (wk["done"] != null && wk["sessions"] != null) {
                lines.add([wk["done"].toString() + "/" + wk["sessions"].toString() + " this week", Native.DIM]);
            }
        }
        var r = _readiness;
        if (r != null && r.hasKey("score") && r["score"] != null) {
            lines.add(["Readiness " + r["score"].toString(), Theme.readiness(r["status"])]);
        }
        var y = (g.h * 80) / 100;
        for (var i = 0; i < lines.size(); i += 1) {
            Native.text(dc, g.cx, y + i * (g.h * 6) / 100, Text.small(), lines[i][0], lines[i][1]);
        }
    }
}

class TodayDetailDelegate extends Ui.BehaviorDelegate {

    function initialize() { BehaviorDelegate.initialize(); }

    // START: the pre-start page, where START again starts the workout.
    function onSelect() {
        var lv = new SessionListView(false);
        Ui.pushView(lv, new SessionListDelegate(lv), Ui.SLIDE_LEFT);
        return true;
    }

    // BACK: to the glance loop.
    function onBack() {
        Toybox.System.exit();
    }
}
