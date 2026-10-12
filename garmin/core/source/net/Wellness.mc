using Toybox.ActivityMonitor;
using Toybox.Lang;
using Toybox.SensorHistory;
using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.UserProfile;

// Reads today's wellness signals for POST /api/health/wellness (src/wellness.py
// validates them; the keys below are its body keys).
//
// Every call here ran on the athlete's fēnix 9 Pro in garmin/WellnessSpike
// (docs/roadmap.md, item 2, "Results so far"): UserProfile's restingHeartRate
// is the zone *setting* (46 on three mornings while the watch showed 46, 45,
// 49), so the server stores it for display and never scores it — the HR low
// below is the watch's resting-HR signal; averageRestingHeartRate is Garmin's
// 7-day average;
// SensorHistory's getMin()/getMax() return numbers equal to a full walk of the
// samples, so this does not walk them; the heart-rate history holds six hours,
// so a reading taken late in the day has already lost the night's low — the
// server keeps the lowest value of the day across posts for that reason.
//
// Each signal is read on its own: one that throws or is missing leaves its key
// out instead of losing the rest.
module Wellness {

    const HR_WINDOW_SEC = 8 * 3600;    // asks for 8 h; the watch keeps 6
    const BB_WINDOW_SEC = 12 * 3600;

    // The athlete's local day, which is the day the server files the reading
    // under. (SessionListView's todayDateStr is the UTC day, on purpose: it
    // matches /user/today-session.)
    function localDate() {
        var i = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        return i.year.format("%04d") + "-" + i.month.format("%02d") + "-" + i.day.format("%02d");
    }

    function history(which) {
        if (!(Toybox has :SensorHistory)) { return null; }
        var opts = {
            :period => new Time.Duration(which == 0 ? HR_WINDOW_SEC : BB_WINDOW_SEC),
            :order => SensorHistory.ORDER_NEWEST_FIRST
        };
        if (which == 0 && (SensorHistory has :getHeartRateHistory)) {
            return SensorHistory.getHeartRateHistory(opts);
        }
        if (which == 1 && (SensorHistory has :getBodyBatteryHistory)) {
            return SensorHistory.getBodyBatteryHistory(opts);
        }
        return null;
    }

    // Only a value inside the bounds src/wellness.FIELDS accepts: one value
    // outside them makes the server refuse the whole reading (422), so a
    // resting HR of 0 on a profile without one would cost the Body Battery
    // and recovery time read beside it.
    function put(d, key, v, lo, hi) {
        if (v == null) { return; }
        var n = v.toNumber();
        if (n >= lo && n <= hi) { d[key] = n; }
    }

    // The request body, or null when nothing at all could be read (the server
    // refuses a reading with no metric).
    function read() {
        var d = { "date" => localDate(), "readAt" => Time.now().value() };
        var metrics = 0;

        try {
            var p = UserProfile.getProfile();
            if (p != null) {
                if (p has :restingHeartRate) { put(d, "restingHr", p.restingHeartRate, 25, 200); }
                if (p has :averageRestingHeartRate) { put(d, "restingHr7dAvg", p.averageRestingHeartRate, 25, 200); }
                if (p has :vo2maxRunning) { put(d, "vo2max", p.vo2maxRunning, 10, 100); }
            }
        } catch (ex) {}

        try {
            var info = ActivityMonitor.getInfo();
            if (info != null && (info has :timeToRecovery)) { put(d, "recoveryTimeH", info.timeToRecovery, 0, 240); }
        } catch (ex) {}

        try {
            var it = history(0);
            if (it != null) { put(d, "hrMin", it.getMin(), 25, 230); }
        } catch (ex) {}

        try {
            var it = history(1);
            if (it != null) {
                put(d, "bodyBatteryMax", it.getMax(), 0, 100);
                put(d, "bodyBatteryMin", it.getMin(), 0, 100);
                var s = it.next();    // newest first
                if (s != null) { put(d, "bodyBatteryLatest", s.data, 0, 100); }
            }
        } catch (ex) {}

        try {
            var ds = System.getDeviceSettings();
            d["partNumber"] = ds.partNumber;
            var fw = ds.firmwareVersion;
            // "6.49", as the spike's NOW page showed it.
            if (fw != null && fw.size() >= 2) { d["firmware"] = fw[0].toString() + "." + fw[1].toString(); }
        } catch (ex) {}

        var keys = ["restingHr", "restingHr7dAvg", "vo2max", "recoveryTimeH", "hrMin",
                    "bodyBatteryMax", "bodyBatteryMin", "bodyBatteryLatest"];
        for (var i = 0; i < keys.size(); i++) {
            if (d.hasKey(keys[i])) { metrics++; }
        }
        return metrics > 0 ? d : null;
    }
}
