import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Background;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;

// Foreground-only bookkeeping. Deliberately not (:background): the service never pays memory
// for it. Writes the "app is open" marker the service reads, counts opens, and registers the
// background events, recording every outcome in fgLog because a registration that silently did
// not happen would look exactly like "the event never fires".
module Foreground {
    const PERIOD_SEC = 15 * 60;

    function open() as Void {
        var now = Time.now().value();
        Storage.setValue("fgOpen", now);
        var st = Store.stats("fgSt");
        st["opens"] = Store.cnt(st, "opens") + 1;
        st["lastOpen"] = now;
        if (!st.hasKey("firstOpen")) { st["firstOpen"] = now; }
        Store.save("fgSt", st);
        register();
    }

    function close() as Void {
        Storage.setValue("fgOpen", 0);
        Store.put("fgSt", "lastClose", Time.now().value());
    }

    function received(data as Application.PersistableType) as Void {
        var st = Store.stats("fgSt");
        st["bgData"] = Store.cnt(st, "bgData") + 1;
        st["bgDataAt"] = Time.now().value();
        Store.save("fgSt", st);
        WatchUi.requestUpdate();
    }

    function describe(reg as Time.Moment or Time.Duration) as String {
        if (reg instanceof Time.Duration) {
            return "every" + ((reg as Time.Duration).value() / 60) + "m";
        }
        return "at" + Store.stamp((reg as Time.Moment).value());
    }

    // T = the 15-minute temporal event (only if none is registered, so opening the app does not
    // reset the schedule), W / S = the wake and sleep events. "+" registered now, "=" already
    // there, "!" the SDK refused (with its message).
    function register() as Void {
        var tag = "";
        try {
            var reg = Background.getTemporalEventRegisteredTime();
            if (reg == null) {
                Background.registerForTemporalEvent(new Time.Duration(PERIOD_SEC));
                tag += "T+";
            } else {
                tag += "T=" + describe(reg);
            }
        } catch (ex) {
            tag += "T!" + Reader.clip(ex.getErrorMessage(), 14);
        }
        try {
            if (Background.getWakeEventRegistered()) {
                tag += " W=";
            } else {
                Background.registerForWakeEvent();
                tag += " W+";
            }
        } catch (ex) {
            tag += " W!" + Reader.clip(ex.getErrorMessage(), 14);
        }
        try {
            if (Background.getSleepEventRegistered()) {
                tag += " S=";
            } else {
                Background.registerForSleepEvent();
                tag += " S+";
            }
        } catch (ex) {
            tag += " S!" + Reader.clip(ex.getErrorMessage(), 14);
        }
        Store.push("fgLog", Store.stamp(null) + " reg " + tag);
    }
}
