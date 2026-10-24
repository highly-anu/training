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

    // Ring, the glance as it was until 1.12: a label over one line.
    //
    //   not synced   TRAINING             Open to sync
    //   rest day     REST DAY  3/5 THIS WK   Tomorrow: Ruck  90 min
    //   none done    TODAY  3 SESSIONS    SOF Strength A  55 min
    //   some done    TODAY  1 OF 3 DONE   Next: PT Test Prep  25 min
    //   all done     TODAY  DONE  3/5 THIS WK   3 sessions  1:42  17 sets
    //   evening      TOMORROW  3/5 THIS WK   Ruck  90 min
    //
    // The week's count joins the label only once the day itself is no longer the
    // message: on a rest day, in the evening and once the day is done.
    function ring(d) {
        var st = d[:st];
        var n = d[:n];
        if (st == :todo) {
            return ["TODAY" + ((n > 1) ? ("  " + n + " SESSIONS") : ""), describe(d[:next])];
        }
        if (st == :some) {
            return ["TODAY  " + d[:done] + " OF " + n + " DONE", "Next: " + describe(d[:next])];
        }
        if (st == :evening) {
            return ["TOMORROW" + weekTag(d), describeDay(d[:tomorrow])];
        }
        if (st == :done) {
            return ["TODAY  DONE" + weekTag(d), sessionsDone(d, "  ")
                    + ((d[:sets] > 0) ? ("  " + d[:sets] + " sets") : "")];
        }
        if (st == :rest) {
            var t = d[:tomorrow];
            return ["REST DAY" + weekTag(d), (t != null) ? ("Tomorrow: " + describeDay(t)) : "Recover well"];
        }
        return ["TRAINING", "Open to sync"];
    }

    // Next up: what to do next, in three lines (the third left out when the
    // glance is too short for it).
    //
    //   none done    TODAY · 1/2       SOF Strength A    55 min · 3/5 this wk
    //   some done    TODAY · 2/2       PT Test Prep      25 min · 4/5 this wk
    //   all done     TODAY · DONE      2 sessions · 1:10    17 sets · 5/5 this wk
    //   evening      TOMORROW          Ruck  +1          90 min · 5/5 this wk
    //   rest day     REST DAY          Tomorrow: Ruck    90 min · 3/5 this wk
    //
    // "+1": tomorrow holds another session after its first.
    function nextUp(d) {
        var st = d[:st];
        var n = d[:n];
        if (st == :todo || st == :some) {
            var s = d[:next];
            return ["TODAY" + ((n > 1) ? (" · " + (d[:done] + 1) + "/" + n) : ""),
                    name(s), join(minutes(s) + " min", weekText(d))];
        }
        if (st == :done) {
            return ["TODAY · DONE", sessionsDone(d, " · "),
                    join((d[:sets] > 0) ? (d[:sets] + " sets") : null, weekText(d))];
        }
        if (st == :evening) {
            var t = d[:tomorrow];
            return ["TOMORROW", dayName(t) + more(t), join(dayMinutes(t), weekText(d))];
        }
        if (st == :rest) {
            var t = d[:tomorrow];
            if (t == null) { return ["REST DAY", "Recover well", weekText(d)]; }
            return ["REST DAY", "Tomorrow: " + dayName(t) + more(t), join(dayMinutes(t), weekText(d))];
        }
        return ["TRAINING", "Open to sync", null];
    }

    // Day bar: a title over the bar (a segment per session, or on a rest day per
    // session of the week, whose count the title carries) and one line under it.
    //
    //   none done    TODAY             2 left · 1h 10m
    //   some done    TODAY             1 left · 25 min
    //   all done     TODAY · DONE      1:42 · 17 sets
    //   evening      TODAY · DONE      Tomorrow: Ruck  +1
    //   rest day     REST DAY · 3/5    Tomorrow: Ruck  +1
    function bar(d) {
        var st = d[:st];
        if (st == :todo || st == :some) {
            return ["TODAY", (d[:n] - d[:done]) + " left · " + hmLong(d[:left])];
        }
        if (st == :done) {
            return ["TODAY · DONE", hm(d[:mins]) + ((d[:sets] > 0) ? (" · " + d[:sets] + " sets") : "")];
        }
        if (st == :evening) {
            var t = d[:tomorrow];
            return ["TODAY · DONE", "Tomorrow: " + dayName(t) + more(t)];
        }
        if (st == :rest) {
            var t = d[:tomorrow];
            var w = week(d);
            return [(w != null) ? ("REST DAY · " + w[0] + "/" + w[1]) : "REST DAY",
                    (t != null) ? ("Tomorrow: " + dayName(t) + more(t)) : "Recover well"];
        }
        return ["TRAINING", "Open to sync"];
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

    // "3/5 this wk", or null.
    function weekText(d) {
        var w = week(d);
        return (w == null) ? null : (w[0] + "/" + w[1] + " this wk");
    }

    // "  3/5 THIS WK", or nothing.
    function weekTag(d) {
        var w = weekText(d);
        return (w == null) ? "" : ("  " + w.toUpper());
    }

    function sessionsDone(d, sep) {
        var n = d[:n];
        return n + ((n == 1) ? " session" : " sessions") + sep + hm(d[:mins]);
    }

    function join(a, b) {
        if (a == null) { return b; }
        if (b == null) { return a; }
        return a + " · " + b;
    }

    function minutes(s) {
        return (s != null && s.hasKey("estimatedMinutes") && s["estimatedMinutes"] != null)
               ? s["estimatedMinutes"] : 0;
    }

    function name(s) {
        return (s != null && s.hasKey("archetypeName") && s["archetypeName"] != null)
               ? s["archetypeName"] : "";
    }

    function describe(s) {
        if (s == null) { return ""; }
        return name(s) + "  " + minutes(s) + " min";
    }

    function count(t) {
        return (t != null && t.hasKey("sessionCount") && t["sessionCount"] != null) ? t["sessionCount"] : 0;
    }

    function describeDay(t) {
        var n = count(t);
        if (n == 0) { return "Rest day"; }
        return describe(t) + ((n > 1) ? ("  +" + (n - 1)) : "");
    }

    // Tomorrow's first session, or "Rest day".
    function dayName(t) { return (count(t) == 0) ? "Rest day" : name(t); }

    // "  +1" when the day holds more than its first session, else nothing.
    function more(t) {
        var n = count(t);
        return (n > 1) ? ("  +" + (n - 1)) : "";
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
