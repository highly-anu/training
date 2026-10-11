using Toybox.Lang;

// The screen an exercise is drawn with, from its package's spec.
//
// A today-session fetched with ?spec=1 carries, per session, a table of resolved
// screen specs (src/watch_spec.py) and, per exercise, the key of its spec. The
// spec says which template runs the step (the engine mode), which fields fill the
// data page, what the lines under the rule say and what LAP does; the ids are the
// vocabulary in data/commons/watch_vocabulary.json, generated into Vocab.mc.
//
// A payload without specs (an older server, a cached day from 1.3) gets the
// vocabulary's default for the slot type -- the same table the server resolves
// from -- and an id this build does not know falls back to the template default,
// field by field, so a newer server never blanks a screen.
module ScreenSpec {

    const KEYS = ["a", "b", "gauge", "lines", "lap", "title"];

    function synthesise(slotType) {
        return Vocab.templateDefaults(Vocab.templateFor(slotType));
    }

    function forExercise(ex as Lang.Dictionary, screens) {
        var slotType = ex.hasKey("slotType") ? ex["slotType"] : null;
        var key = ex.hasKey("screen") ? ex["screen"] : null;
        var spec = (key != null && screens instanceof Lang.Dictionary && screens.hasKey(key))
            ? screens[key] : null;
        if (!(spec instanceof Lang.Dictionary)) { return synthesise(slotType); }

        var t = spec.hasKey("template") ? spec["template"] : null;
        var base = Vocab.templateDefaults(t);
        if (base == null) { return synthesise(slotType); }

        // Unknown ids from a newer vocabulary: the template's default instead.
        var out = {};
        var all = spec.keys();
        for (var i = 0; i < all.size(); i += 1) { out[all[i]] = spec[all[i]]; }
        for (var k = 0; k < KEYS.size(); k += 1) {
            var name = KEYS[k];
            if (!out.hasKey(name) || out[name] == null) { out[name] = base[name]; continue; }
            if ((name.equals("a") || name.equals("b") || name.equals("gauge"))
                    && !Vocab.isField(out[name])) {
                out[name] = base[name];
            }
            if (name.equals("lap") && Vocab.actionsFor(t).indexOf(out[name]) < 0) {
                out[name] = base[name];
            }
        }
        return out;
    }
}
