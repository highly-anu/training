import Toybox.Application.Storage;
import Toybox.Lang;

// What each page of the foreground view says, one String per entry (the view scrolls by entry
// and wraps long ones). Foreground only: nothing here is compiled into the service.
module Pages {
    const COUNT = 5;
    const NAMES = ["NOW", "BG", "LOG", "DAYS", "FG"];

    function entries(page as Number, d as Dictionary?, probe as String) as Array<String> {
        if (page == 0) { return nowPage(d, probe); }
        if (page == 1) { return bgPage(); }
        if (page == 2) { return logPage(); }
        if (page == 3) { return daysPage(); }
        return fgPage();
    }

    function f(d as Dictionary, key as String) as String {
        return Reader.fmt(d, key);
    }

    function at(d as Dictionary, key as String) as String {
        var v = d[key];
        return (v instanceof Lang.Number) ? Store.stamp(v as Number) : "-";
    }

    function newestFirst(a as Array<String>) as Array<String> {
        var out = [] as Array<String>;
        for (var i = a.size() - 1; i >= 0; i--) { out.add(a[i]); }
        return out;
    }

    // A live reading made by the foreground just now: compare it with Garmin Connect, and with
    // what the background logged (LOG).
    function nowPage(d as Dictionary?, probe as String) as Array<String> {
        if (d == null) { return ["reading..."] as Array<String>; }
        var out = [] as Array<String>;
        out.add("read " + at(d, "t") + "  " + f(d, "ms") + " ms");
        out.add("RHR " + f(d, "r") + "  avg " + f(d, "a") + "  VO2 " + f(d, "v"));
        out.add("HR 8h  min " + f(d, "hmin") + "  max " + f(d, "hmax") + "  low5 " + f(d, "hlo") + "  n" + f(d, "hn") +
            "  newest " + f(d, "hlat") + " (" + f(d, "hage") + "m)");
        out.add("AM 8h  min " + f(d, "amin") + "  n" + f(d, "an"));
        out.add("BB 12h  max " + f(d, "bmax") + "  min " + f(d, "bmin") + "  now " + f(d, "blat") +
            "  n" + f(d, "bn") + " (" + f(d, "bage") + "m)");
        out.add("Recovery " + f(d, "tr") + " h");
        out.add("Wake " + Store.hhmm(d["wk"] as Number?) + "  sleep " + Store.hhmm(d["sl"] as Number?) +
            "  next wake " + at(d, "uw"));
        out.add("Stress " + f(d, "slat") + " n" + f(d, "sn") + "  SpO2 " + f(d, "olat") + " n" + f(d, "on"));
        out.add("walk hr " + f(d, "hseen") + "/" + Reader.HR_CAP + " span " + f(d, "hspan") + "m  bb " +
            f(d, "bseen") + "/" + Reader.BB_CAP + " span " + f(d, "bspan") + "m");
        out.add("getMin/Max hr " + f(d, "hg1") + "/" + f(d, "hg2") + " (" + f(d, "hk1") + f(d, "hk2") +
            ")  bb " + f(d, "bg1") + "/" + f(d, "bg2") + " (" + f(d, "bk1") + f(d, "bk2") + ")");
        out.add("mem start " + f(d, "m0") + "  read " + f(d, "m1") + "  peak " + f(d, "mu") + "  of " + f(d, "tot"));
        out.add("time hr " + f(d, "hms") + " ms  bb " + f(d, "bms") + " ms");
        out.add("dev " + f(d, "part") + "  fw " + f(d, "fw") + "  mv " + f(d, "mv") + "  phone " + f(d, "ph"));
        out.add("api " + probe);
        if (d.hasKey("err")) { out.add("ERR " + f(d, "err")); }
        return out;
    }

    // The service's own counters: did it run, when, how long, how much memory, did the request return.
    function bgPage() as Array<String> {
        var s = Store.stats("bgSt");
        if (s.size() == 0) { return ["no background run recorded yet"] as Array<String>; }
        var out = [] as Array<String>;
        out.add("runs " + f(s, "runs") + "  B" + f(s, "evB") + " W" + f(s, "evW") + " S" + f(s, "evS"));
        out.add("first " + at(s, "first") + "  last " + at(s, "last"));
        out.add("reads " + f(s, "reads") + "  logged " + f(s, "logs") + "  unchanged " + f(s, "same"));
        out.add("api ok " + f(s, "netOk") + "  fail " + f(s, "netFail") + "  killed " + f(s, "netKilled") +
            "  pending " + f(s, "netPending"));
        out.add("api last " + f(s, "code") + "  " + f(s, "lat") + " ms  worst " + f(s, "latMax") +
            " ms  at " + at(s, "netAt"));
        out.add("run " + f(s, "rms") + " ms  read " + f(s, "lms") + "  hr " + f(s, "lhms") + "  bb " + f(s, "lbms"));
        out.add("mem start " + f(s, "lm0") + "  read " + f(s, "lm1") + "  peak " + f(s, "muMax") + "  of " + f(s, "ltot"));
        out.add("hr n" + f(s, "lhn") + " seen " + f(s, "lhseen") + "/" + Reader.HR_CAP + " span " + f(s, "lhspan") +
            "m age " + f(s, "lhage") + "m  min " + f(s, "lhmin") + " max " + f(s, "lhmax"));
        out.add("bb n" + f(s, "lbn") + " seen " + f(s, "lbseen") + "/" + Reader.BB_CAP + " span " + f(s, "lbspan") +
            "m age " + f(s, "lbage") + "m  min " + f(s, "lbmin") + " max " + f(s, "lbmax"));
        out.add("getMin/Max hr " + f(s, "lhg1") + "/" + f(s, "lhg2") + " (" + f(s, "lhk1") + f(s, "lhk2") +
            ")  bb " + f(s, "lbg1") + "/" + f(s, "lbg2") + " (" + f(s, "lbk1") + f(s, "lbk2") + ")");
        out.add("dev " + f(s, "lpart") + "  fw " + f(s, "lfw") + "  mv " + f(s, "lmv"));
        out.add("phone " + f(s, "lph") + "  batt " + f(s, "lbat") + " %");
        if (s.hasKey("err")) { out.add("read err " + f(s, "err") + "  x" + f(s, "errN") + "  at " + at(s, "errAt")); }
        if (s.hasKey("bgErr")) { out.add("service err " + f(s, "bgErr") + "  x" + f(s, "bgErrN")); }
        return out;
    }

    // The background's value lines, newest first. A line is written only when a slow signal
    // changed (see the README legend), so a quiet day is a short list.
    function logPage() as Array<String> {
        var a = Store.lines("bgLog");
        if (a.size() == 0) { return ["no background reading logged yet"] as Array<String>; }
        return newestFirst(a);
    }

    // One line per day: how many times the service ran, first and last time, longest gap.
    // "*" is today, still counting.
    function daysPage() as Array<String> {
        var out = [] as Array<String>;
        var dy = Storage.getValue("bgDay") as Dictionary?;
        if (dy != null) { out.add("*" + Store.daySummary(dy)); }
        out.addAll(newestFirst(Store.lines("bgDays")));
        if (out.size() == 0) { out.add("no background run recorded yet"); }
        return out;
    }

    function fgPage() as Array<String> {
        var s = Store.stats("fgSt");
        var out = [] as Array<String>;
        out.add("opens " + f(s, "opens") + "  first " + at(s, "firstOpen"));
        out.add("last open " + at(s, "lastOpen") + "  closed " + at(s, "lastClose"));
        out.add("data from service " + f(s, "bgData") + "  last " + at(s, "bgDataAt"));
        out.add("api ok " + f(s, "fOk") + "  fail " + f(s, "fFail") + "  last " + f(s, "fcode") + "  " + f(s, "flat") + " ms");
        out.addAll(newestFirst(Store.lines("fgLog")));
        return out;
    }
}
