using Toybox.Test;
using Toybox.Lang;
using Toybox.Application.Storage;
using Toybox.Time;
using Toybox.Time.Gregorian;

// The cached day and week: only today's day stands in when a sync fails, and a
// week fetched earlier is re-based on today. Run with build.sh --test.

(:test)
function daysBetweenCountsCalendarDays(logger as Test.Logger) as Lang.Boolean {
    Test.assertEqual(SyncCache.daysBetween("2026-10-12", "2026-10-13"), 1);
    Test.assertEqual(SyncCache.daysBetween("2026-10-12", "2026-10-12"), 0);
    Test.assertEqual(SyncCache.daysBetween("2026-10-13", "2026-10-12"), -1);
    Test.assertEqualMessage(SyncCache.daysBetween("2026-09-28", "2026-10-04"), 6, "across a month end");
    Test.assertEqual(SyncCache.daysBetween("2026-12-31", "2027-01-01"), 1);
    Test.assert(SyncCache.daysBetween("garbage", "2026-10-12") == null);
    return true;
}

// Only the test build compiles core/test, so this needs no annotation.
function testYmd(offsetDays) {
    var i = Gregorian.info(Time.now().add(new Time.Duration(offsetDays * 86400)), Time.FORMAT_SHORT);
    return i.year.format("%04d") + "-" + i.month.format("%02d") + "-" + i.day.format("%02d");
}

(:test)
function yesterdaysCacheIsNotToday(logger as Test.Logger) as Lang.Boolean {
    var keepDay = Storage.getValue(Config.KEY_TODAY_SESSION);
    var keepDate = Storage.getValue(Config.KEY_TODAY_DATE);

    Storage.setValue(Config.KEY_TODAY_SESSION, { "status" => "ok", "sessions" => [] });
    Storage.setValue(Config.KEY_TODAY_DATE, testYmd(-1));
    Test.assertMessage(SyncCache.cachedToday() == null, "yesterday's rest day must not stand in for today");
    Storage.setValue(Config.KEY_TODAY_DATE, Config.localDate());
    Test.assert(SyncCache.cachedToday() != null);

    Storage.setValue(Config.KEY_TODAY_SESSION, keepDay);
    Storage.setValue(Config.KEY_TODAY_DATE, keepDate);
    return true;
}

(:test)
function aWeekFetchedEarlierStartsAtToday(logger as Test.Logger) as Lang.Boolean {
    var keepWeek = Storage.getValue(Config.KEY_WEEK);
    var keepDate = Storage.getValue(Config.KEY_TODAY_DATE);

    var days = [];
    for (var k = 0; k < 7; k += 1) {
        days.add({ "offset" => k, "title" => "d" + k.toString(), "sessions" => [] });
    }
    Storage.setValue(Config.KEY_WEEK, days);

    Storage.setValue(Config.KEY_TODAY_DATE, testYmd(-2));      // fetched two days ago
    var wk = SyncCache.cachedWeek();
    Test.assertEqual(wk.size(), 5);
    Test.assertEqual(wk[0]["offset"], 0);
    Test.assertEqualMessage(wk[0]["title"], "d2", "today is the fetch's third day");

    Storage.setValue(Config.KEY_TODAY_DATE, testYmd(-7));      // a week ago: nothing left
    Test.assert(SyncCache.cachedWeek() == null);

    Storage.setValue(Config.KEY_WEEK, keepWeek);
    Storage.setValue(Config.KEY_TODAY_DATE, keepDate);
    return true;
}

// The couldn't-sync page and the Sync row name a failure in words, with its code.
(:test)
function syncReasonNamesTheCode(logger as Test.Logger) as Lang.Boolean {
    Test.assertEqual(SyncCache.reason(-104), "No phone (-104)");
    Test.assertEqual(SyncCache.reason(-300), "Timed out (-300)");
    Test.assertEqual(SyncCache.reason(-402), "Too large (-402)");
    Test.assertEqual(SyncCache.reason(401), "Not paired (401)");
    Test.assertEqual(SyncCache.reason(502), "Server error (502)");
    Test.assertEqual(SyncCache.reason(-7), "Watch error (-7)");
    Test.assertEqual(SyncCache.reason(null), "No reply");
    return true;
}

(:test)
function syncLineSaysHowTheLastSyncWent(logger as Test.Logger) as Lang.Boolean {
    var keep = Storage.getValue(Config.KEY_LAST_SYNC);
    Storage.deleteValue(Config.KEY_LAST_SYNC);
    Test.assertEqual(SyncCache.syncLine(), "today's session");
    SyncCache.recordSync(200);
    Test.assert(SyncCache.syncLine().find("ok ") == 0);
    SyncCache.recordSync(-104);
    var line = SyncCache.syncLine();
    Test.assert(line.find("failed ") == 0 && line.find("No phone (-104)") != null);
    if (keep != null) { Storage.setValue(Config.KEY_LAST_SYNC, keep); } else { Storage.deleteValue(Config.KEY_LAST_SYNC); }
    return true;
}
