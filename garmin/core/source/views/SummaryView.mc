using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.System;
using Toybox.Lang;
using Toybox.UserProfile;
using Toybox.ActivityMonitor;

// All Stats, opened from the post-save list (SummaryList.mc), as Garmin's own
// activities show it: a page loop with vertical dots on the left, the next page
// named at the bottom, and the START hint. UP/DOWN turn the pages; START opens
// Done / the pages by name; BACK returns to the list.
//
//   Summary         the session's icon and name, duration, SETS | VOLUME, sync
//   Heart Rate      Avg. / Max. and the HR over the session
//   HR Zones        time and share in each zone, on the athlete's own zones
//   Training Effect Garmin's aerobic TE, when the watch computed one
//   Training Status recovery time left and VO2 max, when the watch has them
//   Exercises       each exercise's logged sets
//
// Training status itself (Productive, Maintaining...) reaches only watch faces
// (Complications needs ComplicationSubscriber, which a watch app may not hold),
// so the page shows the two numbers an app can read.
class SummaryView extends Ui.View {

    hidden var _ctl;
    hidden var _g;
    hidden var _pages;   // [ [id, name] ]
    hidden var _page;

    function initialize(ctl) {
        View.initialize();
        _ctl = ctl;
        _page = 0;
        _pages = pagesFor(ctl);
    }

    // The package chooses the pages and their order (watch.summary.pages,
    // vocabulary summary_pages); a page only when the watch has its numbers.
    static function pagesFor(ctl) {
        var out = [];
        var ids = ctl.session().summaryPages();
        for (var i = 0; i < ids.size() && out.size() < 6; i += 1) {
            var id = ids[i];
            if (id.equals("summary"))              { out.add([:summary, "SUMMARY"]); }
            else if (id.equals("heart_rate"))      { out.add([:hr, "HEART RATE"]); }
            else if (id.equals("hr_zones")) {
                if (ctl.zoneSeconds() != null) { out.add([:zones, "HR ZONES"]); }
            }
            else if (id.equals("training_effect")) {
                if (ctl.trainingEffect() != null) { out.add([:te, "TRAINING EFFECT"]); }
            }
            else if (id.equals("training_status")) {
                if (recoveryHours() != null || vo2max() != null) { out.add([:status, "TRAINING STATUS"]); }
            }
            else if (id.equals("exercises"))       { out.add([:exercises, "EXERCISES"]); }
        }
        if (out.size() == 0) { out.add([:summary, "SUMMARY"]); }
        return out;
    }

    // Garmin's aerobic Training Effect bands: [word, colour].
    static function benefit(v) {
        if (v >= 5.0) { return ["Overreaching", Native.Z5]; }
        if (v >= 4.0) { return ["Highly improving", Native.Z4]; }
        if (v >= 3.0) { return ["Improving", Native.Z3]; }
        if (v >= 2.0) { return ["Maintaining", Native.Z2]; }
        if (v >= 1.0) { return ["Minor benefit", Native.Z1]; }
        return ["No benefit", Native.DIM];
    }

    // The hours of recovery the watch has left, read now (the save updates it).
    static function recoveryHours() {
        try {
            var info = ActivityMonitor.getInfo();
            if (info != null && (info has :timeToRecovery) && info.timeToRecovery != null) {
                var h = info.timeToRecovery.toNumber();
                if (h >= 0 && h <= 240) { return h; }
            }
        } catch (e) {}
        return null;
    }

    static function vo2max() {
        try {
            var p = UserProfile.getProfile();
            if (p != null && (p has :vo2maxRunning) && p.vo2maxRunning != null) {
                var v = p.vo2maxRunning.toNumber();
                if (v >= 10 && v <= 100) { return v; }
            }
        } catch (e) {}
        return null;
    }

    function onLayout(dc) {
        _g = new Grid(dc);
        Text.init(_g);
    }

    function onShow() {
        Icons.prefetch(Icons.forSession(_ctl.session()));
    }

    function onHide() { Icons.release(); Native.releaseHints(); }

    function pages() { return _pages; }

    function turn(d) {
        var n = _pages.size();
        _page = ((_page + d) % n + n) % n;
        Ui.requestUpdate();
    }

    function show(id) {
        for (var i = 0; i < _pages.size(); i += 1) {
            if (_pages[i][0] == id) { _page = i; }
        }
        Ui.requestUpdate();
    }

    function onUpdate(dc) {
        try { draw(dc); } catch (e) { Clip.drawError(dc, "summary", e); }
    }

    hidden function draw(dc) {
        Native.clear(dc);
        if (_g == null) { _g = new Grid(dc); Text.init(_g); }
        var g = _g;
        var id = _pages[_page][0];
        if (id == :hr) { drawHr(dc); }
        else if (id == :zones) { drawZones(dc); }
        else if (id == :te) { drawTe(dc); }
        else if (id == :status) { drawStatus(dc); }
        else if (id == :exercises) { drawExercises(dc); }
        else { drawSummary(dc); }

        var next = _pages[(_page + 1) % _pages.size()][1];
        Native.text(dc, g.cx, (g.h * 875) / 1000, Text.small(), next, Gfx.COLOR_WHITE);
        Native.pageDots(dc, g, _page, _pages.size());
        Native.hint(dc, :start);
    }

    hidden function drawSummary(dc) {
        var g = _g;
        var s = _ctl.session();
        Icons.drawCentered(dc, g.cx, (g.h * 13) / 100, g.iconChip,
                           Icons.forSession(s), Theme.sessionAccent(s));
        Native.fitted(dc, g.cx, (g.h * 225) / 1000, Text.lineBold(), s.archetypeName(),
                      Gfx.COLOR_WHITE, (g.w * 66) / 100);
        Native.text(dc, g.cx, (g.h * 385) / 1000, Text.bigNum(), Text.mmss(_ctl.elapsedSec()),
                    Gfx.COLOR_WHITE);
        var vol = _ctl.totalVolumeKg();
        Native.fields(dc, g, (g.h * 545) / 1000, (g.h * 645) / 1000,
                      ["SETS", _ctl.totalSetsLogged().toString()],
                      (vol > 0) ? ["VOLUME KG", vol.toNumber().toString()]
                                : ["CALORIES", _ctl.calories().toString()]);
        var msg = "Syncing...";
        var col = Native.DIM;
        var ok = _ctl.uploadOk();
        if (DemoSession.enabled()) { msg = "Demo - not saved"; }
        else if (ok != null) {
            msg = ok ? "Synced" : "Sync failed - will retry";
            col = ok ? Native.GOOD : Native.WARN;
        }
        if (_ctl.lastError() != null) { msg = _ctl.lastError(); col = Native.Z5; }
        Native.fitted(dc, g.cx, (g.h * 745) / 1000, Text.small(), msg, col, (g.w * 70) / 100);
    }

    hidden function drawHr(dc) {
        var g = _g;
        Native.text(dc, g.cx, (g.h * 15) / 100, Text.small(), "HEART RATE", Gfx.COLOR_WHITE);
        var avg = _ctl.avgHR();
        var max = _ctl.peakHR();
        var f = Text.small();
        var nf = Text.hrNum();
        var a = "Avg.";
        var av = (avg != null) ? avg.toString() : "--";
        var m = "  Max.";
        var mv = (max != null) ? max.toString() : "--";
        var w = dc.getTextWidthInPixels(a, f) + dc.getTextWidthInPixels(av, nf)
              + dc.getTextWidthInPixels(m, f) + dc.getTextWidthInPixels(mv, nf);
        var x = g.cx - (w / 2);
        var y = (g.h * 265) / 1000;
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        var parts = [[a, f], [av, nf], [m, f], [mv, nf]];
        for (var i = 0; i < parts.size(); i += 1) {
            dc.drawText(x, y, parts[i][1], parts[i][0], Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER);
            x += dc.getTextWidthInPixels(parts[i][0], parts[i][1]);
        }
        drawChart(dc, (g.w * 20) / 100, (g.h * 36) / 100, (g.w * 58) / 100, (g.h * 36) / 100, avg, max);
    }

    // The HR over the session: a line on a light grid, the average dashed, the
    // max and average labelled at the right — the watch's own chart, simplified.
    hidden function drawChart(dc, x, y, w, h, avg, max) {
        var n = _ctl.hrCount();
        dc.setPenWidth(1);
        dc.setColor(0x3A3A3A, Gfx.COLOR_TRANSPARENT);
        for (var i = 0; i <= 4; i += 1) {
            dc.drawLine(x + (w * i) / 4, y, x + (w * i) / 4, y + h);
            dc.drawLine(x, y + (h * i) / 4, x + w, y + (h * i) / 4);
        }
        if (n < 2) {
            Native.text(dc, x + (w / 2), y + (h / 2), Text.small(), "No HR recorded", Native.DIM);
            return;
        }
        var lo = 999;
        var hi = 0;
        for (var i = 0; i < n; i += 1) {
            var v = _ctl.hrAt(i);
            if (v < lo) { lo = v; }
            if (v > hi) { hi = v; }
        }
        if (hi - lo < 10) { hi = lo + 10; }
        var px = null;
        var py = null;
        dc.setColor(Native.Z1, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth((_g.h >= 400) ? 3 : 2);
        for (var i = 0; i < n; i += 1) {
            var cx = x + ((w * i) / (n - 1));
            var cy = y + h - ((h * (_ctl.hrAt(i) - lo)) / (hi - lo));
            if (px != null) { dc.drawLine(px, py, cx, cy); }
            px = cx;
            py = cy;
        }
        if (avg != null) {
            var ay = y + h - ((h * (avg - lo)) / (hi - lo));
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            dc.setPenWidth(1);
            for (var dx = 0; dx < w; dx += 10) { dc.drawLine(x + dx, ay, x + dx + 5, ay); }
            dc.drawText(x + w + 4, ay, Text.small(), avg.toString(),
                        Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER);
        }
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x + w + 4, y, Text.small(), hi.toString(),
                    Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    // Five bars, zone 5 on top as on the watch: each zone's colour, its time
    // and its share of the time with a reading, and the bpm it starts at.
    hidden function drawZones(dc) {
        var g = _g;
        Native.text(dc, g.cx, (g.h * 15) / 100, Text.small(), "HR ZONES", Gfx.COLOR_WHITE);
        var secs = _ctl.zoneSeconds();
        var floors = _ctl.zoneFloors();
        var total = 0;
        var most = 1;
        for (var i = 0; i < secs.size(); i += 1) {
            total += secs[i];
            if (secs[i] > most) { most = secs[i]; }
        }
        var f = Text.small();
        var step = (g.h * 105) / 1000;
        var y = (g.h * 27) / 100;
        var barH = step / 2;
        var x0 = (g.w * 26) / 100;     // the bars start right of the zone's bpm
        var barW = (g.w * 30) / 100;
        for (var z = 5; z >= 1; z -= 1) {
            var s = secs[z - 1];
            var pct = (total > 0) ? ((s * 100) / total) : 0;
            dc.setColor(Native.DIM, Gfx.COLOR_TRANSPARENT);
            if (floors != null && z - 1 < floors.size()) {
                dc.drawText(x0 - (g.w * 2) / 100, y, f, floors[z - 1].toString(),
                            Gfx.TEXT_JUSTIFY_RIGHT | Gfx.TEXT_JUSTIFY_VCENTER);
            }
            dc.setColor(0x3A3A3A, Gfx.COLOR_TRANSPARENT);
            dc.fillRectangle(x0, y - barH / 2, barW, barH);
            var w = (barW * s) / most;
            if (s > 0 && w < 3) { w = 3; }
            dc.setColor(Native.zoneColor(z), Gfx.COLOR_TRANSPARENT);
            dc.fillRectangle(x0, y - barH / 2, w, barH);
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            dc.drawText(x0 + barW + (g.w * 3) / 100, y, f,
                        Text.mmss(s) + "  " + pct.toString() + "%",
                        Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER);
            y += step;
        }
    }

    hidden function drawTe(dc) {
        var g = _g;
        var v = _ctl.trainingEffect().toFloat();
        var b = benefit(v);
        Native.text(dc, g.cx, (g.h * 15) / 100, Text.small(), "TRAINING EFFECT", Gfx.COLOR_WHITE);
        Native.text(dc, g.cx, (g.h * 25) / 100, Text.small(), "Aerobic", Native.DIM);
        Native.text(dc, g.cx, (g.h * 45) / 100, Text.bigNum(), v.format("%.1f"), b[1]);
        Native.text(dc, g.cx, (g.h * 64) / 100, Text.line(), b[0], b[1]);
    }

    // RECOVERY | VO2 MAX, the fields the watch itself puts on this page.
    hidden function drawStatus(dc) {
        var g = _g;
        Native.text(dc, g.cx, (g.h * 15) / 100, Text.small(), "TRAINING STATUS", Gfx.COLOR_WHITE);
        var h = recoveryHours();
        var v = vo2max();
        Native.fields(dc, g, (g.h * 40) / 100, (g.h * 51) / 100,
                      (h != null) ? ["RECOVERY", h.toString() + " h"] : null,
                      (v != null) ? ["VO2 MAX", v.toString()] : null);
    }

    hidden function drawExercises(dc) {
        var g = _g;
        Native.text(dc, g.cx, (g.h * 15) / 100, Text.small(), "EXERCISES", Gfx.COLOR_WHITE);
        var list = _ctl.session().exercises();
        var y = (g.h * 27) / 100;
        var step = (g.h * 95) / 1000;
        var shown = 0;
        for (var i = 0; i < list.size() && shown < 6; i += 1) {
            if (_ctl.isFoldedComponent(i)) { continue; }
            var name = list[i].name();
            var t = _ctl.loggedText(name);
            var line = name + ((t != null) ? ("  " + t) : "");
            Native.fitted(dc, g.cx, y, Text.small(), line,
                          (t != null) ? Gfx.COLOR_WHITE : Native.DIM,
                          Native.chordHalf(g, y) * 2 - (g.w * 16) / 100);
            y += step;
            shown += 1;
        }
    }
}

class SummaryDelegate extends Ui.BehaviorDelegate {

    hidden var _view;
    hidden var _ctl;

    function initialize(view, ctl) {
        BehaviorDelegate.initialize();
        _view = view;
        _ctl = ctl;
    }

    function onNextPage()     { _view.turn(1);  return true; }
    function onPreviousPage() { _view.turn(-1); return true; }
    function onBack()         { Ui.popView(Ui.SLIDE_RIGHT); return true; }
    function onTap(evt)       { return true; }

    // START: Done, or a page by name.
    function onSelect() {
        var m = new Ui.Menu2({});
        m.addItem(new Ui.IconMenuItem("Done", null, :done, Native.icon(Rez.Drawables.GmCheck), {}));
        var ps = _view.pages();
        for (var i = 1; i < ps.size(); i += 1) {
            var name = ps[i][1];
            m.addItem(new Ui.MenuItem(name.substring(0, 1) + name.substring(1, name.length()).toLower(),
                                      null, ps[i][0], {}));
        }
        Ui.pushView(m, new SummaryMenuDelegate(_view, self), Ui.SLIDE_LEFT);
        return true;
    }

    function done() { $.leaveSummary(_ctl); }
}

class SummaryMenuDelegate extends Ui.Menu2InputDelegate {
    hidden var _view;
    hidden var _owner;
    function initialize(view, owner) {
        Menu2InputDelegate.initialize();
        _view = view;
        _owner = owner;
    }
    function onSelect(item) {
        var id = item.getId();
        if (id == :done) { _owner.done(); return; }
        _view.show(id);
        Ui.popView(Ui.SLIDE_RIGHT);
    }
    function onBack() { Ui.popView(Ui.SLIDE_RIGHT); }
}
