using Toybox.Test;
using Toybox.Lang;
using Toybox.Application.Storage;

// The glance's slim copy keeps the program week's two numbers from the
// server's `progress.week`, and nothing else of `progress`. Run with
// build.sh --test.

(:test)
function glanceCacheKeepsTheWeekCounts(logger as Test.Logger) as Lang.Boolean {
    var keep = Storage.getValue(Config.KEY_TODAY_GLANCE);

    GlanceCache.write({ "status" => "ok", "date" => "2026-10-16", "sessions" => [],
                        "progress" => { "week" => { "number" => 2, "of" => 12, "done" => 3, "due" => 4, "sessions" => 5 },
                                        "headline" => { "text" => "Back squat 102.5kg" } } });
    var g = Storage.getValue(Config.KEY_TODAY_GLANCE) as Lang.Dictionary;
    Test.assertEqualMessage(g["week"][0], 3, "done");
    Test.assertEqualMessage(g["week"][1], 5, "sessions in the week");
    Test.assertMessage(!g.hasKey("progress"), "the glance copy carries no headline");

    GlanceCache.write({ "status" => "ok", "date" => "2026-10-16", "sessions" => [] });
    g = Storage.getValue(Config.KEY_TODAY_GLANCE) as Lang.Dictionary;
    Test.assertMessage(!g.hasKey("week"), "an older server's day has no week");

    Storage.setValue(Config.KEY_TODAY_GLANCE, keep);
    return true;
}
