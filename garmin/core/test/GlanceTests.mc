using Toybox.Test;
using Toybox.Lang;

// What the glance's three styles say on hand-built days (GlanceDay). Run with
// build.sh --test.

function glanceDay(sessions, week) {
    var d = { "status" => "ok", "sessions" => sessions,
              "tomorrow" => { "sessionCount" => 2, "modalityId" => "aerobic_base",
                              "archetypeName" => "Ruck", "estimatedMinutes" => 90 } };
    if (week != null) { d["week"] = week; }
    return d;
}

function glanceSession(id, name, mins, completed) {
    return { "sessionId" => id, "archetypeName" => name, "estimatedMinutes" => mins,
             "modalityId" => "max_strength", "completed" => completed };
}

(:test)
function glanceSaysWhatIsNext(logger as Test.Logger) as Lang.Boolean {
    var today = glanceDay([glanceSession("a", "SOF Strength A", 55, true),
                           glanceSession("b", "PT Test Prep", 25, false)], [3, 5]);
    var d = GlanceDay.read(today, {}, false);
    Test.assertEqualMessage(d[:st], :some, "one of two done");
    var l = GlanceDay.nextUp(d);
    Test.assertEqualMessage(l[0], "TODAY · 2/2", "the next is the second of two");
    Test.assertEqualMessage(l[1], "PT Test Prep", "its name");
    Test.assertEqualMessage(l[2], "25 min · 3/5 this wk", "its minutes and the week");
    l = GlanceDay.bar(d);
    Test.assertEqualMessage(l[1], "1 left · 25 min", "what is left");
    l = GlanceDay.ring(d);
    Test.assertEqualMessage(l[0], "TODAY  1 OF 2 DONE", "Ring keeps its words");
    Test.assertEqualMessage(l[1], "Next: PT Test Prep  25 min", "Ring's next");
    return true;
}

(:test)
function glanceCountsWhatThisWatchSaved(logger as Test.Logger) as Lang.Boolean {
    var today = glanceDay([glanceSession("a", "SOF Strength A", 55, false),
                           glanceSession("b", "PT Test Prep", 25, false)], [3, 5]);
    // Both saved here, the server not told yet: 62 + 30 minutes, 17 sets.
    var d = GlanceDay.read(today, { "a" => [62, 12], "b" => [30, 5] }, false);
    Test.assertEqualMessage(d[:st], :done, "both done");
    var l = GlanceDay.nextUp(d);
    Test.assertEqualMessage(l[0], "TODAY · DONE", "done");
    Test.assertEqualMessage(l[1], "2 sessions · 1:32", "the time this watch recorded");
    Test.assertEqualMessage(l[2], "17 sets · 5/5 this wk", "sets, and the week with both counted");
    Test.assertEqualMessage(GlanceDay.bar(d)[1], "1:32 · 17 sets", "Day bar's line");
    Test.assertEqualMessage(GlanceDay.ring(d)[0], "TODAY  DONE  5/5 THIS WK", "Ring's label");
    return true;
}

(:test)
function glanceLooksAheadInTheEvening(logger as Test.Logger) as Lang.Boolean {
    var today = glanceDay([glanceSession("a", "SOF Strength A", 55, true)], null);
    var d = GlanceDay.read(today, {}, true);
    Test.assertEqualMessage(d[:st], :evening, "done, after the evening hour");
    var l = GlanceDay.nextUp(d);
    Test.assertEqualMessage(l[0], "TOMORROW", "tomorrow");
    Test.assertEqualMessage(l[1], "Ruck  +1", "tomorrow's first session, and one more");
    Test.assertEqualMessage(l[2], "90 min", "its minutes; no week without one");
    Test.assertEqualMessage(GlanceDay.bar(d)[1], "Tomorrow: Ruck  +1", "Day bar's line");
    return true;
}

(:test)
function glanceOnARestDayAndUnsynced(logger as Test.Logger) as Lang.Boolean {
    var d = GlanceDay.read(glanceDay([], [2, 4]), {}, false);
    Test.assertEqualMessage(d[:st], :rest, "no sessions today");
    var l = GlanceDay.nextUp(d);
    Test.assertEqualMessage(l[0], "REST DAY", "rest day");
    Test.assertEqualMessage(l[1], "Tomorrow: Ruck  +1", "tomorrow");
    Test.assertEqualMessage(l[2], "90 min · 2/4 this wk", "tomorrow's minutes and the week");
    l = GlanceDay.bar(d);
    Test.assertEqualMessage(l[0], "REST DAY · 2/4", "Day bar draws the week and counts it");
    Test.assertEqualMessage(l[1], "Tomorrow: Ruck  +1", "and tomorrow under it");
    Test.assertEqualMessage(GlanceDay.ring(d)[1], "Tomorrow: Ruck  90 min  +1", "Ring keeps its words");

    d = GlanceDay.read(null, {}, false);
    Test.assertEqualMessage(d[:st], :none, "no copy");
    Test.assertEqualMessage(GlanceDay.nextUp(d)[1], "Open to sync", "asks for a sync");
    Test.assertEqualMessage(GlanceDay.hmLong(70), "1h 10m", "time left as a duration");
    Test.assertEqualMessage(GlanceDay.hmLong(120), "2h", "and a whole hour without the minutes");
    return true;
}
