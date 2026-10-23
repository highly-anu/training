using Toybox.Application;
using Toybox.Attention;
using Toybox.Lang;

// The athlete's cue settings and the lead-in rule.
//
// The settings are app Properties, so the watch's Settings menu and Garmin
// Connect Mobile change the same values (resources/settings/settings.xml):
//
//   cueTones        the workout's tones (Haptics.tone)
//   cueVibrate      its vibrations (Haptics.vibe)
//   leadIn          "Work in 3, 2, 1, go" before work that starts on a clock
//   countdownStart  the same count after START, before the timer starts — as
//                   Garmin's own Countdown Start
//   leadTickTone    the tone of each count, a Toybox.Attention TONE_* value
//   leadGoTone      the tone of the go
//
// Garmin has no speech: Connect IQ cannot say words, play a sound file, or
// reach the watch's own voice prompts, and a custom ToneProfile plays nothing
// on a watch with a speaker (the fenix 8 and 9). The count is the watch's own
// tones, which the athlete picks under Settings ▸ Lead-in tones.
module Cues {

    var tones = true;
    var vibrate = true;
    var leadInOn = true;
    var countdownStartOn = true;
    var tickTone = Attention.TONE_ALERT_LO;
    var goTone = Attention.TONE_LOUD_BEEP;

    // Read the settings: when a workout is prepared, and after the Settings menu
    // changes one.
    function load() {
        tones = prop("cueTones", true);
        vibrate = prop("cueVibrate", true);
        leadInOn = prop("leadIn", true);
        countdownStartOn = prop("countdownStart", true);
        tickTone = prop("leadTickTone", Attention.TONE_ALERT_LO);
        goTone = prop("leadGoTone", Attention.TONE_LOUD_BEEP);
    }

    function prop(key, fallback) {
        try {
            var v = Application.Properties.getValue(key);
            if (v != null) { return v; }
        } catch (e) {}
        return fallback;
    }

    function set(key, value) {
        try { Application.Properties.setValue(key, value); } catch (e) {}
        load();
    }

    // What the lead-in plays with `left` seconds to go before the work: a tick on
    // each of the last LEAD_IN_SEC seconds, the go at 0, else nothing.
    function leadIn(left) {
        if (left == null || left > Vocab.LEAD_IN_SEC || left < 0) { return null; }
        return (left == 0) ? :go : :tick;
    }

    // The vocabulary's word for `left` seconds to go ("Work in 3", "2", "1", "Go"):
    // the screen's line while counting, the Apple Watch's spoken words.
    function leadText(left) {
        var w = Vocab.leadInWords();
        var i = Vocab.LEAD_IN_SEC - left;
        return (i >= 0 && i < w.size()) ? w[i] : null;
    }
}
