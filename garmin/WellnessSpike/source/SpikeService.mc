import Toybox.Application.Storage;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;

// The background half. Runs on every temporal / wake / sleep event, with the app closed:
//   - counts the fire and keeps a per-day summary (fires, first, last, largest gap)
//   - reads every signal in the morning window (04:00-12:00, every fire) and on the first
//     fire of each hour; a line is logged only when a slow signal changed, the rest is counted
//   - once an hour asks the API for a public route to prove the phone-bridged web request
//     works from the background, and notes when a request outlived the 30 s service limit
//   - always ends in Background.exit
(:background)
class SpikeService extends System.ServiceDelegate {
    var _t0 as Number = 0;
    var _tNet as Number = 0;

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void { run("B"); }
    function onWakeTime() as Void { run("W"); }
    function onSleepTime() as Void { run("S"); }

    function run(tag as String) as Void {
        _t0 = System.getTimer();
        var probing = false;
        var runs = 0;
        try {
            var moment = Time.now();
            var now = moment.value();
            var info = Gregorian.info(moment, Time.FORMAT_SHORT);
            var st = Store.stats("bgSt");
            runs = Store.cnt(st, "runs") + 1;
            st["runs"] = runs;
            st["last"] = now;
            if (!st.hasKey("first")) { st["first"] = now; }
            st["ev" + tag] = Store.cnt(st, "ev" + tag) + 1;
            account(now, info);

            var fo = Storage.getValue("fgOpen");
            var fgOpen = (fo instanceof Lang.Number) && (fo as Number) > 0 && (now - (fo as Number)) < 1800;
            var hour = info.hour as Number;
            var firstOfHour = (info.min as Number) < 15;
            var forced = !tag.equals("B");
            if ((hour >= 4 && hour < 12) || firstOfHour || forced) {
                readAndLog(fgOpen ? tag + "f" : tag, forced, st);
            }
            st["rms"] = System.getTimer() - _t0;

            if (firstOfHour) {
                if (Store.cnt(st, "netPending") == 1) { st["netKilled"] = Store.cnt(st, "netKilled") + 1; }
                st["netPending"] = 1;
                _tNet = System.getTimer();
                Store.save("bgSt", st);
                probing = true;
                Net.probe(method(:onProbe));
            } else {
                Store.save("bgSt", st);
            }
        } catch (ex) {
            fail(ex);
            if (probing) { probeFailed(); }
            probing = false;
        }
        if (!probing) { Background.exit({"n" => runs}); }
    }

    // Per-day fire accounting; yesterday's summary goes to the bgDays ring at rollover.
    function account(now as Number, info as Gregorian.Info) as Void {
        var key = (info.year as Number) * 10000 + (info.month as Number) * 100 + (info.day as Number);
        var sod = (info.hour as Number) * 3600 + (info.min as Number) * 60 + (info.sec as Number);
        var dy = Storage.getValue("bgDay") as Dictionary?;
        if (dy == null) { dy = {} as Dictionary; }
        if (dy.hasKey("k") && Store.cnt(dy, "k") != key) {
            Store.push("bgDays", Store.daySummary(dy));
            dy = {} as Dictionary;
        }
        var n = Store.cnt(dy, "n");
        if (n == 0) {
            dy["k"] = key;
            dy["f"] = sod;
            dy["g"] = 0;
        } else {
            var gap = (now - Store.cnt(dy, "p")) / 60;
            if (gap > Store.cnt(dy, "g")) { dy["g"] = gap; }
        }
        dy["n"] = n + 1;
        dy["l"] = sod;
        dy["p"] = now;
        Store.save("bgDay", dy);
    }

    function readAndLog(tag as String, forced as Boolean, st as Dictionary) as Void {
        var d = Reader.read();
        fold(st, d);
        var sg = Reader.sig(d);
        var prev = Storage.getValue("bgSig");
        var skipped = Store.cnt(st, "skip");
        if (forced || prev == null || !sg.equals(prev)) {
            Store.push("bgLog", Reader.line(tag, d, skipped));
            Storage.setValue("bgSig", sg);
            st["skip"] = 0;
            st["logs"] = Store.cnt(st, "logs") + 1;
        } else {
            st["skip"] = skipped + 1;
            st["same"] = Store.cnt(st, "same") + 1;
        }
    }

    // Last-seen diagnostics from a read, plus the peaks that decide the memory question.
    function fold(st as Dictionary, d as Dictionary) as Void {
        st["reads"] = Store.cnt(st, "reads") + 1;
        var keys = ["m0", "m1", "mu", "tot", "bat", "part", "fw", "mv", "ph", "hk1", "hk2", "bk1", "bk2",
                    "hg1", "hg2", "bg1", "bg2", "hseen", "hspan", "bseen", "bspan", "hmin", "hmax", "bmin", "bmax",
                    "hms", "bms", "hn", "bn", "hage", "bage", "ms"];
        for (var i = 0; i < keys.size(); i++) {
            var k = "l" + keys[i];
            var v = d[keys[i]];
            if (v != null) {
                st[k] = v;
            } else if (st.hasKey(k)) {
                st.remove(k);
            }
        }
        var mu = Store.cnt(d, "mu");
        if (mu > Store.cnt(st, "muMax")) { st["muMax"] = mu; }
        var ms = Store.cnt(d, "ms");
        if (ms > Store.cnt(st, "msMax")) { st["msMax"] = ms; }
        if (d.hasKey("err")) {
            st["err"] = d["err"];
            st["errAt"] = d["t"];
            st["errN"] = Store.cnt(st, "errN") + 1;
        }
    }

    function onProbe(code as Number, data as Dictionary or String or Null) as Void {
        try {
            var st = Store.stats("bgSt");
            var ms = System.getTimer() - _tNet;
            st["netPending"] = 0;
            st["code"] = code;
            st["lat"] = ms;
            st["netAt"] = Time.now().value();
            if (Net.answered(code)) {
                st["netOk"] = Store.cnt(st, "netOk") + 1;
            } else {
                st["netFail"] = Store.cnt(st, "netFail") + 1;
            }
            if (ms > Store.cnt(st, "latMax")) { st["latMax"] = ms; }
            st["rms"] = System.getTimer() - _t0;
            Store.save("bgSt", st);
        } catch (ex) {
            fail(ex);
        }
        Background.exit({"n" => 0});
    }

    // makeWebRequest threw before the request left the watch: a failed request, not a killed service.
    function probeFailed() as Void {
        try {
            var st = Store.stats("bgSt");
            st["netPending"] = 0;
            st["netFail"] = Store.cnt(st, "netFail") + 1;
            Store.save("bgSt", st);
        } catch (ex) {
        }
    }

    function fail(ex as Lang.Exception) as Void {
        try {
            var st = Store.stats("bgSt");
            st["bgErr"] = Reader.clip(ex.getErrorMessage(), 24);
            st["bgErrN"] = Store.cnt(st, "bgErrN") + 1;
            Store.save("bgSt", st);
        } catch (ex2) {
        }
    }
}
