using Toybox.Lang;

// What the glance says, apart from how it is drawn: the day read from the
// glance's slim copy (GlanceCache) and the words each style puts on it. Pure,
// so the core's tests run it on hand-built days (GlanceTests.mc).
//
// The day is one of
//
//   :none     not synced, or another day's copy
//   :rest     a rest day
//   :todo     sessions today, none done
//   :some     some done
//   :done     all done
//   :evening  all done, after GLANCE_EVENING_HOUR with tomorrow known
//
// A session is done when this watch saved it (DayLog) or the server says so (a
// log or a matched workout from another device).
(:glance)
module GlanceDay {

    // `today` is the glance copy (null when there is none or it is stale), `log`
    // DayLog.done(), `evening` whether the evening hour has passed.
    function read(today, log, evening) {
        var d = { :st => :none, :n => 0, :done => 0, :flags => null, :sessions => null,
                  :next => null, :first => null, :mins => 0, :left => 0, :sets => 0,
                  :tomorrow => null, :week => null, :localOnly => 0 };
        if (today == null || !today.hasKey("status")) { return d; }
        var status = today["status"] as Lang.String;
        if (!status.equals("ok")) { return d; }
        d[:tomorrow] = today.hasKey("tomorrow") ? today["tomorrow"] : null;
        d[:week] = today.hasKey("week") ? today["week"] : null;
        var sessions = today.hasKey("sessions") ? (today["sessions"] as Lang.Array) : null;
        if (sessions == null || sessions.size() == 0) { d[:st] = :rest; return d; }
        var n = sessions.size();
        var flags = new [n];
        var done = 0;
        var mins = 0;
        var left = 0;
        var sets = 0;
        var local = 0;
        var next = null;
        for (var i = 0; i < n; i += 1) {
            var s = sessions[i] as Lang.Dictionary;
            var id = s.hasKey("sessionId") ? s["sessionId"] : null;
            var server = s.hasKey("completed") && s["completed"] == true;
            var here = id != null && log.hasKey(id);
            flags[i] = server || here;
            // Saved on this watch but not yet counted by the server's progress
            // (the upload and the fetch race; offline it waits).
            if (here && !server) { local += 1; }
            if (flags[i]) {
                done += 1;
                if (here) { mins += log[id][0]; sets += log[id][1]; }
                else { mins += minutes(s); }
            } else {
                left += minutes(s);
                if (next == null) { next = s; }
            }
        }
        d[:n] = n;
        d[:done] = done;
        d[:flags] = flags;
        d[:sessions] = sessions;
        d[:next] = next;
        d[:first] = sessions[0];
        d[:mins] = mins;
        d[:left] = left;
        d[:sets] = sets;
        d[:localOnly] = local;
        if (done == 0) { d[:st] = :todo; }
        else if (done < n) { d[:st] = :some; }
        else if (evening && d[:tomorrow] != null) { d[:st] = :evening; }
        else { d[:st] = :done; }
        return d;
    }

    // Next up, as Garmin's own glance cards: a title over a row of two
    // icon + value pairs. A pair is [glyph, text, session]; the view picks the
    // icon (:session draws the session's own, in its colour) and `session` is
    // the slim session or tomorrow it describes, else null. The second pair may
    // be null.
    //
    //   none done    Today · 1/2       [kettlebell] 55 min   [steps] 4 ex
    //   some done    Today · 2/2       [session] 25 min      [steps] 3 ex
    //   all done     Today · Done      [check] 1:32          [sets] 17 sets
    //   evening      Tomorrow · 2      [session] 90 min      [steps] 5 ex
    //   rest day     Rest day          [week] 2/4 wk         [session] Tmrw
    //   not synced   Training          [sync] Open to sync
    //
    // Without an exercise count (an older server's tomorrow) or sets, the
    // second pair is the week.
    function nextUp(d) {
        var st = d[:st];
        var n = d[:n];
        if (st == :todo || st == :some) {
            var s = d[:next];
            return ["Today" + ((n > 1) ? (" · " + (d[:done] + 1) + "/" + n) : ""),
                    [:session, minutes(s) + " min", s], stepsOr(d, s)];
        }
        if (st == :done) {
            return ["Today · Done", [:check, hm(d[:mins]), null],
                    (d[:sets] > 0) ? [:sets, d[:sets] + " sets", null] : weekPair(d)];
        }
        if (st == :evening) {
            var t = d[:tomorrow];
            var c = count(t);
            return ["Tomorrow" + ((c > 1) ? (" · " + c) : ""),
                    [:session, minutes(t) + " min", t], stepsOr(d, t)];
        }
        if (st == :rest) {
            var t = d[:tomorrow];
            var w = weekPair(d);
            var next = (count(t) > 0) ? [:session, "Tmrw", t] : null;
            if (w == null) { return ["Rest day", (next != null) ? next : [:rest, "Recover", null], null]; }
            return ["Rest day", w, next];
        }
        return ["Training", [:sync, "Open to sync", null], null];
    }

    // Day bar: a title over a row of segments and one value beside them. The
    // segments are the day's sessions (bright once done), tomorrow's on the
    // evening look ahead, and the week's on a rest day; the view draws them
    // from `d`.
    //
    //   none done    Today             ▭▭    1h 20m      (time still to train)
    //   some done    Today · 1/2       ▬▭    25 min
    //   all done     Today · Done      ▬▬    1:32
    //   evening      Tomorrow          ▭▭    90 min
    //   rest day     Rest day          ▬▬▭▭  2/4 wk
    //   not synced   Training          ▭     Sync
    function bar(d) {
        var st = d[:st];
        if (st == :todo || st == :some) {
            return [(st == :some) ? ("Today · " + d[:done] + "/" + d[:n]) : "Today", hmLong(d[:left])];
        }
        if (st == :done) { return ["Today · Done", hm(d[:mins])]; }
        if (st == :evening) {
            var m = dayMinutes(d[:tomorrow]);
            return ["Tomorrow", (m != null) ? m : "Rest"];
        }
        if (st == :rest) {
            var w = week(d);
            return ["Rest day", (w != null) ? (w[0] + "/" + w[1] + " wk") : "Recover"];
        }
        return ["Training", "Sync"];
    }

    // The exercise count of `s`, else the week.
    function stepsOr(d, s) {
        var k = exercises(s);
        return (k > 0) ? [:steps, k + " ex", null] : weekPair(d);
    }

    function weekPair(d) {
        var w = week(d);
        return (w == null) ? null : [:week, w[0] + "/" + w[1] + " wk", null];
    }

    function exercises(s) {
        return (s != null && s.hasKey("exerciseCount") && s["exerciseCount"] != null) ? s["exerciseCount"] : 0;
    }

    // [done, sessions] of the program week, with what this watch saved that the
    // server has not counted yet; null when the copy predates `progress` or the
    // week holds no sessions.
    function week(d) {
        var wk = d[:week];
        if (!(wk instanceof Lang.Array) || wk.size() < 2 || wk[0] == null || wk[1] == null || wk[1] == 0) {
            return null;
        }
        var done = wk[0] + d[:localOnly];
        if (done > wk[1]) { done = wk[1]; }
        return [done, wk[1]];
    }

    function minutes(s) {
        return (s != null && s.hasKey("estimatedMinutes") && s["estimatedMinutes"] != null)
               ? s["estimatedMinutes"] : 0;
    }

    function count(t) {
        return (t != null && t.hasKey("sessionCount") && t["sessionCount"] != null) ? t["sessionCount"] : 0;
    }

    // "90 min", or null on a rest day.
    function dayMinutes(t) { return (count(t) == 0) ? null : (minutes(t) + " min"); }

    // "1:42" for minutes, "45 min" under an hour.
    function hm(m) {
        if (m < 60) { return m + " min"; }
        return (m / 60) + ":" + (m % 60).format("%02d");
    }

    // "1h 10m", "2h", "45 min" under an hour: time still to train reads as a
    // duration.
    function hmLong(m) {
        if (m < 60) { return m + " min"; }
        return (m / 60) + "h" + ((m % 60 == 0) ? "" : (" " + (m % 60) + "m"));
    }
}
