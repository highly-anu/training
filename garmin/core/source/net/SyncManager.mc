using Toybox.Communications as Comm;
using Toybox.Application.Storage;
using Toybox.Lang;
using Toybox.PersistedContent;
using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;

// The exact data type makeWebRequest hands its callback on this SDK.
typedef WebData as Null or Lang.Dictionary or Lang.String or PersistedContent.Iterator;

// All backend I/O. Mirrors the iOS SyncManager + WatchSessionManager + APIClient:
// pairing, today-session fetch, and buffer-and-retry upload of a finished session.
//
// Callbacks are Lang.Method objects invoked as cb.invoke(success, data).
class SyncManager {

    hidden var _pairCb;
    hidden var _statusCb;
    hidden var _todayCb;
    hidden var _readinessCb;

    // Wellness: the readings to post this round, the one in flight, and the
    // first that failed (kept for the next open).
    hidden var _wellnessCb;
    hidden var _wellnessQueue;
    hidden var _wellnessInFlight;
    hidden var _wellnessFailed;

    // Upload state machine (workout -> session log), all-or-buffer.
    hidden var _uploadCb;
    hidden var _uploadSummary;

    function initialize() {}

    // ── helpers ────────────────────────────────────────────────────────────────

    hidden function token() {
        return Storage.getValue(Config.KEY_DEVICE_TOKEN);
    }

    hidden function authHeaders() {
        var t = token();
        if (t == null) { return {}; }
        return { "Authorization" => "Bearer " + t };
    }

    hidden function jsonGetOptions() {
        return {
            :method => Comm.HTTP_REQUEST_METHOD_GET,
            :headers => authHeaders(),
            :responseType => Comm.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
    }

    hidden function jsonBodyOptions(httpMethod) {
        var h = authHeaders();
        h["Content-Type"] = Comm.REQUEST_CONTENT_TYPE_JSON;
        return {
            :method => httpMethod,
            :headers => h,
            :responseType => Comm.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
    }

    // ── pairing ─────────────────────────────────────────────────────────────────

    // POST /devices/pair (unauthenticated). cb.invoke(success, code).
    function pair(cb) {
        _pairCb = cb;
        Comm.makeWebRequest(
            Config.apiBaseUrl() + "/devices/pair",
            // The server names the model from the part number
            // (data/garmin_devices.json); every watch used to pair as "Fenix 9".
            { "deviceName" => "Garmin watch",
              "partNumber" => System.getDeviceSettings().partNumber },
            jsonBodyOptions(Comm.HTTP_REQUEST_METHOD_POST),
            method(:onPair)
        );
    }

    function onPair(code as Lang.Number, data as WebData) as Void {
        if (code == 200 && data instanceof Lang.Dictionary && data.hasKey("deviceToken")) {
            Storage.setValue(Config.KEY_DEVICE_TOKEN, data["deviceToken"]);
            Storage.setValue(Config.KEY_CLAIMED, false);
            System.println("CIQ_PAIR_CODE=" + data["code"]);  // DEBUG: capture in sim console
            if (_pairCb != null) { _pairCb.invoke(true, data["code"]); }
        } else {
            System.println("CIQ_PAIR_FAIL http=" + code);      // DEBUG
            if (_pairCb != null) { _pairCb.invoke(false, null); }
        }
    }

    // GET /devices/status. cb.invoke(success, claimedBool).
    function pollStatus(cb) {
        _statusCb = cb;
        Comm.makeWebRequest(
            Config.apiBaseUrl() + "/devices/status",
            null,
            jsonGetOptions(),
            method(:onStatus)
        );
    }

    function onStatus(code as Lang.Number, data as WebData) as Void {
        var claimed = (code == 200 && data instanceof Lang.Dictionary && data["claimed"] == true);
        if (claimed) { Storage.setValue(Config.KEY_CLAIMED, true); }
        if (_statusCb != null) { _statusCb.invoke(code == 200, claimed); }
    }

    // ── today's session ──────────────────────────────────────────────────────────

    // The HTTP status of the last today-session request (a negative number is
    // Connect IQ's: no phone, timed out, response too large), for the
    // couldn't-sync page.
    var lastTodayCode = null;

    // GET /user/today-session for the watch's own day, with the week ahead.
    // cb.invoke(success, dict). Caches on success.
    function fetchToday(cb) {
        if (DemoSession.enabled()) { cb.invoke(true, null); return; }
        _todayCb = cb;
        Comm.makeWebRequest(
            // spec=1: each session carries its package's screen specs (ScreenSpec).
            // date: the server's own date is UTC, a day out every evening west of
            // Greenwich and every early morning east of it.
            // week=1: `days`, today and the six after it, for the Week menu.
            Config.apiBaseUrl() + "/user/today-session?spec=" + Vocab.VERSION.toString()
                + "&week=1&date=" + Config.localDate(),
            null,
            jsonGetOptions(),
            method(:onToday)
        );
    }

    function onToday(code as Lang.Number, data as WebData) as Void {
        lastTodayCode = code;
        if (code == 200 && data instanceof Lang.Dictionary) {
            // The week is stored on its own: with it, a heavy week would push the
            // day past what one Storage value holds.
            if (data.hasKey("days")) {
                Storage.setValue(Config.KEY_WEEK, data["days"]);
                data.remove("days");
            } else {
                Storage.deleteValue(Config.KEY_WEEK);
            }
            Storage.setValue(Config.KEY_TODAY_SESSION, data);
            GlanceCache.write(data);
            Storage.setValue(Config.KEY_TODAY_DATE, data["date"]);
            if (_todayCb != null) { _todayCb.invoke(true, data); }
        } else {
            // Offline: the cached day, but only if it is today's. Yesterday's
            // cache used to stand in for today, so a failed morning sync after a
            // rest day showed today as a rest day too.
            var cached = SyncCache.cachedToday();
            if (_todayCb != null) { _todayCb.invoke(cached != null, cached); }
        }
    }

    // ── readiness (for the glance / session-list dot) ─────────────────────────────

    // GET /health/readiness. Caches the dict so the glance (which has no reliable
    // network) can render the readiness dot from Storage. cb.invoke(success, dict).
    function fetchReadiness(cb) {
        if (DemoSession.enabled()) { cb.invoke(true, DemoSession.readiness()); return; }
        _readinessCb = cb;
        Comm.makeWebRequest(
            Config.apiBaseUrl() + "/health/readiness",
            null,
            jsonGetOptions(),
            method(:onReadiness)
        );
    }

    function onReadiness(code as Lang.Number, data as WebData) as Void {
        if (code == 200 && data instanceof Lang.Dictionary) {
            Storage.setValue(Config.KEY_READINESS, data);
            if (_readinessCb != null) { _readinessCb.invoke(true, data); }
        } else if (_readinessCb != null) {
            _readinessCb.invoke(false, null);
        }
    }

    // ── wellness (POST /health/wellness) ──────────────────────────────────────────

    // Reads today's wellness (Wellness.read) and posts it, then cb.invoke(success, null).
    // Called on every app open before readiness is fetched, so the readiness dot
    // already scores this morning's resting HR. One reading that did not reach the
    // server is kept: a later one of the same day absorbs its lows and highs (the
    // heart-rate history holds six hours, so the morning's low would otherwise be
    // gone), one of an earlier day is posted first. 200 (stored, or skipped because
    // the Garmin toggle is off) and 422 (resending cannot fix it) both end a
    // reading; anything else — no phone, a 503 — keeps it.
    function sendWellness(cb) {
        if (DemoSession.enabled()) { cb.invoke(true, null); return; }
        _wellnessCb = cb;
        _wellnessQueue = [];
        _wellnessFailed = null;
        if (token() == null) { cb.invoke(true, null); return; }

        var pending = Storage.getValue(Config.KEY_WELLNESS_PENDING) as Lang.Dictionary?;
        var sentAt = Storage.getValue(Config.KEY_WELLNESS_SENT_AT) as Lang.Number?;
        if (pending == null && sentAt != null
                && Time.now().value() - sentAt < Config.WELLNESS_MIN_GAP_SEC) {
            cb.invoke(true, null);
            return;
        }

        var cur = Wellness.read();
        if (pending != null) {
            if (cur != null && cur["date"].equals(pending["date"])) {
                cur = foldWellness(pending, cur);
            } else {
                _wellnessQueue.add(pending);
            }
        }
        if (cur != null) { _wellnessQueue.add(cur); }
        _postNextWellness();
    }

    // The newer reading, keeping the lower lows and the higher high of the two —
    // the same per-column rule src/wellness_store.py applies to a repeat post.
    function foldWellness(older, newer) {
        var lows = ["hrMin", "bodyBatteryMin"];
        for (var i = 0; i < lows.size(); i++) {
            var k = lows[i];
            if (older.hasKey(k) && (!newer.hasKey(k) || older[k] < newer[k])) { newer[k] = older[k]; }
        }
        if (older.hasKey("bodyBatteryMax")
                && (!newer.hasKey("bodyBatteryMax") || older["bodyBatteryMax"] > newer["bodyBatteryMax"])) {
            newer["bodyBatteryMax"] = older["bodyBatteryMax"];
        }
        return newer;
    }

    hidden function _postNextWellness() {
        if (_wellnessQueue.size() == 0) {
            if (_wellnessFailed != null) {
                Storage.setValue(Config.KEY_WELLNESS_PENDING, _wellnessFailed);
            } else {
                Storage.deleteValue(Config.KEY_WELLNESS_PENDING);
                Storage.setValue(Config.KEY_WELLNESS_SENT_AT, Time.now().value());
            }
            if (_wellnessCb != null) { _wellnessCb.invoke(_wellnessFailed == null, null); }
            return;
        }
        _wellnessInFlight = _wellnessQueue[0];
        _wellnessQueue = _wellnessQueue.slice(1, null);
        Comm.makeWebRequest(
            Config.apiBaseUrl() + "/health/wellness",
            _wellnessInFlight,
            jsonBodyOptions(Comm.HTTP_REQUEST_METHOD_POST),
            method(:onWellnessPosted)
        );
    }

    function onWellnessPosted(code as Lang.Number, data as WebData) as Void {
        if (code != 200 && code != 422 && _wellnessFailed == null) {
            _wellnessFailed = _wellnessInFlight;
        }
        _wellnessInFlight = null;
        _postNextWellness();
    }

    // ── upload (buffer-and-retry) ─────────────────────────────────────────────────

    // summary: { sessionKey, date, source:"garmin", workout:{...}, sessionLog:{...} }
    // Runs workout -> sessionLog; buffers the whole summary on the first failure.
    // There used to be a third step, PUT /health/bio/{date}, for a "bio" key nothing
    // ever filled; daily wellness now goes through sendWellness on every open.
    function uploadSession(summary, cb) {
        // A demo workout must never reach the server, nor sit in the retry buffer
        // waiting for a real pairing to send it.
        if (DemoSession.enabled()) { cb.invoke(true, null); return; }
        _uploadSummary = summary;
        _uploadCb = cb;
        _postWorkout();
    }

    hidden function _postWorkout() {
        var w = _uploadSummary["workout"];
        Comm.makeWebRequest(
            Config.apiBaseUrl() + "/health/workouts",
            { "workouts" => [ w ] },
            jsonBodyOptions(Comm.HTTP_REQUEST_METHOD_POST),
            method(:onWorkoutPosted)
        );
    }

    function onWorkoutPosted(code as Lang.Number, data as WebData) as Void {
        if (code != 200) { _failUpload(); return; }
        var key = _uploadSummary["sessionKey"];
        Comm.makeWebRequest(
            Config.apiBaseUrl() + "/health/sessions/" + key,
            _uploadSummary["sessionLog"],
            jsonBodyOptions(Comm.HTTP_REQUEST_METHOD_PUT),
            method(:onSessionLogPut)
        );
    }

    function onSessionLogPut(code as Lang.Number, data as WebData) as Void {
        if (code != 200) { _failUpload(); return; }
        _finishUpload();
    }

    hidden function _finishUpload() {
        if (_uploadCb != null) { _uploadCb.invoke(true, null); }
        _uploadSummary = null;
    }

    hidden function _failUpload() {
        bufferPayload(_uploadSummary);
        if (_uploadCb != null) { _uploadCb.invoke(false, null); }
        _uploadSummary = null;
    }

    // The app is closing with an upload in flight: buffer it, drop the callback.
    function parkPending() {
        if (_uploadSummary == null) { return; }
        bufferPayload(_uploadSummary);
        _uploadSummary = null;
        _uploadCb = null;
    }

    // ── local buffer (survives upload failure) ────────────────────────────────────

    function bufferPayload(payload) {
        if (payload == null) { return; }
        var buf = Storage.getValue(Config.KEY_UPLOAD_BUFFER);
        if (buf == null) { buf = []; }
        buf.add(payload);
        Storage.setValue(Config.KEY_UPLOAD_BUFFER, buf);
    }

    // Retry the oldest buffered upload. Call on app open / when reachable.
    // TODO: iterate the whole buffer; here we drain one per call to stay simple.
    function flushBuffer() {
        if (DemoSession.enabled()) { return; }
        var buf = Storage.getValue(Config.KEY_UPLOAD_BUFFER);
        if (buf == null || buf.size() == 0) { return; }
        var next = buf[0];
        buf.remove(next);
        Storage.setValue(Config.KEY_UPLOAD_BUFFER, buf);
        uploadSession(next, method(:onFlushResult));
    }

    function onFlushResult(success, data) as Void {
        // On failure uploadSession re-buffers automatically; keep draining on success.
        if (success) { flushBuffer(); }
    }
}

// The cached day and week, read by the views and checked against the athlete's
// local date. A module, not statics on SyncManager: a static that calls another
// unqualified fails at run time ("Failed invoking <symbol>").
module SyncCache {

    // The cached today-session, or null when it is another day's.
    function cachedToday() {
        var d = Storage.getValue(Config.KEY_TODAY_DATE) as Lang.String?;
        if (d == null || !d.equals(Config.localDate())) { return null; }
        return Storage.getValue(Config.KEY_TODAY_SESSION) as Lang.Dictionary?;
    }

    // The cached week, re-based on today: a week fetched on Monday still answers
    // on Wednesday, from its third day on. Null when nothing of it is left.
    function cachedWeek() {
        var days = Storage.getValue(Config.KEY_WEEK) as Lang.Array?;
        var d = Storage.getValue(Config.KEY_TODAY_DATE) as Lang.String?;
        if (days == null || d == null) { return null; }
        var shift = daysBetween(d, Config.localDate());
        if (shift == null || shift < 0) { return null; }
        var out = [];
        for (var i = 0; i < days.size(); i += 1) {
            var day = days[i] as Lang.Dictionary;
            var off = (day["offset"] as Lang.Number) - shift;
            if (off < 0) { continue; }
            out.add({ "offset" => off, "title" => day["title"], "sessions" => day["sessions"] });
        }
        return (out.size() > 0) ? out : null;
    }

    // Whole days from one "YYYY-MM-DD" to another, or null if either is malformed.
    function daysBetween(a, b) {
        var ma = moment(a);
        var mb = moment(b);
        if (ma == null || mb == null) { return null; }
        return ((mb.value() - ma.value()) / 86400.0).toNumber();
    }

    function moment(ymd) {
        if (ymd == null || ymd.length() != 10) { return null; }
        var y = ymd.substring(0, 4).toNumber();
        var m = ymd.substring(5, 7).toNumber();
        var dd = ymd.substring(8, 10).toNumber();
        if (y == null || m == null || dd == null) { return null; }
        return Gregorian.moment({ :year => y, :month => m, :day => dd, :hour => 12 });
    }
}
