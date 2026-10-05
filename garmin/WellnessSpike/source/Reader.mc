import Toybox.ActivityMonitor;
import Toybox.Lang;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;
import Toybox.UserProfile;

// Reads every candidate wellness signal once and returns a flat dictionary of short keys
// (see README for the legend). Used from the background service and the foreground alike,
// so a value that differs between the two is itself a finding.
(:background)
module Reader {
    const HR_WINDOW = 8 * 3600;
    const HR_CAP = 600;
    const BB_WINDOW = 12 * 3600;
    const BB_CAP = 300;
    const LOW_N = 5;

    // N number, F float, Z null, X anything else.
    function kind(v as Object?) as String {
        if (v == null) { return "Z"; }
        if (v instanceof Lang.Number) { return "N"; }
        if (v instanceof Lang.Float) { return "F"; }
        return "X";
    }

    function used() as Number {
        return System.getSystemStats().usedMemory;
    }

    function iterator(which as Number, windowSec as Number) as SensorHistory.SensorHistoryIterator? {
        if (!(Toybox has :SensorHistory)) { return null; }
        var opts = {
            :period => new Time.Duration(windowSec),
            :order => SensorHistory.ORDER_NEWEST_FIRST
        };
        if (which == 0 && (SensorHistory has :getHeartRateHistory)) { return SensorHistory.getHeartRateHistory(opts); }
        if (which == 1 && (SensorHistory has :getBodyBatteryHistory)) { return SensorHistory.getBodyBatteryHistory(opts); }
        if (which == 2 && (SensorHistory has :getStressHistory)) { return SensorHistory.getStressHistory(opts); }
        if (which == 3 && (SensorHistory has :getOxygenSaturationHistory)) { return SensorHistory.getOxygenSaturationHistory(opts); }
        return null;
    }

    // Walks an iterator newest-first, at most `cap` samples, and writes under prefix `p`:
    //   p+"n" valid samples, p+"min", p+"max", p+"lo" mean of the lowest LOW_N, p+"lat" newest
    //   value, p+"age" newest age (min), p+"span" newest-to-oldest (min), p+"seen" samples visited
    //   (equal to `cap` when the walk stopped early), p+"ms" elapsed, p+"k1"/p+"k2" runtime kind and
    //   p+"g1"/p+"g2" value of getMin()/getMax() (to compare with this walk's own p+"min"/p+"max").
    //   Also raises d["mu"] to the memory in use while the iterator is still alive.
    function walk(it as SensorHistory.SensorHistoryIterator, cap as Number, p as String, d as Dictionary) as Void {
        var t0 = System.getTimer();
        var now = Time.now().value();
        var n = 0;
        var mn = null;
        var mx = null;
        var low = [] as Array<Number>;
        var newest = null;
        var oldest = null;
        var s = it.next();
        var seen = 0;
        while (s != null && seen < cap) {
            seen++;
            var v = s.data;
            if (v != null) {
                var iv = v.toNumber();
                if (n == 0) { d[p + "lat"] = iv; newest = s.when.value(); }
                oldest = s.when.value();
                n++;
                if (mn == null || iv < mn) { mn = iv; }
                if (mx == null || iv > mx) { mx = iv; }
                if (low.size() < LOW_N) {
                    low.add(iv);
                } else {
                    var hi = 0;
                    for (var i = 1; i < low.size(); i++) { if (low[i] > low[hi]) { hi = i; } }
                    if (iv < low[hi]) { low[hi] = iv; }
                }
            }
            s = it.next();
        }
        var m = used();
        if (!d.hasKey("mu") || m > (d["mu"] as Number)) { d["mu"] = m; }
        d[p + "n"] = n;
        d[p + "seen"] = seen;
        d[p + "min"] = mn;
        d[p + "max"] = mx;
        if (low.size() > 0) {
            var sum = 0;
            for (var j = 0; j < low.size(); j++) { sum += low[j]; }
            d[p + "lo"] = sum / low.size();
        }
        if (newest != null) { d[p + "age"] = (now - newest) / 60; }
        if (newest != null && oldest != null) { d[p + "span"] = (newest - oldest) / 60; }
        d[p + "ms"] = System.getTimer() - t0;
        try {
            var gm = it.getMin();
            var gx = it.getMax();
            d[p + "k1"] = kind(gm);
            d[p + "k2"] = kind(gx);
            d[p + "g1"] = gm;
            d[p + "g2"] = gx;
        } catch (ex) {
            d[p + "k1"] = "!";
            d[p + "k2"] = "!";
        }
    }

    // The same HR window through ActivityMonitor, as a second opinion on the SensorHistory read.
    function walkAm(d as Dictionary) as Void {
        if (!(ActivityMonitor has :getHeartRateHistory)) { return; }
        var t0 = System.getTimer();
        var it = ActivityMonitor.getHeartRateHistory(new Time.Duration(HR_WINDOW), true);
        var n = 0;
        var mn = null;
        var seen = 0;
        var s = it.next();
        while (s != null && seen < HR_CAP) {
            seen++;
            var v = s.heartRate;
            if (v != null && v != ActivityMonitor.INVALID_HR_SAMPLE && v > 0) {
                n++;
                if (mn == null || v < mn) { mn = v; }
            }
            s = it.next();
        }
        d["an"] = n;
        d["amin"] = mn;
        d["ams"] = System.getTimer() - t0;
    }

    function clip(s as String?, n as Number) as String {
        if (s == null) { return "?"; }
        return (s.length() <= n) ? s : (s.substring(0, n) as String);
    }

    function ver(a as Array<Number>?) as String {
        if (a == null) { return "?"; }
        var out = "";
        for (var i = 0; i < a.size(); i++) { out += ((i > 0) ? "." : "") + a[i].toString(); }
        return out;
    }

    function fail(d as Dictionary, tag as String, ex as Lang.Exception) as Void {
        var prev = d.hasKey("err") ? (d["err"] as String) + "," : "";
        d["err"] = prev + tag + ":" + clip(ex.getErrorMessage(), 14);
    }

    // One full read. Keys: see README legend. m0 = memory in use before any read, m1 = peak
    // after resting HR + heart-rate history + body battery + recovery (what the real feature
    // would need), mu = peak after the extra signals as well.
    function read() as Dictionary {
        var d = {} as Dictionary;
        var t0 = System.getTimer();
        d["t"] = Time.now().value();
        d["m0"] = used();
        try {
            if (Toybox has :UserProfile) {
                var p = UserProfile.getProfile() as UserProfile.Profile?;
                if (p == null) {
                    d["pnull"] = 1;
                } else {
                    if (p has :restingHeartRate) { d["r"] = p.restingHeartRate; }
                    if (p has :averageRestingHeartRate) { d["a"] = p.averageRestingHeartRate; }
                    if (p has :wakeTime) { var w = p.wakeTime; if (w != null) { d["wk"] = w.value(); } }
                    if (p has :sleepTime) { var sl = p.sleepTime; if (sl != null) { d["sl"] = sl.value(); } }
                    if (p has :upcomingWakeTime) { var uw = p.upcomingWakeTime; if (uw != null) { d["uw"] = uw.value(); } }
                    if (p has :vo2maxRunning) { d["v"] = p.vo2maxRunning; }
                }
            }
        } catch (ex) { fail(d, "pf", ex); }
        try {
            var info = ActivityMonitor.getInfo();
            if (info != null && (info has :timeToRecovery)) { d["tr"] = info.timeToRecovery; }
        } catch (ex) { fail(d, "am", ex); }
        try {
            var it = iterator(0, HR_WINDOW);
            if (it != null) { walk(it, HR_CAP, "h", d); } else { d["hno"] = 1; }
        } catch (ex) { fail(d, "hr", ex); }
        try {
            var it = iterator(1, BB_WINDOW);
            if (it != null) { walk(it, BB_CAP, "b", d); } else { d["bno"] = 1; }
        } catch (ex) { fail(d, "bb", ex); }
        d["m1"] = d.hasKey("mu") ? d["mu"] : used();
        try {
            var it = iterator(2, 3 * 3600);
            if (it != null) { walk(it, 30, "s", d); }
        } catch (ex) { fail(d, "st", ex); }
        try {
            var it = iterator(3, 12 * 3600);
            if (it != null) { walk(it, 30, "o", d); }
        } catch (ex) { fail(d, "ox", ex); }
        try {
            walkAm(d);
        } catch (ex) { fail(d, "ah", ex); }
        try {
            var ds = System.getDeviceSettings();
            d["part"] = ds.partNumber;
            d["fw"] = ver(ds.firmwareVersion);
            d["mv"] = ver(ds.monkeyVersion);
            d["ph"] = ds.phoneConnected ? 1 : 0;
        } catch (ex) { fail(d, "ds", ex); }
        var st = System.getSystemStats();
        d["tot"] = st.totalMemory;
        d["bat"] = st.battery.toNumber();
        var now = used();
        if (!d.hasKey("mu") || now > (d["mu"] as Number)) { d["mu"] = now; }
        d["ms"] = System.getTimer() - t0;
        return d;
    }

    function fmt(d as Dictionary, key as String) as String {
        var v = d[key] as Object?;
        if (v == null) { return "-"; }
        if (v instanceof Lang.Float) { return (v as Float).format("%.1f"); }
        return v.toString();
    }

    // One log line per read: "dd hh:mm<tag>[+skipped] [!errors] r a  h<min>/<lo>#n ha<age>
    // b<max>/<min>/<now>#n ba<age>  tr  w s  am  st  ox  v". Legend in README. The error marker comes
    // first because Store caps a line at MAX_CHARS and it is the tail that gets cut.
    function line(tag as String, d as Dictionary, skipped as Number) as String {
        var out = Store.stamp(d["t"] as Number) + tag;
        if (skipped > 0) { out += "+" + skipped; }
        if (d.hasKey("err")) { out += " !" + fmt(d, "err"); }
        out += " r" + fmt(d, "r") + " a" + fmt(d, "a");
        out += " h" + fmt(d, "hmin") + "/" + fmt(d, "hlo") + "#" + fmt(d, "hn") + " ha" + fmt(d, "hage");
        out += " b" + fmt(d, "bmax") + "/" + fmt(d, "bmin") + "/" + fmt(d, "blat") + "#" + fmt(d, "bn") + " ba" + fmt(d, "bage");
        out += " tr" + fmt(d, "tr");
        out += " w" + Store.hhmm(d["wk"] as Number?) + " s" + Store.hhmm(d["sl"] as Number?);
        out += " am" + fmt(d, "amin") + "#" + fmt(d, "an");
        out += " st" + fmt(d, "slat") + "#" + fmt(d, "sn") + " ox" + fmt(d, "olat") + "#" + fmt(d, "on");
        out += " v" + fmt(d, "v");
        return out;
    }

    // What counts as "a value changed": the slow signals only. Not the newest-sample values, ages or
    // counts, and not the lowest-5 mean, the 12 h Body Battery low or the AM minimum: those drift as
    // the window slides and would log nearly every read.
    function sig(d as Dictionary) as String {
        return fmt(d, "r") + "|" + fmt(d, "a") + "|" + fmt(d, "hmin") + "|" + fmt(d, "bmax") + "|" +
            fmt(d, "tr") + "|" + fmt(d, "wk") + "|" + fmt(d, "sl") + "|" + fmt(d, "v") + "|" + fmt(d, "err");
    }
}
