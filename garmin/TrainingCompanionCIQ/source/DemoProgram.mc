using Toybox.Lang;
using Toybox.WatchUi as Ui;
using Toybox.Application.Storage;

// The demo programmes, so the pre-start page, the week, the workout screens and
// the summary can be walked without an account:
//
//   sof      SOF selection prep: strength, PT-test prep, rucks, conditioning, and
//            day 0's every-slot-type showcase
//   kb       Wildman Kettlebell: ballistics at a target RPM, double-bell strength,
//            anti-glycolic swings (rest until HR is down), pentathlon sets with a
//            hand switch, get-ups, movement skill
//   uphill   Uphill Athlete: threshold and VO2 hill intervals, zone-2 steps with
//            warm-up and cool-down, ME step-ups, a weighted ruck, a mountain day
//
// Each is a JSON resource (resources/jsonData/demo_*.json) in exactly the shape of
// the server's today-session payload, and only the chosen one is loaded. Day 0 is
// today and the week runs forward from it, so "today" is always a training day.
// The choice is kept in Storage.
//
// Views only: never reach this from the app class or the glance — the glance build
// links everything the app class can reach into a 64 KB budget.
module DemoProgram {

    const KEY = "demoProgramme";
    const IDS = ["sof", "kb", "uphill"];
    const NAMES = ["SOF Selection Prep", "Wildman Kettlebell", "Uphill Athlete"];

    var _data = null;
    var _loaded = null;

    function current() {
        var id = Storage.getValue(KEY);
        return (id != null && IDS.indexOf(id) >= 0) ? id : "sof";
    }

    function select(id) {
        if (IDS.indexOf(id) < 0) { return; }
        Storage.setValue(KEY, id);
        _data = null;
        _loaded = null;
    }

    function data() {
        var id = current();
        if (_data == null || _loaded == null || !_loaded.equals(id)) {
            var rid = Rez.JsonData.DemoSof;
            if (id.equals("kb"))     { rid = Rez.JsonData.DemoKb; }
            if (id.equals("uphill")) { rid = Rez.JsonData.DemoUphill; }
            _data = Ui.loadResource(rid);
            _loaded = id;
        }
        return _data;
    }

    // Set by build.sh --demo (HHMM of the build), so a photo says which build ran.
    function stamp()        { return "b" + data()["stamp"]; }
    function programName()  { return data()["name"]; }
    function programPhase() { return data()["phase"]; }

    // [ { "offset", "title", "sessions" => [WorkoutSession] } ]
    function week() {
        var raw = data()["days"];
        var out = [];
        for (var i = 0; i < raw.size(); i += 1) {
            var ss = [];
            var rs = raw[i]["sessions"];
            for (var j = 0; j < rs.size(); j += 1) { ss.add(new WorkoutSession(rs[j])); }
            out.add({ "offset" => raw[i]["offset"], "title" => raw[i]["title"], "sessions" => ss });
        }
        return out;
    }

    // The glance reads the cached today payload (it never loads this module), so
    // write day 0's sessions and day 1's first in that shape.
    function seedGlanceCache() {
        var days = data()["days"];
        var today = [];
        var d0 = days[0]["sessions"];
        for (var i = 0; i < d0.size(); i += 1) {
            var s = d0[i];
            // Exercise count only: the glance runs in 64 KB and reads nothing else.
            var ph = new [s["exercises"].size()];
            for (var k = 0; k < ph.size(); k += 1) { ph[k] = {}; }
            today.add({ "sessionId" => s["sessionId"], "modalityId" => s["modalityId"],
                        "archetypeName" => s["archetypeName"],
                        "estimatedMinutes" => s["estimatedMinutes"],
                        "exercises" => ph });
        }
        var tomorrow = null;
        if (days.size() > 1) {
            var d1 = days[1]["sessions"];
            if (d1.size() == 0) {
                tomorrow = { "sessionCount" => 0 };
            } else {
                tomorrow = { "sessionCount" => d1.size(), "modalityId" => d1[0]["modalityId"],
                             "archetypeName" => d1[0]["archetypeName"],
                             "estimatedMinutes" => d1[0]["estimatedMinutes"] };
            }
        }
        Storage.setValue(Config.KEY_TODAY_SESSION,
                         { "status" => "ok", "sessions" => today, "tomorrow" => tomorrow });
        Storage.setValue(Config.KEY_READINESS, DemoSession.readiness());
    }
}
