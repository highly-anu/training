using Toybox.Test;
using Toybox.Lang;

// What the glance's two cards say on hand-built days (GlanceDay). Run with
// build.sh --test.

function glanceDay(sessions, week) {
    var d = { "status" => "ok", "sessions" => sessions,
              "tomorrow" => { "sessionCount" => 2, "modalityId" => "aerobic_base",
                              "archetypeName" => "Ruck", "estimatedMinutes" => 90,
                              "archetypeCategory" => "conditioning", "exerciseCount" => 5 } };
    if (week != null) { d["week"] = week; }
    return d;
}

function glanceSession(id, name, mins, completed) {
    return { "sessionId" => id, "archetypeName" => name, "estimatedMinutes" => mins,
             "modalityId" => "max_strength", "completed" => completed,
             "archetypeCategory" => "kettlebell", "exerciseCount" => 4 };
}

(:test)
function glanceSaysWhatIsNext(logger as Test.Logger) as Lang.Boolean {
    var today = glanceDay([glanceSession("a", "SOF Strength A", 55, true),
                           glanceSession("b", "PT Test Prep", 25, false)], [3, 5]);
    var d = GlanceDay.read(today, {}, false);
    Test.assertEqualMessage(d[:st], :some, "one of two done");
    var c = GlanceDay.nextUp(d);
    Test.assertEqualMessage(c[0], "Today · 2/2", "the next is the second of two");
    Test.assertEqualMessage(c[1][0], :session, "the session's own icon");
    Test.assertEqualMessage(c[1][1], "25 min", "its minutes");
    Test.assertEqualMessage(c[1][2]["sessionId"], "b", "the icon is the next session's");
    Test.assertEqualMessage(c[2][1], "4 ex", "its exercises");
    c = GlanceDay.bar(d);
    Test.assertEqualMessage(c[0], "Today · 1/2", "Day bar counts what is done");
    Test.assertEqualMessage(c[1], "25 min", "and the time left");
    return true;
}

(:test)
function glanceCountsWhatThisWatchSaved(logger as Test.Logger) as Lang.Boolean {
    var today = glanceDay([glanceSession("a", "SOF Strength A", 55, false),
                           glanceSession("b", "PT Test Prep", 25, false)], [3, 5]);
    // Both saved here, the server not told yet: 62 + 30 minutes, 17 sets.
    var d = GlanceDay.read(today, { "a" => [62, 12], "b" => [30, 5] }, false);
    Test.assertEqualMessage(d[:st], :done, "both done");
    var c = GlanceDay.nextUp(d);
    Test.assertEqualMessage(c[0], "Today · Done", "done");
    Test.assertEqualMessage(c[1][0], :check, "a tick");
    Test.assertEqualMessage(c[1][1], "1:32", "the time this watch recorded");
    Test.assertEqualMessage(c[2][1], "17 sets", "and the sets");
    Test.assertEqualMessage(GlanceDay.bar(d)[1], "1:32", "Day bar's value");

    // No sets logged: the week, with both counted.
    d = GlanceDay.read(today, { "a" => [62, 0], "b" => [30, 0] }, false);
    Test.assertEqualMessage(GlanceDay.nextUp(d)[2][1], "5/5 wk", "the week instead of sets");
    return true;
}

(:test)
function glanceLooksAheadInTheEvening(logger as Test.Logger) as Lang.Boolean {
    var today = glanceDay([glanceSession("a", "SOF Strength A", 55, true)], null);
    var d = GlanceDay.read(today, {}, true);
    Test.assertEqualMessage(d[:st], :evening, "done, after the evening hour");
    var c = GlanceDay.nextUp(d);
    Test.assertEqualMessage(c[0], "Tomorrow · 2", "tomorrow, and its two sessions");
    Test.assertEqualMessage(c[1][1], "90 min", "its first session's minutes");
    Test.assertEqualMessage(c[1][2]["archetypeName"], "Ruck", "drawn with tomorrow's icon");
    Test.assertEqualMessage(c[2][1], "5 ex", "its exercises");
    Test.assertEqualMessage(GlanceDay.bar(d)[0], "Tomorrow", "Day bar looks ahead too");
    Test.assertEqualMessage(GlanceDay.bar(d)[1], "90 min", "with tomorrow's minutes");

    // An older server's tomorrow has no count: no second pair without a week.
    today["tomorrow"].remove("exerciseCount");
    Test.assertMessage(GlanceDay.nextUp(GlanceDay.read(today, {}, true))[2] == null, "nothing to show");
    return true;
}

(:test)
function glanceOnARestDayAndUnsynced(logger as Test.Logger) as Lang.Boolean {
    var d = GlanceDay.read(glanceDay([], [2, 4]), {}, false);
    Test.assertEqualMessage(d[:st], :rest, "no sessions today");
    var c = GlanceDay.nextUp(d);
    Test.assertEqualMessage(c[0], "Rest day", "rest day");
    Test.assertEqualMessage(c[1][1], "2/4 wk", "the week");
    Test.assertEqualMessage(c[2][1], "Tmrw", "and what tomorrow is, by its icon");
    c = GlanceDay.bar(d);
    Test.assertEqualMessage(c[0], "Rest day", "Day bar draws the week");
    Test.assertEqualMessage(c[1], "2/4 wk", "and counts it");

    d = GlanceDay.read(null, {}, false);
    Test.assertEqualMessage(d[:st], :none, "no copy");
    c = GlanceDay.nextUp(d);
    Test.assertEqualMessage(c[1][1], "Open to sync", "asks for a sync");
    Test.assertMessage(c[2] == null, "one pair");
    Test.assertEqualMessage(GlanceDay.hmLong(70), "1h 10m", "time left as a duration");
    Test.assertEqualMessage(GlanceDay.hmLong(120), "2h", "and a whole hour without the minutes");
    return true;
}
