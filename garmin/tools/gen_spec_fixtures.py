#!/usr/bin/env python3
"""Generate garmin/core/test/SpecFixtures.mc from data/watch_fixtures.json.

The fixtures say what each watch draws for a step: title, fields, lines and what
LAP does. The Apple Watch runs them in ios/TrainingCompanionTests/WatchSpecTests;
this turns them into a Connect IQ (:test) that runs each through the Garmin's
SpecRenderer, with a stand-in controller answering from the case's state — so a
screen is changed in the JSON, and both renderers are held to it.

    python3 garmin/tools/gen_spec_fixtures.py          # write
    python3 garmin/tools/gen_spec_fixtures.py --check  # exit 1 if the file is stale
    garmin/TrainingCompanionCIQ/build.sh --test        # run (the simulator open)
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, 'garmin', 'tools'))
import gen_vocab  # noqa: E402


def mc(v) -> str:
    """gen_vocab's Monkey C literal, with strings written as UTF-8 ("97.5kg × 5")."""
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, list):
        return '[' + ', '.join(mc(x) for x in v) + ']'
    if isinstance(v, dict):
        return '{ ' + ', '.join(f'{mc(k)} => {mc(x)}' for k, x in v.items()) + ' }' if v else '{}'
    return gen_vocab.mc(v)

SRC = os.path.join(ROOT, 'data', 'watch_fixtures.json')
OUT = os.path.join(ROOT, 'garmin', 'core', 'test', 'SpecFixtures.mc')

CTL = '''// The renderer's view of the workout, answered from a case's state. What the
// real controller derives (Run / Recover, the work and rest values) is restated
// here from WorkoutController.mc, so the fixtures test the renderer, not it.
class SpecFixtureCtl {
    hidden var s;
    hidden var ex;
    hidden var calls;

    function initialize(state, exercise) { s = state; ex = exercise; calls = []; }

    hidden function v(k, d) { return s.hasKey(k) ? s[k] : d; }

    function editReps()             { return v("reps", 0); }
    function editWeight()           { return v("weightKg", null); }
    function editRpe()              { return v("rpe", 0); }
    function currentSetCount()      { return v("setsDone", 0); }
    function setsDoneFor(e)         { return v("setsDone", 0); }
    function state()                { return v("resting", false) ? WorkoutController.RESTING : WorkoutController.ACTIVE; }
    function sideIsLeft()           { return v("sideIsLeft", true); }
    function amrapRounds()          { return v("rounds", 0); }
    function repsDoneFor(e)         { return v("repsDone", 0); }
    function exerciseRemainingSec() { return v("capLeftSec", 0); }
    function exerciseElapsedSec()   { return v("elapsedSec", 0); }
    function distanceKm()           { return v("distanceKm", 0); }
    function holdRunning()          { return v("holdRunning", false); }
    function holdRemaining()        { return v("holdLeftSec", 0); }
    function holdTarget()           { var h = ex.holdSeconds(); return (h != null) ? h : 30; }
    function intervalWorking()      { return v("intervalWorking", true); }
    function emomRound()            { return v("intervalRound", 1); }
    function roundName(e) {
        var alt = e.alternateName();
        return (alt != null && e.isTemplate("interval") && WorkoutController.alternatesAt(emomRound())) ? alt : e.name();
    }
    function emomTotal()            { return v("intervalTotal", 0); }
    function intervalLeft()         { return v("intervalLeftSec", 0); }
    function intervalRestSec()      { return v("intervalRestSec", 0); }
    function gateRest()             { return v("gateRest", false); }
    function restPhaseElapsed()     { return v("restPhaseElapsedSec", 0); }
    function currentHR()            { return v("heartRate", null); }
    function nextStep()             { return [v("nextTitle", "Finish"), v("nextValue", null)]; }

    function componentsForCurrent() {
        var out = [];
        var cs = v("components", []);
        for (var i = 0; i < cs.size(); i += 1) { out.add(new WorkoutExercise(cs[i], null, null)); }
        return out;
    }

    function isRunInterval(e) {
        return e != null && e.zoneLower() != null && e.targetRpm() == null && isLocomotion(e);
    }
    hidden function isLocomotion(e) {
        var c = e.category();
        var p = e.movementPattern();
        if (c != null && c.equals("aerobic")) { return true; }
        if (p != null && (p.equals("aerobic_monostructural") || p.equals("locomotion"))) { return true; }
        return e.isTemplate("distance") && e.distanceKm() != null;
    }
    function workLabel(e) { return isRunInterval(e) ? "Run" : "Work"; }
    function restLabel(e) { return isRunInterval(e) ? "Recover" : "Rest"; }
    function workValue(e) {
        var t = Text.mmss(v("intervalWorkSec", 0));
        if (e.targetRpm() != null) { return t + "  " + e.targetRpm().toString() + " RPM"; }
        var z = e.zoneLower();
        if (z != null) {
            var hi = e.zoneUpper();
            return t + "  Zone " + z.toString() + ((hi != null && hi != z) ? ("-" + hi.toString()) : "");
        }
        return t;
    }
    function restValue(e) {
        var g = e.restUntilHr();
        if (g != null) { return "until HR " + g.toString(); }
        return Text.mmss(v("intervalRestSec", 0));
    }

    // LAP: what the renderer asked for, in the fixtures' words.
    function skip()          { calls.add("skip"); }
    function completeSet()   { calls.add("completeSet"); }
    function startHold()     { calls.add("startHold"); }
    function stopHoldEarly() { calls.add("stopHoldEarly"); }
    function toggleSide()    { calls.add("toggleSide"); }
    function logRound()      { calls.add("logRound"); s["rounds"] = amrapRounds() + 1; }

    function outcome() {
        if (calls.size() == 2 && calls[0].equals("logRound") && calls[1].equals("skip")) { return "log_round_and_next"; }
        if (calls.size() != 1) { return "?"; }
        var m = { "skip" => "next", "completeSet" => "complete_set", "startHold" => "start_hold",
                  "stopHoldEarly" => "stop_hold", "toggleSide" => "next_side", "logRound" => "log_round" };
        return m.hasKey(calls[0]) ? m[calls[0]] : "?";
    }
}

function specFixtureSame(got, want, msg) {
    if (want == null) {
        Test.assertMessage(got == null, msg + ": want none, got " + got);
    } else {
        Test.assertMessage(got != null && got.equals(want), msg + ": want " + want + ", got " + got);
    }
}

function specFixtureField(got, want, msg) {
    if (want == null) {
        Test.assertMessage(got == null, msg + ": want no field");
        return;
    }
    Test.assertMessage(got != null, msg + ": want " + want[0] + " " + want[1] + ", got none");
    if (got == null) { return; }
    specFixtureSame(got[0], want[0], msg + " label");
    specFixtureSame(got[1], want[1], msg + " value");
}

(:test)
function specFixturesDrawEveryCase(logger as Test.Logger) as Lang.Boolean {
    var cases = specFixtureCases();
    var r = new SpecRenderer();
    for (var i = 0; i < cases.size(); i += 1) {
        var c = cases[i];
        var exd = c["exercise"];
        var screens = null;
        if (c["screen"] != null) {
            exd["screen"] = "s0";
            screens = { "s0" => c["screen"] };
        }
        var ex = new WorkoutExercise(exd, screens, null);
        var ctl = new SpecFixtureCtl(c["state"], ex);
        var e = c["expect"];
        var n = c["name"];
        specFixtureSame(r.title(ctl, ex), e["title"], n + ": title");
        specFixtureField(r.fieldA(ctl, ex), e["a"], n + ": a");
        specFixtureField(r.fieldB(ctl, ex), e["b"], n + ": b");
        specFixtureField(r.gaugeField(ctl, ex), e["gauge"], n + ": gauge");
        var ln = r.lines(ctl, ex);
        specFixtureSame(ln[0], e["lines"][0], n + ": line 1");
        specFixtureSame(ln[1], e["lines"][1], n + ": line 2");
        specFixtureSame(ex.spec()["lap"], e["lap"], n + ": LAP");
        r.onLap(ctl, ex);
        specFixtureSame(ctl.outcome(), e["outcome"], n + ": what LAP does");
    }
    return true;
}
'''


def render(fixtures: dict) -> str:
    cases = []
    for c in fixtures['cases']:
        cases.append({'name': c['name'], 'exercise': c['exercise'], 'screen': c.get('screen'),
                      'state': c.get('state') or {}, 'expect': c['expect']})
    body = ',\n'.join(f'        {mc(c)}' for c in cases)
    return '\n'.join([
        '// GENERATED by garmin/tools/gen_spec_fixtures.py from data/watch_fixtures.json.',
        '// Do not edit; change the JSON and rerun the generator. The Apple Watch runs',
        '// the same cases (ios/TrainingCompanionTests/WatchSpecTests.swift).',
        'using Toybox.Test;',
        'using Toybox.Lang;',
        '',
        CTL,
        'function specFixtureCases() {',
        '    return [',
        body,
        '    ];',
        '}',
        '',
    ])


def main() -> int:
    with open(SRC, encoding='utf-8') as f:
        text = render(json.load(f))
    if '--check' in sys.argv:
        current = open(OUT, encoding='utf-8').read() if os.path.exists(OUT) else ''
        if current != text:
            print(f'{os.path.relpath(OUT, ROOT)} is stale: run garmin/tools/gen_spec_fixtures.py')
            return 1
        return 0
    with open(OUT, 'w', encoding='utf-8') as f:
        f.write(text)
    print(f'wrote {os.path.relpath(OUT, ROOT)}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
