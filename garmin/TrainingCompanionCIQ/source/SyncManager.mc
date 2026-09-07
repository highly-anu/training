using Toybox.Communications as Comm;
using Toybox.Application.Storage;
using Toybox.Lang;

// All backend I/O. Mirrors the iOS SyncManager + WatchSessionManager + APIClient:
// pairing, today-session fetch, and buffer-and-retry upload of a finished session.
//
// Callbacks are Lang.Method objects invoked as cb.invoke(success, data).
class SyncManager {

    hidden var _pairCb;
    hidden var _statusCb;
    hidden var _todayCb;

    // Upload state machine (workout -> session log -> bio), all-or-buffer.
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
            { "deviceName" => "Garmin Fenix 9" },
            jsonBodyOptions(Comm.HTTP_REQUEST_METHOD_POST),
            method(:onPair)
        );
    }

    function onPair(code, data) {
        if (code == 200 && data != null && data.hasKey("deviceToken")) {
            Storage.setValue(Config.KEY_DEVICE_TOKEN, data["deviceToken"]);
            Storage.setValue(Config.KEY_CLAIMED, false);
            if (_pairCb != null) { _pairCb.invoke(true, data["code"]); }
        } else {
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

    function onStatus(code, data) {
        var claimed = (code == 200 && data != null && data["claimed"] == true);
        if (claimed) { Storage.setValue(Config.KEY_CLAIMED, true); }
        if (_statusCb != null) { _statusCb.invoke(code == 200, claimed); }
    }

    // ── today's session ──────────────────────────────────────────────────────────

    // GET /user/today-session. cb.invoke(success, dict). Caches on success.
    function fetchToday(cb) {
        _todayCb = cb;
        Comm.makeWebRequest(
            Config.apiBaseUrl() + "/user/today-session",
            null,
            jsonGetOptions(),
            method(:onToday)
        );
    }

    function onToday(code, data) {
        if (code == 200 && data != null) {
            Storage.setValue(Config.KEY_TODAY_SESSION, data);
            Storage.setValue(Config.KEY_TODAY_DATE, data["date"]);
            if (_todayCb != null) { _todayCb.invoke(true, data); }
        } else {
            // Fall back to cache so the app is useful offline.
            var cached = Storage.getValue(Config.KEY_TODAY_SESSION);
            if (_todayCb != null) { _todayCb.invoke(cached != null, cached); }
        }
    }

    // ── upload (buffer-and-retry) ─────────────────────────────────────────────────

    // summary: {
    //   sessionKey, date, source:"garmin", workout:{...}, sessionLog:{...}, bio:{...}?
    // }
    // Runs workout -> sessionLog -> bio; buffers the whole summary on the first failure.
    function uploadSession(summary, cb) {
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

    function onWorkoutPosted(code, data) {
        if (code != 200) { return _failUpload(); }
        var key = _uploadSummary["sessionKey"];
        Comm.makeWebRequest(
            Config.apiBaseUrl() + "/health/sessions/" + key,
            _uploadSummary["sessionLog"],
            jsonBodyOptions(Comm.HTTP_REQUEST_METHOD_PUT),
            method(:onSessionLogPut)
        );
    }

    function onSessionLogPut(code, data) {
        if (code != 200) { return _failUpload(); }
        var bio = _uploadSummary.hasKey("bio") ? _uploadSummary["bio"] : null;
        if (bio == null) { return _finishUpload(); }
        Comm.makeWebRequest(
            Config.apiBaseUrl() + "/health/bio/" + _uploadSummary["date"],
            bio,
            jsonBodyOptions(Comm.HTTP_REQUEST_METHOD_PUT),
            method(:onBioPut)
        );
    }

    function onBioPut(code, data) {
        // Bio is best-effort; a failure here still counts the session as uploaded.
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
        var buf = Storage.getValue(Config.KEY_UPLOAD_BUFFER);
        if (buf == null || buf.size() == 0) { return; }
        var next = buf[0];
        buf.remove(next);
        Storage.setValue(Config.KEY_UPLOAD_BUFFER, buf);
        uploadSession(next, method(:onFlushResult));
    }

    function onFlushResult(success, data) {
        // On failure uploadSession re-buffers automatically; keep draining on success.
        if (success) { flushBuffer(); }
    }
}
