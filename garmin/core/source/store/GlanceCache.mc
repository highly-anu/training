using Toybox.Application.Storage;
using Toybox.Lang;

// The glance's own copy of today: only the keys GlanceView reads.
//
// The glance runs in 64 KB. Reading the whole today-session payload there (every
// exercise, and since 1.4 every screen spec) put the glance one long session away
// from running out of memory, so the app writes this slim copy whenever it stores
// a day, and the glance never touches the full one.
module GlanceCache {

    const SESSION_KEYS = ["sessionId", "completed", "modalityId", "archetypeName", "estimatedMinutes"];

    function write(today as Lang.Dictionary) as Void {
        var out = { "status" => today["status"], "date" => today["date"],
                    "tomorrow" => today["tomorrow"] };
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
                slim.add(t);
            }
            out["sessions"] = slim;
        }
        Storage.setValue(Config.KEY_TODAY_GLANCE, out);
    }
}
