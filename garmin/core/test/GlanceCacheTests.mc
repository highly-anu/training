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

// A session of a modality its package brings itself is drawn in the colour the
// server sends with it (modalityDisplay); it used to be grey. The package's
// accent token still wins, and a commons session keeps no accent.
(:test)
function glanceCacheKeepsAServedModalityColour(logger as Test.Logger) as Lang.Boolean {
    var keep = Storage.getValue(Config.KEY_TODAY_GLANCE);

    GlanceCache.write({ "status" => "ok", "date" => "2026-11-24", "sessions" => [
        { "sessionId" => "1-Monday-0", "modalityId" => "zz_trail", "exercises" => [],
          "modalityDisplay" => { "label" => "Trail", "color" => "#0ea5e9", "family" => "aerobic" } },
        { "sessionId" => "1-Monday-1", "modalityId" => "zz_trail", "exercises" => [],
          "watch" => { "accent" => "amber" }, "modalityDisplay" => { "color" => "#0ea5e9" } },
        { "sessionId" => "1-Monday-2", "modalityId" => "max_strength", "exercises" => [] } ],
        "tomorrow" => { "dayName" => "Tuesday", "sessionCount" => 1, "modalityId" => "zz_trail",
                        "modalityDisplay" => { "color" => "#0ea5e9" } } });
    var g = Storage.getValue(Config.KEY_TODAY_GLANCE) as Lang.Dictionary;
    var ss = g["sessions"] as Lang.Array;
    Test.assertEqualMessage(ss[0]["accent"], 0x0EA5E9, "the served colour");
    Test.assertEqualMessage(ss[1]["accent"], Vocab.colour("amber"), "the package's accent first");
    Test.assertMessage(!(ss[2] as Lang.Dictionary).hasKey("accent"), "a commons modality keeps its compiled colour");
    Test.assertEqualMessage(g["tomorrow"]["accent"], 0x0EA5E9, "tomorrow's too");
    Test.assertMessage(Theme.servedColour({ "color" => "sky" }) == null, "anything but #rrggbb is no colour");

    Storage.setValue(Config.KEY_TODAY_GLANCE, keep);
    return true;
}
