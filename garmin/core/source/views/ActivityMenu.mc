using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Lang;

// hold UP on the pre-start page: the activity menu, built as Garmin builds its
// own — the system Menu2 (so the rows, icons, focus band and scrolling are the
// watch's), under a header with the activity's icon, name and a rule in its
// colour.
//
//   Workout    the session's steps
//   Today      pick another of the day's sessions (when there is more than one)
//   Week       today and the six days after it, each day's sessions, each
//              session's steps (the demo's programme, or the synced week)
//   Programme  the demo's programme: SOF, Kettlebell or Uphill (demo only)
//   Progress   this program week's sessions done, the programme's share done,
//              and the methodology's own measure (real programme only)
//   Readiness  today's score
//   Sync       re-fetch today (real programme only)
function openActivityMenu(view) {
    var s = view.current();
    var m = new Ui.Menu2({ :title => new ActivityHeader(s) });
    if (s != null) {
        var n = s.exerciseCount();
        m.addItem(new Ui.IconMenuItem("Workout", n.toString() + ((n == 1) ? " exercise" : " exercises"),
                                      :workout, Native.icon(Rez.Drawables.GmList), {}));
        var all = view.sessions();
        if (all != null && all.size() > 1) {
            m.addItem(new Ui.IconMenuItem("Today", all.size().toString() + " sessions",
                                          :today, Native.icon(Rez.Drawables.GmToday), {}));
        }
    }
    if (view.week() != null) {
        m.addItem(new Ui.IconMenuItem("Week", view.weekTitle(), :week, Native.icon(Rez.Drawables.GmWeek), {}));
    }
    if (DemoSession.enabled()) {
        m.addItem(new Ui.IconMenuItem("Programme", DemoProgram.programName(), :programme,
                                      Native.icon(Rez.Drawables.GmList), {}));
    }
    var p = view.progress();
    if (p != null) {
        m.addItem(new Ui.IconMenuItem("Progress", progressLine(p), :progress,
                                      Native.icon(Rez.Drawables.GmCheck), {}));
    }
    var r = view.readiness();
    if (r != null && r.hasKey("score") && r["score"] != null) {
        m.addItem(new Ui.IconMenuItem("Readiness", r["score"].toString() + "  " + readinessWord(r["status"]),
                                      :readiness, Native.icon(Rez.Drawables.GmReadiness), {}));
    }
    if (!DemoSession.enabled()) {
        m.addItem(new Ui.IconMenuItem("Sync", "today's session", :sync, Native.icon(Rez.Drawables.GmRefresh), {}));
    }
    Ui.pushView(m, new ActivityMenuDelegate(view), Ui.SLIDE_LEFT);
}

// "3/5 this week · 29%" — the Progress row's sublabel.
function progressLine(p) {
    var parts = [];
    var wk = p["week"];
    if (wk instanceof Lang.Dictionary && wk["sessions"] != null && wk["sessions"] > 0) {
        parts.add(wk["done"].toString() + "/" + wk["sessions"].toString() + " this week");
    }
    var pr = p["program"];
    if (pr instanceof Lang.Dictionary && pr["pct"] != null) {
        parts.add(pr["pct"].toString() + "%");
    }
    var out = "";
    for (var i = 0; i < parts.size(); i += 1) { out += ((i > 0) ? " · " : "") + parts[i]; }
    return out;
}

// The Progress page: the system list again, each row a label over its value.
//
//   This week   3 of 5 done · 4 due
//   Programme   2 of 7 done · 29%
//   <measure>   the methodology's headline sentence, and its trend
//
// The words are the server's (today-session's `progress`, the headline from
// the cached analytics document) — the phone's and the web's Today say the
// same sentence.
function openProgress(p) {
    var m = new Ui.Menu2({ :title => "Progress" });
    var wk = p["week"];
    if (wk instanceof Lang.Dictionary && wk["sessions"] != null) {
        m.addItem(new Ui.MenuItem("This week",
            wk["done"].toString() + " of " + wk["sessions"].toString() + " done · "
            + wk["due"].toString() + " due", :week, {}));
    }
    var pr = p["program"];
    if (pr instanceof Lang.Dictionary && pr["due"] != null && pr["due"] > 0) {
        m.addItem(new Ui.MenuItem("Programme",
            pr["done"].toString() + " of " + pr["due"].toString() + " done"
            + ((pr["pct"] != null) ? (" · " + pr["pct"].toString() + "%") : ""), :program, {}));
    }
    var h = p["headline"];
    if (h instanceof Lang.Dictionary && h["label"] != null) {
        var text = (h["text"] != null) ? h["text"] : "Not measured yet";
        m.addItem(new Ui.MenuItem(h["label"], text, :headline, {}));
        if (h["trendText"] != null) {
            m.addItem(new Ui.MenuItem("Trend", h["trendText"], :trend, {}));
        }
    }
    Ui.pushView(m, new InfoMenuDelegate(), Ui.SLIDE_LEFT);
}

// A list that only shows: selecting a row does nothing, BACK closes it.
class InfoMenuDelegate extends Ui.Menu2InputDelegate {
    function initialize() { Menu2InputDelegate.initialize(); }
    function onSelect(item) {}
    function onBack() { Ui.popView(Ui.SLIDE_RIGHT); }
}

function readinessWord(status) {
    if (status == null) { return ""; }
    if (status.equals("green"))  { return "Ready"; }
    if (status.equals("yellow")) { return "Moderate"; }
    if (status.equals("red"))    { return "Low"; }
    return "";
}

// START on the pre-start page: Garmin's workout menu.
//
//   Do Workout   the workout screen, ready; START there starts the timer
//   Steps        every exercise; select one to set its reps / hold, weight, RPE
function openWorkoutMenu(view) {
    var s = view.current();
    if (s == null) { return; }
    var m = new Ui.Menu2({ :title => new ActivityHeader(s) });
    m.addItem(new Ui.IconMenuItem("Do Workout", null, :go, Native.icon(Rez.Drawables.GmResume), {}));
    m.addItem(new Ui.IconMenuItem("Steps", "set reps and weights", :steps,
                                  Native.icon(Rez.Drawables.GmEdit), {}));
    Ui.pushView(m, new WorkoutStartDelegate(view), Ui.SLIDE_LEFT);
}

// A session's steps as a system list, name over prescription. Selecting an
// exercise with something to set (reps, a hold, a load, an RPE) opens its editor.
function openSessionSteps(s) { openSteps(s, true); }

// editable false: a day from the Week menu, shown but not set up — those
// exercise objects are not the ones a workout would run.
function openSteps(s, editable) {
    var m = new Ui.Menu2({ :title => "Steps" });
    var list = s.exercises();
    for (var i = 0; i < list.size(); i += 1) {
        var ex = list[i];
        if (ex.slotType().equals("amrap_movement") && ex.parentSlotRole() != null) { continue; }
        m.addItem(new Ui.MenuItem(ex.name(), Steps.overview(ex), i, {}));
    }
    Ui.pushView(m, new StepsMenuDelegate(list, editable), Ui.SLIDE_LEFT);
}

class WorkoutStartDelegate extends Ui.Menu2InputDelegate {
    hidden var _view;
    function initialize(view) {
        Menu2InputDelegate.initialize();
        _view = view;
    }
    function onSelect(item) {
        var id = item.getId();
        if (id == :go) {
            _view.startFirstSession();
        } else if (id == :steps) {
            var s = _view.current();
            if (s != null) { $.openSessionSteps(s); }
        }
    }
    function onBack() { Ui.popView(Ui.SLIDE_RIGHT); }
}

class StepsMenuDelegate extends Ui.Menu2InputDelegate {
    hidden var _list;
    hidden var _editable;
    function initialize(list, editable) {
        Menu2InputDelegate.initialize();
        _list = list;
        _editable = editable;
    }
    function onSelect(item) {
        if (!_editable) { return; }
        var ex = _list[item.getId()];
        if (Steps.isSetBased(ex) || ex.weightKg() != null || ex.targetRpm() != null
                || ex.targetRpe() != null) {
            $.editPlan(ex, item);
        }
    }
    function onBack() { Ui.popView(Ui.SLIDE_RIGHT); }
}

// The header: icon, name, length, and the rule in the activity's colour.
class ActivityHeader extends Ui.Drawable {

    hidden var _s;

    function initialize(s) {
        Drawable.initialize({});
        _s = s;
    }

    function draw(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        if (_s == null) {
            dc.drawText(cx, h / 2, Text.line(), "Training", Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
            return;
        }
        var accent = Theme.sessionAccent(_s);
        var icon = (w * 67) / 1000;
        Icons.drawCentered(dc, cx, (h * 22) / 100, icon, Icons.categoryKey(_s.archetypeCategory()), accent);
        var nw = (w * 62) / 100;
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 52) / 100, Text.lineBold(), Clip.fit(dc, _s.archetypeName(), Text.lineBold(), nw),
                    Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, (h * 76) / 100, Text.small(),
                    Clip.fit(dc, _s.estimatedMinutes().toString() + " min  " + _s.exerciseCount().toString()
                                 + " exercises", Text.small(), (w * 72) / 100),
                    Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
        dc.setColor(accent, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth((h >= 120) ? 3 : 2);
        dc.drawLine((w * 10) / 100, h - 3, (w * 90) / 100, h - 3);
    }
}

class ActivityMenuDelegate extends Ui.Menu2InputDelegate {

    hidden var _view;

    function initialize(view) {
        Menu2InputDelegate.initialize();
        _view = view;
    }

    function onSelect(item) {
        var id = item.getId();
        if (id == :workout) {
            var s = _view.current();
            if (s != null) { $.openSessionSteps(s); }
        } else if (id == :today) {
            var m = new Ui.Menu2({ :title => "Today" });
            var all = _view.sessions();
            for (var i = 0; i < all.size(); i += 1) {
                var s2 = all[i];
                var sub = s2.estimatedMinutes().toString() + " min";
                if (i == _view.index()) {
                    m.addItem(new Ui.IconMenuItem(s2.archetypeName(), sub, i, Native.icon(Rez.Drawables.GmCheck), {}));
                } else {
                    m.addItem(new Ui.MenuItem(s2.archetypeName(), sub, i, {}));
                }
            }
            Ui.pushView(m, new TodayMenuDelegate(_view), Ui.SLIDE_LEFT);
        } else if (id == :week) {
            openWeek();
        } else if (id == :programme) {
            var m2 = new Ui.Menu2({ :title => "Programme" });
            var cur = DemoProgram.current();
            for (var k = 0; k < DemoProgram.IDS.size(); k += 1) {
                var pid = DemoProgram.IDS[k];
                if (pid.equals(cur)) {
                    m2.addItem(new Ui.IconMenuItem(DemoProgram.NAMES[k], null, pid,
                                                   Native.icon(Rez.Drawables.GmCheck), {}));
                } else {
                    m2.addItem(new Ui.MenuItem(DemoProgram.NAMES[k], null, pid, {}));
                }
            }
            Ui.pushView(m2, new ProgrammeMenuDelegate(_view), Ui.SLIDE_LEFT);
        } else if (id == :progress) {
            var p = _view.progress();
            if (p != null) { $.openProgress(p); }
        } else if (id == :readiness) {
            var rv = new ReadinessView(_view.readiness());
            Ui.pushView(rv, new PopDelegate(), Ui.SLIDE_LEFT);
        } else if (id == :sync) {
            Ui.popView(Ui.SLIDE_RIGHT);
            _view.refresh();
        }
    }

    function onBack() { Ui.popView(Ui.SLIDE_RIGHT); }

    hidden function openWeek() {
        var days = _view.week();
        if (days == null) { return; }
        var m = new Ui.Menu2({ :title => _view.weekTitle() });
        for (var i = 0; i < days.size(); i += 1) {
            var d = days[i];
            var n = d["sessions"].size();
            var sub = (n == 0) ? "Rest day"
                : (d["title"] + "  " + Clip.dayMinutes(d).toString() + " min");
            m.addItem(new Ui.MenuItem(Native.dayName(d["offset"]), sub, i, {}));
        }
        Ui.pushView(m, new WeekMenuDelegate(days), Ui.SLIDE_LEFT);
    }
}

// Pick a demo programme, and go straight back to the pre-start page showing its
// day 0.
class ProgrammeMenuDelegate extends Ui.Menu2InputDelegate {
    hidden var _view;
    function initialize(view) {
        Menu2InputDelegate.initialize();
        _view = view;
    }
    function onSelect(item) {
        DemoProgram.select(item.getId());
        _view.reloadDemo();
        Ui.popView(Ui.SLIDE_IMMEDIATE);
        Ui.popView(Ui.SLIDE_RIGHT);
    }
    function onBack() { Ui.popView(Ui.SLIDE_RIGHT); }
}

class TodayMenuDelegate extends Ui.Menu2InputDelegate {
    hidden var _view;
    function initialize(view) {
        Menu2InputDelegate.initialize();
        _view = view;
    }
    // Pick a session, and go straight back to the pre-start page showing it.
    function onSelect(item) {
        _view.select(item.getId());
        Ui.popView(Ui.SLIDE_IMMEDIATE);
        Ui.popView(Ui.SLIDE_RIGHT);
    }
    function onBack() { Ui.popView(Ui.SLIDE_RIGHT); }
}

class WeekMenuDelegate extends Ui.Menu2InputDelegate {
    hidden var _days;
    function initialize(days) {
        Menu2InputDelegate.initialize();
        _days = days;
    }
    function onSelect(item) {
        var d = _days[item.getId()];
        var ss = d["sessions"];
        if (ss.size() == 0) { return; }
        var m = new Ui.Menu2({ :title => Native.dayName(d["offset"]) });
        for (var i = 0; i < ss.size(); i += 1) {
            var s = ss[i];
            m.addItem(new Ui.MenuItem(s.archetypeName(),
                                      s.estimatedMinutes().toString() + " min  "
                                          + s.exerciseCount().toString() + " exercises", i, {}));
        }
        Ui.pushView(m, new DayMenuDelegate(ss), Ui.SLIDE_LEFT);
    }
    function onBack() { Ui.popView(Ui.SLIDE_RIGHT); }
}

class DayMenuDelegate extends Ui.Menu2InputDelegate {
    hidden var _sessions;
    function initialize(sessions) {
        Menu2InputDelegate.initialize();
        _sessions = sessions;
    }
    function onSelect(item) { $.openSteps(_sessions[item.getId()], false); }
    function onBack() { Ui.popView(Ui.SLIDE_RIGHT); }
}

class PopDelegate extends Ui.BehaviorDelegate {
    function initialize() { BehaviorDelegate.initialize(); }
    function onBack()   { Ui.popView(Ui.SLIDE_RIGHT); return true; }
    function onSelect() { Ui.popView(Ui.SLIDE_RIGHT); return true; }
}

// Today's readiness on its own page: the score in its colour inside an arc.
class ReadinessView extends Ui.View {

    hidden var _r;
    hidden var _g;

    function initialize(r) {
        View.initialize();
        _r = r;
    }

    function onLayout(dc) {
        _g = new Grid(dc);
        Text.init(_g);
    }

    function onUpdate(dc) {
        Native.clear(dc);
        if (_g == null) { _g = new Grid(dc); Text.init(_g); }
        var g = _g;
        Native.text(dc, g.cx, (g.h * 18) / 100, Text.small(), "READINESS", Gfx.COLOR_WHITE);
        if (_r == null || !_r.hasKey("score") || _r["score"] == null) {
            Native.text(dc, g.cx, g.cy, Text.line(), "No reading yet", Native.DIM);
            return;
        }
        var col = Theme.readiness(_r["status"]);
        var score = _r["score"];
        Ring.drawProgress(dc, g.cx, g.cy, g.ringR, g.ringPen, 0x2A2A2E, col,
                          score.toFloat() / 100.0, true);
        Native.text(dc, g.cx, (g.h * 47) / 100, Text.bigNum(), score.toString(), col);
        Native.text(dc, g.cx, (g.h * 66) / 100, Text.line(), $.readinessWord(_r["status"]), col);
    }
}
