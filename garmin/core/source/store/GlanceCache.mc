using Toybox.Application.Storage;
using Toybox.Lang;

// The glance's own copy of today: only the keys GlanceView reads.
//
// The glance runs in 64 KB. Reading the whole today-session payload there (every
// exercise, and since 1.4 every screen spec) put the glance one long session away
// from running out of memory, so the app writes this slim copy whenever it stores
// a day, and the glance never touches the full one.
module GlanceCache {

    const SESSION_KEYS = ["sessionId", "completed", "modalityId", "archetypeName", "estimatedMinutes",
                          "icon", "archetypeCategory"];

    function write(today as Lang.Dictionary) as Void {
        var out = { "status" => today["status"], "date" => today["date"],
                    "tomorrow" => today["tomorrow"] };
        // A demo day carries its own readiness and is never stale; it lives only
        // here, so the real cached day and readiness survive demo mode.
        if (today.hasKey("demo")) { out["demo"] = today["demo"]; out["readiness"] = today["readiness"]; }
        // This program week's sessions done and in all ("3/5 THIS WK"): two
        // numbers from the server's `progress.week`, nothing else of it.
        var progress = today["progress"];
        if (progress instanceof Lang.Dictionary && progress["week"] instanceof Lang.Dictionary) {
            var wk = progress["week"] as Lang.Dictionary;
            out["week"] = [wk["done"], wk["sessions"]];
        }
        var sessions = today["sessions"];
        if (sessions instanceof Lang.Array) {
            var slim = [];
            for (var i = 0; i < sessions.size(); i += 1) {
                var s = sessions[i] as Lang.Dictionary;
                var t = {};
                for (var k = 0; k < SESSION_KEYS.size(); k += 1) {
                    var key = SESSION_KEYS[k];
                    if (s.hasKey(key)) { t[key] = s[key]; }
                }
                // The card's "4 ex", and the colour the pre-start page draws the
                // session in (its package's accent), resolved here: the glance
                // cannot afford Vocab or Theme.
                var ex = s["exercises"];
                if (ex instanceof Lang.Array) { t["exerciseCount"] = ex.size(); }
                var w = s["watch"];
                if (w instanceof Lang.Dictionary && w.hasKey("accent")) {
                    var c = Vocab.colour(w["accent"]);
                    if (c != null) { t["accent"] = c; }
                }
                slim.add(t);
            }
            out["sessions"] = slim;
        }
        Storage.setValue(Config.KEY_TODAY_GLANCE, out);
    }

    // Demo mode is off: put the real cached day back where the demo's was.
    function restoreReal() as Void {
        var g = Storage.getValue(Config.KEY_TODAY_GLANCE) as Lang.Dictionary?;
        if (g == null || g["demo"] != true) { return; }
        var real = Storage.getValue(Config.KEY_TODAY_SESSION) as Lang.Dictionary?;
        if (real != null) { write(real); } else { Storage.deleteValue(Config.KEY_TODAY_GLANCE); }
    }
}
