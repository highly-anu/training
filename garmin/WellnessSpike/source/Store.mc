import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

// Everything the spike learns is kept on the watch, in Storage rings, so it can be read
// back from the app's own pages. Keys: bgLog / fgLog (value lines), bgDays (one summary line per
// finished day), bgDay (today's fire accounting), bgSt / fgSt (counters), bgSig (the last logged
// signature), fgOpen (when the app was last open).
(:background)
module Store {
    const MAX_LINES = 24;
    const MAX_CHARS = 120;

    // Counter fields in a stats dictionary: missing or non-number reads as 0.
    function cnt(d as Dictionary, key as String) as Number {
        var v = d[key];
        return (v instanceof Lang.Number) ? (v as Number) : 0;
    }

    function two(n as Number) as String {
        return n.format("%02d");
    }

    // Local "dd hh:mm" (Gregorian.info with FORMAT_SHORT is local time).
    function stamp(sec as Number?) as String {
        var m = (sec == null) ? Time.now() : new Time.Moment(sec);
        var i = Gregorian.info(m, Time.FORMAT_SHORT);
        return two(i.day) + " " + two(i.hour) + ":" + two(i.min);
    }

    // "hh:mm" from seconds since midnight.
    function hhmm(sec as Number?) as String {
        if (sec == null) { return "-"; }
        return two(sec / 3600) + ":" + two((sec % 3600) / 60);
    }

    // "MM-DD fires N first hh:mm last hh:mm maxgap Nm" from a per-day accounting dictionary.
    function daySummary(dy as Dictionary) as String {
        var k = cnt(dy, "k");
        return two((k % 10000) / 100) + "-" + two(k % 100) + " fires " + cnt(dy, "n") +
            " first " + hhmm(cnt(dy, "f")) + " last " + hhmm(cnt(dy, "l")) +
            " maxgap " + cnt(dy, "g") + "m";
    }

    // The type checker treats Dictionary<K, V> and Array<T> as invariant, so a typed container
    // never matches Storage.ValueType; the cast lives here, once.
    function save(key as String, value as Object?) as Void {
        Storage.setValue(key, value as Storage.ValueType);
    }

    function push(key as String, line as String) as Void {
        var arr = Storage.getValue(key) as Array<String>?;
        if (arr == null) { arr = [] as Array<String>; }
        arr.add(line.length() > MAX_CHARS ? line.substring(0, MAX_CHARS) as String : line);
        if (arr.size() > MAX_LINES) {
            arr = arr.slice(arr.size() - MAX_LINES, null) as Array<String>;
        }
        save(key, arr);
    }

    function lines(key as String) as Array<String> {
        var arr = Storage.getValue(key) as Array<String>?;
        return (arr == null) ? ([] as Array<String>) : arr;
    }

    function stats(key as String) as Dictionary {
        var d = Storage.getValue(key) as Dictionary?;
        return (d == null) ? ({} as Dictionary) : d;
    }

    function put(key as String, field as String, value as Number or String) as Void {
        var d = stats(key);
        d[field] = value;
        save(key, d);
    }
}
