using Toybox.Lang;

// Per-archetype behaviour overrides.
//
// The SCREEN is chosen by slot_type -- there are only nine, and they cover all 51
// archetypes. But a handful of archetypes need behaviour no generic slot screen
// can give: a Turkish get-up is counted per side, Tabata's 20s/10s is a protocol
// rather than a derived interval, a BJJ class has no exercises at all, and a
// breathing ladder counts rungs rather than rounds.
//
// This is a lookup returning flags the base renderers honour -- deliberately not
// 51 bespoke views.
module ArchetypeBehavior {

    // Count reps per side and show a left/right stepper.
    function sideTracked(archetypeId, ex) {
        if (ex != null && ex.isUnilateral()) { return true; }
        if (archetypeId == null) { return false; }
        return archetypeId.equals("tgu_practice")
            || archetypeId.equals("gym_jones_tgu_recovery")
            || archetypeId.equals("me_weighted_box_step_ups");
    }

    // Show a cumulative rep total toward a session-level target instead of a
    // per-set counter. Gym Jones' TGU recovery session is "100 get-ups", not
    // "10 sets of 5" -- the number the athlete is tracking is the running total.
    function cumulativeTarget(archetypeId) {
        if (archetypeId == null) { return null; }
        if (archetypeId.equals("gym_jones_tgu_recovery")) { return 100; }
        return null;
    }

    // Ladder protocols count rungs (1,2,3...20,...3,2,1), not rounds. The Gym
    // Jones breathing ladder is ~400 swings; a flat round counter says nothing.
    function isLadder(archetypeId) {
        return archetypeId != null && archetypeId.equals("gym_jones_breathing_ladder");
    }

    // Ladder rung for a given completed-round index (0-based), peaking at 20.
    function ladderRung(roundIdx) {
        var r = roundIdx + 1;
        if (r <= 20) { return r; }
        var down = 20 - (r - 20);
        return (down < 1) ? 1 : down;
    }

    // Cumulative reps after n completed ladder rungs.
    function ladderTotal(rounds) {
        var t = 0;
        for (var i = 0; i < rounds; i += 1) { t += ladderRung(i); }
        return t;
    }

    // A named round timer with no exercise content -- the block role IS the
    // content ("Drilling 25:00", "Rolling 25:00").
    function isRoundTimer(archetypeId) {
        return archetypeId != null && archetypeId.equals("bjj_class");
    }

    // Circuits with rest_sec 0 run round-major: all movements, then repeat.
    // Showing them exercise-major implies a rest that the prescription forbids.
    function isCircuit(archetypeId) {
        if (archetypeId == null) { return false; }
        return archetypeId.equals("bodyweight_circuit")
            || archetypeId.equals("loaded_carry_circuit");
    }

    // Distance-led sessions foreground km covered and pack weight.
    function isDistanceLed(archetypeId) {
        if (archetypeId == null) { return false; }
        return archetypeId.equals("ruck_session")
            || archetypeId.equals("weighted_ruck_z2");
    }

    // Kettlebell pentathlon is paced to a target RPM; the metronome is the session.
    function metronomeRpm(archetypeId) {
        if (archetypeId == null) { return null; }
        if (archetypeId.equals("kb_pentathlon_training")) { return 12; }
        return null;
    }

    // Percent-of-1RM wave for the EMOM strength block, so the athlete can see
    // where in the wave they are rather than recalling it from the notes.
    function loadWave(archetypeId) {
        if (archetypeId == null || !archetypeId.equals("emom_strength")) { return null; }
        return [85, 87, 90, 92, 95, 92, 90, 90, 87, 85];
    }

    // Very long sessions drop to static rendering regardless of battery.
    function isLongHaul(archetypeId) {
        if (archetypeId == null) { return false; }
        return archetypeId.equals("long_mountain_day")
            || archetypeId.equals("scrambling_durability")
            || archetypeId.equals("uphill_weighted_carry_session");
    }

    // TGU position strip -- the six phases of the get-up, shown as a hint.
    function tguPhases() {
        return "roll > post > bridge > sweep > lunge > stand";
    }
}
