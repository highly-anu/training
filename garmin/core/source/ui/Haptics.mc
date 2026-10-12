using Toybox.Attention;

// The haptic + tone vocabulary.
//
// The app previously used a single VibeProfile(75, 400) for every event — set
// logged, rest over, EMOM boundary, HR drift, session complete. On the wrist,
// under load, those are indistinguishable. This mirrors the Apple Watch app's
// haptic schedule (ios/docs/workout-guidance-plan.md) using Garmin's own
// vibration profiles and system tones.
//
// Every call is guarded: Attention is absent on some products, and the user can
// disable vibration or tones system-wide, in which case these are no-ops.
module Haptics {

    function vibe(pattern) {
        if (Attention has :vibrate) {
            try { Attention.vibrate(pattern); } catch (e) {}
        }
    }

    function tone(t) {
        if (Attention has :playTone) {
            try { Attention.playTone(t); } catch (e) {}
        }
    }

    // A set was logged — light, quick, non-intrusive.
    function setLogged() {
        vibe([ new Attention.VibeProfile(40, 120) ]);
        tone(Attention.TONE_KEY);
    }

    // Rest timer milestones. 30s is a gentle nudge, 10s is a double tap
    // (distinct without looking), 0s is emphatic because it starts the next set.
    function restWarn30() {
        vibe([ new Attention.VibeProfile(45, 180) ]);
    }

    function restWarn10() {
        vibe([ new Attention.VibeProfile(55, 120),
               new Attention.VibeProfile(0, 100),
               new Attention.VibeProfile(55, 120) ]);
    }

    function restOver() {
        vibe([ new Attention.VibeProfile(100, 400) ]);
        tone(Attention.TONE_START);
    }

    // EMOM / Tabata interval boundaries. Work and rest must feel different —
    // the athlete is reading them without looking at the watch.
    function intervalWork() {
        vibe([ new Attention.VibeProfile(100, 300) ]);
        tone(Attention.TONE_INTERVAL_ALERT);
    }

    function intervalRest() {
        vibe([ new Attention.VibeProfile(45, 200) ]);
        tone(Attention.TONE_STOP);
    }

    // A round / lap was counted.
    function lap() {
        vibe([ new Attention.VibeProfile(60, 150) ]);
        tone(Attention.TONE_LAP);
    }

    // HR has been outside the prescribed band long enough to act on.
    // dir: +1 too high (ease off), -1 too low (push).
    function hrDrift(dir) {
        vibe([ new Attention.VibeProfile(75, 250),
               new Attention.VibeProfile(0, 120),
               new Attention.VibeProfile(75, 250),
               new Attention.VibeProfile(0, 120),
               new Attention.VibeProfile(75, 250) ]);
        tone(dir > 0 ? Attention.TONE_ALERT_HI : Attention.TONE_ALERT_LO);
    }

    // Count-in before a timed block: three ticks then a go.
    function countTick() {
        vibe([ new Attention.VibeProfile(50, 100) ]);
        tone(Attention.TONE_KEY);
    }

    function countGo() {
        vibe([ new Attention.VibeProfile(100, 350) ]);
        tone(Attention.TONE_START);
    }

    // Side change on a unilateral movement (TGU, single-leg work).
    function sideChange() {
        vibe([ new Attention.VibeProfile(50, 90),
               new Attention.VibeProfile(0, 80),
               new Attention.VibeProfile(70, 160) ]);
    }

    // Metronome pulse (kettlebell pentathlon RPM). Deliberately minimal —
    // this fires many times a minute.
    function metronome() {
        vibe([ new Attention.VibeProfile(35, 70) ]);
    }

    function sessionComplete() {
        vibe([ new Attention.VibeProfile(100, 400),
               new Attention.VibeProfile(0, 150),
               new Attention.VibeProfile(100, 400) ]);
        tone(Attention.TONE_SUCCESS);
    }
}
