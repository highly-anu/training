using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.System;
using Toybox.Lang;

// ONE persistent view for the whole workout, laid out as Garmin's own Strength
// workout (photographed on the athlete's fenix 9 Pro, 2026-10-09). DOWN turns the
// pages, UP turns them back:
//
//   1. Workout   ♥ HR · the exercise · REPS | SET · rule · "Next: Rest" / "3:00"
//   2. Heart     five-zone gauge · ♥ HR · total time · field | CALORIES · time of day
//   3. Steps     the workout's steps, scrollable: DOWN walks down the list and,
//                past its end, wraps to page 1; UP walks up and, past its top,
//                returns to page 2
//
// The renderer for the current slot type supplies page 1's content and LAP's
// action; resting and "workout complete" are drawn here.
class ExerciseScreen extends Ui.View {

    const PAGE_WORK  = 0;
    const PAGE_HEART = 1;
    const PAGE_STEPS = 2;
    const PAGE_COUNT = 3;
    const DOTS_MS    = 1500;   // page dots show briefly after a turn

    hidden var _ctl;
    hidden var _g;
    hidden var _page;
    hidden var _pageAt;
    hidden var _renderer;
    hidden var _slotKey;
    hidden var _cursor;        // focused row on the step page
    hidden var _err;
    hidden var _left = false;

    function initialize(ctl) {
        View.initialize();
        _ctl = ctl;
        _page = PAGE_WORK;
        _pageAt = 0;
        _slotKey = null;
        _cursor = -1;
    }

    function onLayout(dc) {
        _g = new Grid(dc);
        Text.init(_g);
        bindRenderer();
    }

    function onShow() {
        if (_ctl.state() == WorkoutController.COMPLETE) { leaveIfComplete(); return; }
        bindRenderer();
    }

    function onHide() { Icons.release(); Native.releaseHints(); }

    // The session ended while a menu was on top (Save): hand over to the summary.
    function leaveIfComplete() {
        if (_left || _ctl.state() != WorkoutController.COMPLETE) { return; }
        _left = true;
        var app = TrainingCompanionApp.instance();
        if (app != null) { app.activeController = null; }
        var sv = new SummaryView(_ctl);
        Ui.switchToView(sv, new SummaryDelegate(sv, _ctl), Ui.SLIDE_UP);
    }

    // A key handler threw: keep the message and show it on the next frame.
    function fail(where, e) {
        _err = where + ": " + ((e != null) ? e.getErrorMessage() : "?");
        Ui.requestUpdate();
    }

    function renderer() { return _renderer; }

    // ── paging ───────────────────────────────────────────────────────────────────

    function setPage(p) {
        _page = ((p % PAGE_COUNT) + PAGE_COUNT) % PAGE_COUNT;
        _pageAt = System.getTimer();
        if (_page == PAGE_STEPS) { _cursor = Steps.rows(_ctl)["current"]; }
        Ui.requestUpdate();
    }

    function down() {
        if (_page == PAGE_STEPS) {
            var rs = Steps.rows(_ctl)["rows"];
            var n = nextStepRow(rs, _cursor, 1);
            if (n < 0) { setPage(PAGE_WORK); } else { _cursor = n; Ui.requestUpdate(); }
            return;
        }
        setPage(_page + 1);
    }

    function up() {
        if (_page == PAGE_STEPS) {
            var rs = Steps.rows(_ctl)["rows"];
            var n = nextStepRow(rs, _cursor, -1);
            if (n < 0) { setPage(PAGE_HEART); } else { _cursor = n; Ui.requestUpdate(); }
            return;
        }
        setPage(_page - 1);
    }

    // The next :step row from i in direction d, or -1 past either end.
    hidden function nextStepRow(rs, i, d) {
        var j = i + d;
        while (j >= 0 && j < rs.size()) {
            if (rs[j][0] == :step) { return j; }
            j += d;
        }
        return -1;
    }

    // Pick the renderer for the current slot type.
    function bindRenderer() {
        var ex = _ctl.currentExercise();
        var slot = (ex != null) ? ex.slotType() : "";
        var key = ArchetypeBehavior.isRoundTimer(_ctl.archetypeId()) ? "__round" : slot;
        if (_slotKey == null || !_slotKey.equals(key)) {
            _renderer = build(key, slot);
            _slotKey = key;
        }
    }

    hidden function build(key, slot) {
        if (key.equals("__round"))         { return new RoundTimerRenderer(); }
        if (slot.equals("sets_reps"))      { return new SetsRepsRenderer(); }
        if (slot.equals("emom"))           { return new EmomRenderer(); }
        if (slot.equals("amrap"))          { return new AmrapRenderer(); }
        if (slot.equals("amrap_movement")) { return new AmrapRenderer(); }
        if (slot.equals("for_time"))       { return new ForTimeRenderer(); }
        if (slot.equals("distance"))       { return new DistanceRenderer(); }
        if (slot.equals("static_hold"))    { return new StaticHoldRenderer(); }
        // time_domain and skill_practice share a screen.
        return new TimeDomainRenderer();
    }

    // ── drawing ──────────────────────────────────────────────────────────────────

    function onUpdate(dc) {
        if (_err != null) { Clip.drawMessage(dc, _err); return; }
        try { draw(dc); } catch (e) { Clip.drawError(dc, "p" + _page + " x" + _ctl.exerciseIndex(), e); }
    }

    hidden function draw(dc) {
        Native.clear(dc);
        if (_g == null) { _g = new Grid(dc); Text.init(_g); }
        // Steps now end by themselves on the clock, so the slot can change between
        // key presses: rebind here (a no-op unless the slot type changed).
        bindRenderer();
        if (_page == PAGE_HEART) {
            drawHeart(dc);
        } else if (_page == PAGE_STEPS) {
            drawSteps(dc);
        } else {
            drawWork(dc);
        }
        Native.hint(dc, :lap);
        if (System.getTimer() - _pageAt < DOTS_MS) {
            Native.pageDots(dc, _g, _page, PAGE_COUNT);
        }
    }

    // Page 1 — the Strength page.
    hidden function drawWork(dc) {
        var g = _g;
        var ex = _ctl.currentExercise();
        var st = _ctl.state();
        Native.heartRate(dc, g, (g.h * 15) / 100, _ctl.currentHR(), _ctl.currentZone());
        Native.hint(dc, _ctl.isReady() ? :ready : :start);

        var title;
        var a;
        var b;
        var ls;
        if (st == WorkoutController.DONE || ex == null) {
            title = "Workout complete";
            a = ["TIME", Text.mmss(_ctl.elapsedSec())];
            b = ["SETS", _ctl.totalSetsLogged().toString()];
            ls = ["Press START", "to save"];
        } else if (st == WorkoutController.RESTING) {
            title = "Rest";
            a = ["REST", Text.mmss(_ctl.restRemaining())];
            b = _ctl.restAdvances() ? ["DONE", Steps.setCount(ex).toString() + " sets"]
                                    : ["SET", _ctl.currentSetCount().toString() + "/"
                                              + Steps.setCount(ex).toString()];
            var n = _ctl.nextStep();
            ls = ["Next: " + n[0], n[1]];
        } else {
            title = _renderer.title(_ctl, ex);
            a = _renderer.fieldA(_ctl, ex);
            b = _renderer.fieldB(_ctl, ex);
            // Ready: nothing records until START, as on Garmin's own workouts.
            ls = _ctl.isReady() ? ["Press START", "to begin"] : _renderer.lines(_ctl, ex);
        }

        var ty = (g.h * 245) / 1000;
        Native.fitted(dc, g.cx, ty, Text.lineBold(), title, Gfx.COLOR_WHITE,
                      Native.chordHalf(g, ty) * 2 - (g.w * 14) / 100);
        Native.fields(dc, g, (g.h * 335) / 1000, (g.h * 455) / 1000, a, b);
        var ry = (g.h * 575) / 1000;
        Native.rule(dc, g, ry, 92);
        drawLines(dc, ls, (g.h * 665) / 1000, (g.h * 765) / 1000);
    }

    hidden function drawLines(dc, ls, y1, y2) {
        if (ls == null) { return; }
        var g = _g;
        if (ls[0] != null) {
            Native.fitted(dc, g.cx, y1, Text.line(), ls[0], Gfx.COLOR_WHITE,
                          Native.chordHalf(g, y1) * 2 - (g.w * 12) / 100);
        }
        if (ls.size() > 1 && ls[1] != null) {
            Native.fitted(dc, g.cx, y2, Text.line(), ls[1], Gfx.COLOR_WHITE,
                          Native.chordHalf(g, y2) * 2 - (g.w * 16) / 100);
        }
    }

    // Page 2 — the heart-rate gauge page.
    hidden function drawHeart(dc) {
        var g = _g;
        var ex = _ctl.currentExercise();
        Native.zoneGauge(dc, g, _ctl.hrGaugeFraction(), _ctl.currentZone());
        Native.heartRate(dc, g, (g.h * 215) / 1000, _ctl.currentHR(), _ctl.currentZone());
        Native.text(dc, g.cx, (g.h * 395) / 1000, Text.bigNum(), Text.mmss(_ctl.elapsedSec()),
                    Gfx.COLOR_WHITE);
        if (_ctl.isCardio()) {
            // A run's page, as Garmin's: distance and pace.
            Native.fields(dc, g, (g.h * 560) / 1000, (g.h * 665) / 1000,
                          ["DISTANCE", Text.kg(((_ctl.distanceKm() * 100).toNumber()) / 100.0)],
                          ["PACE", _ctl.paceText()]);
        } else {
            var left = (ex != null && _ctl.state() != WorkoutController.DONE)
                ? _renderer.gaugeField(_ctl, ex)
                : ["SETS", _ctl.totalSetsLogged().toString()];
            Native.fields(dc, g, (g.h * 560) / 1000, (g.h * 665) / 1000,
                          left, ["CALORIES", _ctl.calories().toString()]);
        }
        var ry = (g.h * 765) / 1000;
        Native.rule(dc, g, ry, 80);
        Native.text(dc, g.cx, (g.h * 840) / 1000, Text.line(), Native.timeOfDay(), Gfx.COLOR_WHITE);
    }

    // Page 3 — the steps, scrollable, the focused row marked with the blue bar and
    // the current block bracketed in yellow, as on the watch's own workout list.
    hidden function drawSteps(dc) {
        var g = _g;
        var res = Steps.rows(_ctl);
        var rs = res["rows"];
        if (rs.size() == 0) { return; }
        if (_cursor < 0 || _cursor >= rs.size() || rs[_cursor][0] != :step) {
            _cursor = res["current"];
        }

        var lineH = (g.h * 82) / 1000;
        var headH = (g.h * 80) / 1000;
        var stepH = lineH * 2;
        var xBracket = (g.w * 26) / 100;
        var xBar = (g.w * 295) / 1000;
        var xText = (g.w * 325) / 1000;

        // Row tops, then scroll so the focused row starts a little above centre.
        var tops = new [rs.size()];
        var y = 0;
        for (var i = 0; i < rs.size(); i += 1) {
            tops[i] = y;
            y += (rs[i][0] == :header) ? headH : stepH;
        }
        var off = ((g.h * 40) / 100) - tops[_cursor];

        // Block brackets: from each header to the end of its block.
        var i2 = 0;
        while (i2 < rs.size()) {
            if (rs[i2][0] != :header) { i2 += 1; continue; }
            var j = i2 + 1;
            while (j < rs.size() && rs[j][4] == rs[i2][4]) { j += 1; }
            var col = blockColor(rs[i2][3]);
            var y0 = off + tops[i2] + (headH / 2);
            var y1 = off + tops[j - 1] + stepH - (lineH / 4);
            dc.setColor(col, Gfx.COLOR_TRANSPARENT);
            dc.setPenWidth((g.h >= 400) ? 3 : 2);
            dc.drawLine(xBracket, y0, xBracket, y1);
            dc.drawLine(xBracket, y0, xBracket + (g.w * 2) / 100, y0);
            i2 = j;
        }

        for (var k = 0; k < rs.size(); k += 1) {
            var r = rs[k];
            var top = off + tops[k];
            if (top > g.h || top + stepH < 0) { continue; }
            if (r[0] == :header) {
                var hy = top + (headH / 2);
                dc.setColor(blockColor(r[3]), Gfx.COLOR_TRANSPARENT);
                dc.drawText(xText - (g.w * 3) / 100, hy, Text.small(),
                            Clip.fit(dc, r[1], Text.small(), textRoom(g, hy, xText)),
                            Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER);
                continue;
            }
            var y1r = top + (lineH / 2);
            var y2r = top + lineH + (lineH / 2);
            var col2 = (r[3] == :done) ? Native.DIM : Gfx.COLOR_WHITE;
            if (k == _cursor) {
                dc.setColor(Native.CURSOR, Gfx.COLOR_TRANSPARENT);
                dc.fillRectangle(xBar, top + (lineH / 6), (g.w * 12) / 1000 + 2, stepH - (lineH / 3));
            }
            dc.setColor(col2, Gfx.COLOR_TRANSPARENT);
            dc.drawText(xText, y1r, Text.line(), Clip.fit(dc, r[1], Text.line(), textRoom(g, y1r, xText)),
                        Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER);
            if (r[2] != null) {
                dc.drawText(xText, y2r, Text.small(), Clip.fit(dc, r[2], Text.small(), textRoom(g, y2r, xText)),
                            Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER);
            }
        }
    }

    hidden function blockColor(state) {
        if (state == :now) { return Native.BLOCK_NOW; }
        if (state == :done) { return Native.DIM; }
        return Gfx.COLOR_WHITE;
    }

    // Width from x to the bezel at height y.
    hidden function textRoom(g, y, x) {
        var w = g.cx + Native.chordHalf(g, y) - x - (g.w * 4) / 100;
        return (w > 10) ? w : 10;
    }
}
