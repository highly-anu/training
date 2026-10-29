using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.System;
using Toybox.Lang;
using Toybox.UserProfile;
using Toybox.ActivityMonitor;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.Timer;

// All Stats, opened from the post-save list (SummaryList.mc), as Garmin's own
// activities show it (photographed on the athlete's fenix 9 Pro, 2026-10-29):
// the title between two dashes, the next page named in light blue at the foot,
// vertical dots on the left for a moment after a turn, and the START hint.
// UP/DOWN turn the pages; START opens Done / the pages by name; BACK returns to
// the list.
//
//   Summary         the session's icon, the duration, SETS | TOTAL CALORIES
//   Heart Rate      Avg. / Max. and the HR over the session, coloured by zone
//   HR Zones        a bar per zone over the average HR; time | share per zone
//   Training Effect Garmin's aerobic TE under its benefit word
//   Training Status VO2 max in its fitness band's colour, recovery time left
//   Exercises       each exercise's logged sets
//
// What the watch's own pages add — the anaerobic TE, the activity's load, the
// acute load and the status word (Productive, Maintaining...) — no watch app
// can read: Activity.Info carries only the aerobic TE, and complications reach
// only watch faces (ComplicationSubscriber is a watch-face permission).
class SummaryView extends Ui.View {

    hidden var _ctl;
    hidden var _g;
    hidden var _pages;   // [ [id, name] ]
    hidden var _page;
    hidden var _dotsUntil = 0;   // System.getTimer() until which the page dots show
    hidden var _dotsTimer = null;

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

    // Garmin's aerobic Training Effect bands. The watch writes the word and the
    // numbers in white; colour is for the zones.
    static function benefit(v) {
        if (v >= 5.0) { return "Overreaching"; }
        if (v >= 4.0) { return "Highly improving"; }
        if (v >= 3.0) { return "Improving"; }
        if (v >= 2.0) { return "Maintaining"; }
        if (v >= 1.0) { return "Minor benefit"; }
        return "No benefit";
    }

    // Garmin's VO2 max bands (its standard ratings, after the Cooper Institute):
    // the lowest value of Fair, Good, Excellent and Superior for a sex and an
    // age, by decade from 20 (under 20 reads as the twenties, 80 and over as the
    // seventies). The band 0 Poor - 4 Superior, or null without sex or age.
    static function vo2Band(v, female, age) {
        if (v == null || female == null || age == null) { return null; }
        var men = [[41.7, 45.4, 51.1, 55.4], [40.5, 44.0, 48.3, 54.0], [38.5, 42.4, 46.4, 52.5],
                   [35.6, 39.2, 43.4, 48.9], [32.3, 35.5, 39.5, 45.7], [29.4, 32.3, 36.7, 42.1]];
        var women = [[36.1, 39.5, 43.9, 49.6], [34.4, 37.8, 42.4, 47.4], [33.0, 36.3, 39.7, 45.3],
                     [30.1, 33.0, 36.7, 41.1], [27.5, 30.0, 33.0, 37.8], [25.9, 28.1, 30.9, 36.7]];
        var d = (age.toNumber() - 20) / 10;
        if (d < 0) { d = 0; }
        if (d > 5) { d = 5; }
        var row = female ? women[d] : men[d];
        var band = 0;
        for (var i = 0; i < row.size(); i += 1) {
            if (v.toFloat() >= row[i]) { band = i + 1; }
        }
        return band;
    }

    // Poor red, Fair orange, Good green, Excellent blue, Superior purple.
    static function vo2Color(band) {
        if (band == null) { return Gfx.COLOR_WHITE; }
        return [Native.Z5, Native.Z4, Native.Z3, Native.Z2, 0xA45EE5][band];
    }

    // The time axis's step, in seconds: a mark every 10 minutes as on the
    // watch, 5 in a short session, 30 in a long one.
    static function timeStep(totalSec) {
        if (totalSec <= 1200) { return 300; }
        if (totalSec <= 3600) { return 600; }
        if (totalSec <= 10800) { return 1800; }
        return 3600;
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

    // The athlete's band for v, from the watch's profile (sex and birth year).
    static function vo2BandNow(v) {
        try {
            var p = UserProfile.getProfile();
            if (p == null || !(p has :gender) || p.gender == null || !(p has :birthYear) || p.birthYear == null) {
                return null;
            }
            var year = Gregorian.info(Time.now(), Time.FORMAT_SHORT).year;
            return vo2Band(v, p.gender == UserProfile.GENDER_FEMALE, year - p.birthYear);
        } catch (e) {}
        return null;
    }

    function onLayout(dc) {
        _g = new Grid(dc);
        Text.init(_g);
    }

    function onShow() {
        Icons.prefetch(Icons.forSession(_ctl.session()));
        flashDots();
    }

    function onHide() {
        if (_dotsTimer != null) { _dotsTimer.stop(); _dotsTimer = null; }
        Icons.release();
        Native.releaseHints();
    }

    // The page dots show for a moment after the page changes, as the watch's.
    hidden function flashDots() {
        _dotsUntil = System.getTimer() + 1500;
        try {
            if (_dotsTimer == null) { _dotsTimer = new Timer.Timer(); }
            _dotsTimer.stop();
            _dotsTimer.start(method(:onDotsTimer), 1600, false);
        } catch (e) {
            // No timer to spare: the dots go at the next redraw instead.
        }
    }

    function onDotsTimer() as Void { Ui.requestUpdate(); }

    function pages() { return _pages; }

    function turn(d) {
        var n = _pages.size();
        _page = ((_page + d) % n + n) % n;
        flashDots();
        Ui.requestUpdate();
    }

    function show(id) {
        for (var i = 0; i < _pages.size(); i += 1) {
            if (_pages[i][0] == id) { _page = i; }
        }
        flashDots();
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

        if (_pages.size() > 1) { Native.nextPage(dc, g, _pages[(_page + 1) % _pages.size()][1]); }
        if (System.getTimer() < _dotsUntil) { Native.pageDots(dc, g, _page, _pages.size()); }
        Native.hint(dc, :start);
    }

    // The activity's icon, the time, then SETS | TOTAL CALORIES — the watch's
    // first page. (The sync's state is the post-save list's Done row.)
    hidden function drawSummary(dc) {
        var g = _g;
        var s = _ctl.session();
        Icons.drawCentered(dc, g.cx, (g.h * 15) / 100, g.iconChip,
                           Icons.forSession(s), Theme.sessionAccent(s));
        Native.text(dc, g.cx, (g.h * 34) / 100, Text.bigNum(), Text.mmss(_ctl.elapsedSec()),
                    Gfx.COLOR_WHITE);
        Native.fields(dc, g, (g.h * 52) / 100, (g.h * 615) / 1000,
                      ["SETS", _ctl.totalSetsLogged().toString()],
                      ["TOTAL CALORIES", _ctl.calories().toString()]);
        Native.vrule(dc, g, g.cx, (g.h * 49) / 100, (g.h * 66) / 100);
    }

    hidden function drawHr(dc) {
        var g = _g;
        Native.pageTitle(dc, g, "HEART RATE");
        var avg = _ctl.avgHR();
        var max = _ctl.peakHR();
        var f = Text.small();
        var nf = Text.hrNum();
        var a = "Avg. ";
        var av = (avg != null) ? avg.toString() : "--";
        var m = " Max. ";
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
        drawChart(dc, (g.w * 18) / 100, (g.h * 36) / 100, (g.w * 56) / 100, (g.h * 30) / 100, avg);
    }

    // The HR over the session as the watch draws it: dotted levels, a line at
    // every time mark, the line coloured by the zone each reading is in over a
    // filled area, the average dashed; the top and the average labelled at the
    // right, the marks' times below.
    hidden function drawChart(dc, x, y, w, h, avg) {
        var g = _g;
        var n = _ctl.hrCount();
        var f = Text.small();
        var total = _ctl.elapsedSec();
        if (n >= 1 && _ctl.hrSecAt(n - 1) > total) { total = _ctl.hrSecAt(n - 1); }
        if (total < 60) { total = 60; }

        dc.setPenWidth(1);
        dc.setColor(0x4A4A4A, Gfx.COLOR_TRANSPARENT);
        for (var i = 0; i <= 3; i += 1) {
            var ly = y + (h * i) / 3;
            for (var dx = 0; dx < w; dx += 6) { dc.drawPoint(x + dx, ly); }
        }
        var step = timeStep(total);
        for (var t = step; t < total; t += step) {
            var tx = x + (w * t) / total;
            dc.setColor(0x4A4A4A, Gfx.COLOR_TRANSPARENT);
            dc.drawLine(tx, y, tx, y + h);
            Native.text(dc, tx, y + h + (g.h * 45) / 1000, f, Text.mmss(t), Gfx.COLOR_WHITE);
        }
        if (n < 2) {
            Native.text(dc, x + (w / 2), y + (h / 2), f, "No HR recorded", Native.DIM);
            return;
        }

        var lo = 999;
        var hi = 0;
        for (var i = 0; i < n; i += 1) {
            var v = _ctl.hrAt(i);
            if (v < lo) { lo = v; }
            if (v > hi) { hi = v; }
        }
        lo = (lo / 10) * 10;
        hi = ((hi + 9) / 10) * 10 + 10;
        if (hi - lo < 30) { lo = hi - 30; }
        var bottom = y + h;

        // One column every 2 px: the reading nearest that moment.
        var pen = (g.h >= 400) ? 3 : 2;
        var px = null;
        var py = null;
        var j = 0;
        for (var cx = 0; cx <= w; cx += 2) {
            var t = (total * cx) / w;
            while (j < n - 1 && _ctl.hrSecAt(j + 1) <= t) { j += 1; }
            var v = _ctl.hrAt(j);
            var cy = bottom - ((h * (v - lo)) / (hi - lo));
            if (px != null) {
                dc.setColor(Native.AREA, Gfx.COLOR_TRANSPARENT);
                dc.fillPolygon([[px, py], [x + cx, cy], [x + cx, bottom], [px, bottom]]);
                dc.setColor(Native.zoneColor(_ctl.zoneOf(v)), Gfx.COLOR_TRANSPARENT);
                dc.setPenWidth(pen);
                dc.drawLine(px, py, x + cx, cy);
            }
            px = x + cx;
            py = cy;
        }

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x + w + 4, y, f, hi.toString(), Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER);
        if (avg != null) {
            var ay = bottom - ((h * (avg - lo)) / (hi - lo));
            dc.setPenWidth(1);
            for (var dx = 0; dx < w; dx += 10) { dc.drawLine(x + dx, ay, x + dx + 5, ay); }
            dc.drawText(x + w + 4, ay, f, avg.toString(), Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER);
        }
    }

    // The watch's zones page: a bar per zone, zone 1 at the left, as tall as its
    // share of the time against the largest, over the average HR; at the right
    // each zone's time and share, zone 5 on top, a tick in its colour between.
    hidden function drawZones(dc) {
        var g = _g;
        Native.pageTitle(dc, g, "HR ZONES");
        var secs = _ctl.zoneSeconds();
        var total = 0;
        var most = 1;
        for (var i = 0; i < secs.size(); i += 1) {
            total += secs[i];
            if (secs[i] > most) { most = secs[i]; }
        }

        var bx = (g.w * 21) / 100;
        var bw = (g.w * 45) / 1000;
        var gap = (g.w * 1) / 100;
        var top = (g.h * 25) / 100;
        var base = (g.h * 47) / 100;
        for (var z = 1; z <= 5; z += 1) {
            var s = secs[z - 1];
            var bh = ((base - top) * s) / most;
            if (bh < 3) { bh = 3; }
            dc.setColor(Native.zoneColor(z), Gfx.COLOR_TRANSPARENT);
            dc.fillRectangle(bx + (z - 1) * (bw + gap), base - bh, bw, bh);
        }
        var mid = bx + ((5 * bw + 4 * gap) / 2);
        var avg = _ctl.avgHR();
        Native.text(dc, mid, (g.h * 575) / 1000, Text.bigNum(), (avg != null) ? avg.toString() : "--",
                    Gfx.COLOR_WHITE);
        Native.text(dc, mid, (g.h * 69) / 100, Text.small(), "AVG. HR", Gfx.COLOR_WHITE);

        var f = Text.line();
        var tick = (g.w * 59) / 100;
        var y = (g.h * 27) / 100;
        var step = (g.h * 94) / 1000;
        for (var z = 5; z >= 1; z -= 1) {
            var s = secs[z - 1];
            var pct = (total > 0) ? ((s * 100) / total) : 0;
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            dc.drawText(tick - (g.w * 12) / 1000, y, f, Text.mmss(s),
                        Gfx.TEXT_JUSTIFY_RIGHT | Gfx.TEXT_JUSTIFY_VCENTER);
            dc.drawText(tick + (g.w * 15) / 1000, y, f, pct.toString() + "%",
                        Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER);
            dc.setColor(Native.zoneColor(z), Gfx.COLOR_TRANSPARENT);
            dc.setPenWidth((g.h >= 400) ? 3 : 2);
            dc.drawLine(tick, y - step / 3, tick, y + step / 3);
            y += step;
        }
    }

    // The benefit word between two blue rules, then the aerobic TE in white.
    hidden function drawTe(dc) {
        var g = _g;
        var v = _ctl.trainingEffect().toFloat();
        Native.pageTitle(dc, g, "TRAINING EFFECT");
        var half = (g.w * 30) / 100;
        dc.setColor(Native.BAND, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth((g.h >= 400) ? 2 : 1);
        dc.drawLine(g.cx - half, (g.h * 28) / 100, g.cx + half, (g.h * 28) / 100);
        dc.drawLine(g.cx - half, (g.h * 40) / 100, g.cx + half, (g.h * 40) / 100);
        Native.text(dc, g.cx, (g.h * 34) / 100, Text.lineBold(), benefit(v), Gfx.COLOR_WHITE);
        Native.text(dc, g.cx, (g.h * 48) / 100, Text.line(), "Aerobic", Gfx.COLOR_WHITE);
        Native.text(dc, g.cx, (g.h * 60) / 100, Text.bigNum(), v.format("%.1f"), Gfx.COLOR_WHITE);
    }

    // VO2 max in its band's colour, then "Recovery: 28hr." with the hours in
    // orange, as the watch writes them.
    hidden function drawStatus(dc) {
        var g = _g;
        Native.pageTitle(dc, g, "TRAINING STATUS");
        var v = vo2max();
        var h = recoveryHours();
        if (v != null) {
            Native.text(dc, g.cx, (g.h * 38) / 100, Text.line(), "VO2 Max.", Gfx.COLOR_WHITE);
            Native.text(dc, g.cx, (g.h * 50) / 100, Text.bigNum(), v.toString(), vo2Color(vo2BandNow(v)));
        }
        if (h != null) {
            var f = Text.line();
            var a = "Recovery: ";
            var b = h.toString();
            var c = "hr.";
            var w = dc.getTextWidthInPixels(a, f) + dc.getTextWidthInPixels(b, f) + dc.getTextWidthInPixels(c, f);
            var x = g.cx - (w / 2);
            var y = (v != null) ? (g.h * 66) / 100 : (g.h * 48) / 100;
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            dc.drawText(x, y, f, a, Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER);
            x += dc.getTextWidthInPixels(a, f);
            dc.setColor(Native.Z4, Gfx.COLOR_TRANSPARENT);
            dc.drawText(x, y, f, b, Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER);
            x += dc.getTextWidthInPixels(b, f);
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            dc.drawText(x, y, f, c, Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER);
        }
    }

    hidden function drawExercises(dc) {
        var g = _g;
        Native.pageTitle(dc, g, "EXERCISES");
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
