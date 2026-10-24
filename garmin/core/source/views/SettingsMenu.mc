using Toybox.WatchUi as Ui;
using Toybox.Attention;
using Toybox.Lang;

// Settings, as Garmin's own activity settings: the system list, switches that
// change at once and stay in the menu. Reached from the pre-start page's
// activity menu and from the workout's hold-UP menu; the same values are in
// Garmin Connect Mobile (Cues).
//
//   Tones            the workout's tones
//   Vibration        its vibrations
//   Lead-in          "Work in 3, 2, 1" and the go before work on a clock
//   Countdown Start  the same count after START
//   Lead-in Tones    which of the watch's tones count and which says go
//   Glance           the glance's style: Next up, Day bar or Ring
function openSettings() {
    Cues.load();
    var m = new Ui.Menu2({ :title => "Settings" });
    m.addItem(new Ui.ToggleMenuItem("Tones", "Workout tones", "cueTones", Cues.tones, {}));
    m.addItem(new Ui.ToggleMenuItem("Vibration", "Workout vibrations", "cueVibrate", Cues.vibrate, {}));
    m.addItem(new Ui.ToggleMenuItem("Lead-in", "Work in 3, 2, 1, go", "leadIn", Cues.leadInOn, {}));
    m.addItem(new Ui.ToggleMenuItem("Countdown Start", "3, 2, 1 after START", "countdownStart",
                                    Cues.countdownStartOn, {}));
    m.addItem(new Ui.MenuItem("Lead-in Tones", toneName(Cues.tickTone) + " · " + toneName(Cues.goTone),
                              :tones, {}));
    m.addItem(new Ui.MenuItem("Glance", glanceStyleName(Cues.prop("glanceStyle", 0)), :glance, {}));
    Ui.pushView(m, new SettingsMenuDelegate(), Ui.SLIDE_LEFT);
}

// The watch's own tones, in Toybox.Attention's order; a custom pitch plays
// nothing on a watch with a speaker, so these are all there is.
function toneIds() {
    return [Attention.TONE_KEY, Attention.TONE_START, Attention.TONE_STOP, Attention.TONE_MSG,
            Attention.TONE_ALERT_HI, Attention.TONE_ALERT_LO, Attention.TONE_LOUD_BEEP,
            Attention.TONE_INTERVAL_ALERT, Attention.TONE_ALARM, Attention.TONE_RESET,
            Attention.TONE_LAP, Attention.TONE_CANARY, Attention.TONE_TIME_ALERT,
            Attention.TONE_DISTANCE_ALERT, Attention.TONE_FAILURE, Attention.TONE_SUCCESS,
            Attention.TONE_POWER, Attention.TONE_LOW_BATTERY, Attention.TONE_ERROR];
}

function toneName(t) {
    var names = ["Key", "Start", "Stop", "Message", "Alert High", "Alert Low", "Loud Beep",
                 "Interval Alert", "Alarm", "Reset", "Lap", "Canary", "Time Alert",
                 "Distance Alert", "Failure", "Success", "Power", "Low Battery", "Error"];
    var i = toneIds().indexOf(t);
    return (i >= 0) ? names[i] : "Tone";
}

// GlanceView's styles, in `glanceStyle` order (settings.xml names them the same).
function glanceStyleName(i) {
    var names = ["Next up", "Day bar", "Ring"];
    return (i instanceof Lang.Number && i >= 0 && i < names.size()) ? names[i] : names[0];
}

class SettingsMenuDelegate extends Ui.Menu2InputDelegate {

    function initialize() { Menu2InputDelegate.initialize(); }

    function onSelect(item) {
        var id = item.getId();
        if (id == :tones) {
            var m = new Ui.Menu2({ :title => "Lead-in Tones" });
            m.addItem(new Ui.MenuItem("Count", toneName(Cues.tickTone), "leadTickTone", {}));
            m.addItem(new Ui.MenuItem("Go", toneName(Cues.goTone), "leadGoTone", {}));
            Ui.pushView(m, new LeadToneMenuDelegate(item), Ui.SLIDE_LEFT);
            return;
        }
        if (id == :glance) {
            var cur = Cues.prop("glanceStyle", 0);
            var m = new Ui.Menu2({ :title => "Glance" });
            for (var i = 0; i < 3; i += 1) {
                m.addItem(new Ui.MenuItem(glanceStyleName(i), (i == cur) ? "Selected" : null, i, {}));
            }
            Ui.pushView(m, new GlancePickDelegate(item), Ui.SLIDE_LEFT);
            return;
        }
        if (item instanceof Ui.ToggleMenuItem) { Cues.set(id, item.isEnabled()); }
    }

    function onBack() { Ui.popView(Ui.SLIDE_RIGHT); }
}

// A style is kept as it is picked and the list closes; the glance draws it the
// next time the glance loop is open.
class GlancePickDelegate extends Ui.Menu2InputDelegate {

    hidden var _settingsItem;

    function initialize(settingsItem) {
        Menu2InputDelegate.initialize();
        _settingsItem = settingsItem;
    }

    function onSelect(item) {
        Cues.set("glanceStyle", item.getId());
        _settingsItem.setSubLabel(glanceStyleName(item.getId()));
        Ui.popView(Ui.SLIDE_RIGHT);
    }

    function onBack() { Ui.popView(Ui.SLIDE_RIGHT); }
}

// Count / Go: each opens the list of tones.
class LeadToneMenuDelegate extends Ui.Menu2InputDelegate {

    hidden var _parentItem;

    function initialize(parentItem) {
        Menu2InputDelegate.initialize();
        _parentItem = parentItem;
    }

    function onSelect(item) {
        var key = item.getId();
        var ids = toneIds();
        var cur = Cues.prop(key, key.equals("leadGoTone") ? Attention.TONE_LOUD_BEEP : Attention.TONE_ALERT_LO);
        var m = new Ui.Menu2({ :title => item.getLabel() });
        for (var i = 0; i < ids.size(); i += 1) {
            m.addItem(new Ui.MenuItem(toneName(ids[i]), (ids[i] == cur) ? "Selected" : null, ids[i], {}));
        }
        Ui.pushView(m, new TonePickDelegate(m, key, item, _parentItem), Ui.SLIDE_LEFT);
    }

    function onBack() { Ui.popView(Ui.SLIDE_RIGHT); }
}

// Selecting a tone plays it and keeps it, so the athlete picks by ear; the list
// stays up to try the next.
class TonePickDelegate extends Ui.Menu2InputDelegate {

    hidden var _menu;
    hidden var _key;
    hidden var _rowItem;
    hidden var _settingsItem;

    function initialize(menu, key, rowItem, settingsItem) {
        Menu2InputDelegate.initialize();
        _menu = menu;
        _key = key;
        _rowItem = rowItem;
        _settingsItem = settingsItem;
    }

    function onSelect(item) {
        var t = item.getId();
        if (Attention has :playTone) {
            try { Attention.playTone(t); } catch (e) {}
        }
        Cues.set(_key, t);
        var ids = toneIds();
        for (var i = 0; i < ids.size(); i += 1) {
            var it = _menu.getItem(i);
            if (it != null) { it.setSubLabel((ids[i] == t) ? "Selected" : null); }
        }
        _rowItem.setSubLabel(toneName(t));
        _settingsItem.setSubLabel(toneName(Cues.tickTone) + " · " + toneName(Cues.goTone));
        Ui.requestUpdate();
    }

    function onBack() { Ui.popView(Ui.SLIDE_RIGHT); }
}
