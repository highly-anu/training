using Toybox.Application.Storage;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.Lang;

// The sessions finished on this watch today, kept in Storage so the glance (a
// separate process) and the next app launch can see them. Written when a workout
// is saved, never when it is discarded; a new local day starts empty.
//
// { "date" => "2026-10-09", "ids" => { sessionId => [minutes, sets] } }
//
// (:glance): the glance reads it, so it must stay small and use no ui/* module.
(:glance)
module DayLog {

    const KEY = "dayLog";

    // Today as the athlete's own calendar day, "YYYY-MM-DD".
    function today() {
        var i = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        return i.year.format("%04d") + "-" + i.month.format("%02d") + "-" + i.day.format("%02d");
    }

    // Today's finished sessions, { sessionId => [minutes, sets] }.
    function done() {
        var log = Storage.getValue(KEY) as Lang.Dictionary?;
        if (log == null || !log.hasKey("date") || !today().equals(log["date"])) { return {}; }
        var ids = log["ids"];
        return (ids != null) ? ids : {};
    }

    function isDone(id) { return id != null && done().hasKey(id); }

    function record(id, minutes, sets) {
        if (id == null) { return; }
        var ids = done();
        ids[id] = [minutes, sets];
        Storage.setValue(KEY, { "date" => today(), "ids" => ids });
    }
}
