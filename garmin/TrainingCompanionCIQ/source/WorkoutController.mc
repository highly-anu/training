using Toybox.ActivityRecording as Rec;
using Toybox.Activity;
using Toybox.Timer;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.Lang;
using Toybox.Attention;
using Toybox.WatchUi;
using Toybox.UserProfile;

// Drives one session: recording, HR capture, set/rest progression, and the final
// upload. Mirrors ios/.../WorkoutManager.swift + WorkoutSessionState.swift.
class WorkoutController {

    // States (mirror WorkoutSessionState phases).
    enum {
        IDLE, ACTIVE, RESTING, COMPLETE
    }

    hidden var _session;        // WorkoutSession
    hidden var _state;
    hidden var _exIndex;
    hidden var _restRemaining;  // seconds
    hidden var _sync;

    // Recording + metrics.
    hidden var _rec;            // ActivityRecording session
    hidden var _timer;
    hidden var _startMoment;
    hidden var _elapsed;        // seconds since start
    hidden var _hrOffsets;      // [Number] second offsets
    hidden var _hrValues;       // [Number] bpm
    hidden var _hrSum;
    hidden var _hrCount;
    hidden var _hrPeak;

    // GPS / distance / elevation — captured for cardio sessions only.
    hidden var _isCardio;
    hidden var _distanceM;      // meters (Activity.Info.elapsedDistance)
    hidden var _ascent;         // meters climbed (Activity.Info.totalAscent)
    hidden var _descent;        // meters descended (Activity.Info.totalDescent)
    hidden var _gpsTrack;       // [ {lat,lng,altitude} ] sampled every GPS_STRIDE_SEC
    hidden var _lastGpsSec;

    // HR-zone drift (cardio / zoned slots): compare live HR to the prescribed zone
    // band, resolved from the athlete's own UserProfile zone boundaries.
    hidden var _hrZones;        // [Number] boundaries from UserProfile, or null
    hidden var _driftSec;       // consecutive seconds outside the prescribed band
    hidden var _pendingDir;     // direction being timed toward an alert (+1/-1/0)
    hidden var _driftDir;       // latched alert direction: +1 too high, -1 too low, 0 in-band

    // Per-exercise interval timing for EMOM / AMRAP / for-time slots.
    hidden var _exStartSec;     // _elapsed when the current exercise became active
    hidden var _emomInterval;   // seconds per EMOM interval (0 = not an EMOM)
    hidden var _emomTotal;      // total EMOM intervals prescribed (0 = open)
    hidden var _emomRound;      // current EMOM interval, 1-based
    hidden var _amrapRounds;    // rounds the athlete has logged (AMRAP / for-time)
    hidden var _capSec;         // AMRAP time cap in seconds (0 = none)
    hidden var _capBuzzed;      // whether the cap-reached buzz has fired

    // setLogs: { exerciseId => [ {reps, weightKg, rpe} ] }
    hidden var _setLogs;

    function initialize(session, sync) {
        _session = session;
        _sync = sync;
        _state = IDLE;
        _exIndex = 0;
        _elapsed = 0;
        _hrOffsets = [];
        _hrValues = [];
        _hrSum = 0; _hrCount = 0; _hrPeak = 0;
        _isCardio = false;
        _distanceM = 0; _ascent = 0; _descent = 0;
        _gpsTrack = [];
        _lastGpsSec = -1000;
        _hrZones = null;
        _driftSec = 0; _pendingDir = 0; _driftDir = 0;
        _exStartSec = 0;
        _emomInterval = 0; _emomTotal = 0; _emomRound = 1;
        _amrapRounds = 0; _capSec = 0; _capBuzzed = false;
        _setLogs = {};
    }

    // ── lifecycle ────────────────────────────────────────────────────────────────

    function start() {
        _startMoment = Time.now();
        _isCardio = isCardioModality(_session.modalityId());
        _hrZones = readHrZones();
        _rec = Rec.createSession({
            :name => _session.archetypeName(),
            :sport => sportForModality(_session.modalityId()),
            :subSport => subSportForModality(_session.modalityId())
        });
        _rec.start();
        _timer = new Timer.Timer();
        _timer.start(method(:onTick), 1000, true);
        _state = ACTIVE;
        beginExerciseTiming();
    }

    function onTick() as Void {
        _elapsed += 1;
        var info = Activity.getActivityInfo();
        if (info != null && info.currentHeartRate != null) {
            var hr = info.currentHeartRate;
            _hrOffsets.add(_elapsed);
            _hrValues.add(hr);
            _hrSum += hr; _hrCount += 1;
            if (hr > _hrPeak) { _hrPeak = hr; }
        }
        if (_isCardio) { captureGps(info); }
        if (_state == ACTIVE) { evaluateHrDrift(); updateIntervalTiming(); }
        if (_state == RESTING) {
            _restRemaining -= 1;
            if (_restRemaining <= 0) {
                vibrate();
                _state = ACTIVE;
            }
        }
        WatchUi.requestUpdate();
    }

    // Capture distance / elevation / a subsampled GPS point from Activity.Info.
    // Every field is guarded with `has` + null checks: indoor sessions and watches
    // without a GPS fix simply contribute nothing.
    hidden function captureGps(info) {
        if (info == null) { return; }
        if ((info has :elapsedDistance) && info.elapsedDistance != null) {
            _distanceM = info.elapsedDistance;
        }
        if ((info has :totalAscent) && info.totalAscent != null) {
            _ascent = info.totalAscent;
        }
        if ((info has :totalDescent) && info.totalDescent != null) {
            _descent = info.totalDescent;
        }
        // Sample one location point every GPS_STRIDE_SEC seconds.
        if (_elapsed - _lastGpsSec >= Config.GPS_STRIDE_SEC
                && (info has :currentLocation) && info.currentLocation != null) {
            var deg = info.currentLocation.toDegrees();   // [lat, lng] as Double
            if (deg != null && deg.size() >= 2) {
                var alt = ((info has :altitude) && info.altitude != null) ? info.altitude : null;
                _gpsTrack.add({ "lat" => deg[0], "lng" => deg[1], "altitude" => alt });
                _lastGpsSec = _elapsed;
            }
        }
    }

    // Read the athlete's HR zone boundaries once, preferring running zones for cardio.
    // Guarded so it degrades to null (no drift alerts) on devices/API levels without
    // the sport-parameterized UserProfile call.
    hidden function readHrZones() {
        if (!(Toybox has :UserProfile)) { return null; }
        if (!(UserProfile has :getHeartRateZones)) { return null; }
        var sport = UserProfile.HR_ZONE_SPORT_GENERIC;
        if (_isCardio && (UserProfile has :HR_ZONE_SPORT_RUNNING)) {
            sport = UserProfile.HR_ZONE_SPORT_RUNNING;
        }
        return UserProfile.getHeartRateZones(sport);
    }

    // BPM band [lo, hi] for the current exercise's prescribed HR zone(s), or null when
    // no zone is prescribed / zones are unavailable. The boundary array has
    // (numZones + 1) entries: index z-1 is the lower bound of zone z, index z its upper.
    function currentHrBand() {
        if (_hrZones == null || _hrZones.size() < 2) { return null; }
        var ex = currentExercise();
        if (ex == null) { return null; }
        var zlo = ex.zoneLower();
        if (zlo == null) { return null; }
        var zhi = ex.zoneUpper();
        if (zhi == null) { zhi = zlo; }
        var maxZone = _hrZones.size() - 1;
        if (zlo < 1) { zlo = 1; }
        if (zhi > maxZone) { zhi = maxZone; }
        if (zlo > maxZone || zhi < 1 || zlo > zhi) { return null; }
        return [ _hrZones[zlo - 1], _hrZones[zhi] ];
    }

    // Latched drift alert direction for the current exercise: +1 HR above the
    // prescribed band (ease off), -1 below it (push), 0 in-band / unknown.
    function driftDirection() { return _driftDir; }

    // Accumulate time outside the prescribed band; buzz once when it persists past
    // HR_DRIFT_HOLD_SEC. Direction changes restart the timer.
    hidden function evaluateHrDrift() {
        var band = currentHrBand();
        var hr = currentHR();
        if (band == null || hr == null) {
            _driftSec = 0; _pendingDir = 0; _driftDir = 0;
            return;
        }
        var dir = (hr < band[0]) ? -1 : ((hr > band[1]) ? 1 : 0);
        if (dir == 0) {
            _driftSec = 0; _pendingDir = 0; _driftDir = 0;
            return;
        }
        if (dir != _pendingDir) { _pendingDir = dir; _driftSec = 0; }
        _driftSec += 1;
        if (_driftSec == Config.HR_DRIFT_HOLD_SEC) {
            _driftDir = dir;
            vibrate();
        }
    }

    // Set up interval state when an exercise becomes active. EMOM interval is
    // derived from the prescribed total time / rounds (falling back to 60s);
    // AMRAP reads its time cap.
    hidden function beginExerciseTiming() {
        _exStartSec = _elapsed;
        _emomInterval = 0; _emomTotal = 0; _emomRound = 1;
        _amrapRounds = 0; _capSec = 0; _capBuzzed = false;
        var ex = currentExercise();
        if (ex == null) { return; }
        var slot = ex.slotType();
        if (slot.equals("emom")) {
            var tmin = ex.timeMinutes();
            var rounds = ex.targetRounds();
            _emomTotal = (rounds != null) ? rounds : 0;
            _emomInterval = (tmin != null && rounds != null && rounds > 0)
                ? ((tmin * 60) / rounds)
                : 60;
        } else if (slot.equals("amrap")) {
            var cap = ex.timeMinutes();
            _capSec = (cap != null) ? (cap * 60) : 0;
        }
    }

    // Buzz at the top of each EMOM interval; buzz once when an AMRAP cap is reached.
    hidden function updateIntervalTiming() {
        var ex = currentExercise();
        if (ex == null) { return; }
        var slot = ex.slotType();
        var since = _elapsed - _exStartSec;
        if (slot.equals("emom") && _emomInterval > 0) {
            var round = (since / _emomInterval) + 1;
            if (round > _emomRound && (_emomTotal <= 0 || round <= _emomTotal)) {
                _emomRound = round;
                vibrate();
            }
        } else if (slot.equals("amrap") && _capSec > 0) {
            if (since >= _capSec && !_capBuzzed) {
                _capBuzzed = true;
                vibrate();
            }
        }
    }

    // Log one completed AMRAP / for-time round (mirrored into setLogs so it uploads).
    function logRound() {
        _amrapRounds += 1;
        var ex = currentExercise();
        if (ex == null) { return; }
        _setLogs[ex.name()] = [ { "reps" => _amrapRounds, "weightKg" => null, "rpe" => null } ];
    }

    function emomRound()          { return _emomRound; }
    function emomTotal()          { return _emomTotal; }
    function amrapRounds()        { return _amrapRounds; }
    function exerciseElapsedSec() { return _elapsed - _exStartSec; }

    // Seconds until the next EMOM interval boundary.
    function emomSecToNext() {
        if (_emomInterval <= 0) { return 0; }
        return _emomInterval - ((_elapsed - _exStartSec) % _emomInterval);
    }

    // Seconds left on the AMRAP time cap (0 once elapsed).
    function exerciseRemainingSec() {
        if (_capSec <= 0) { return 0; }
        var rem = _capSec - (_elapsed - _exStartSec);
        return (rem > 0) ? rem : 0;
    }

    // ── progression ────────────────────────────────────────────────────────────────

    function state()           { return _state; }
    function currentExercise() {
        var list = _session.exercises();
        return (_exIndex < list.size()) ? list[_exIndex] : null;
    }
    function exerciseIndex()    { return _exIndex; }
    function exerciseTotal()    { return _session.exerciseCount(); }
    function restRemaining()    { return _restRemaining; }
    function elapsedSec()       { return _elapsed; }
    function currentHR() {
        var info = Activity.getActivityInfo();
        return (info != null) ? info.currentHeartRate : null;
    }

    // How many sets have been logged for the current exercise.
    function currentSetCount() {
        var ex = currentExercise();
        if (ex == null) { return 0; }
        var id = ex.name();
        return _setLogs.hasKey(id) ? _setLogs[id].size() : 0;
    }

    // Record a completed set for the current exercise.
    function logSet(reps, weightKg, rpe) {
        var ex = currentExercise();
        if (ex == null) { return; }
        var id = ex.name();   // TODO: prefer a stable exerciseId; backend keys by it.
        if (!_setLogs.hasKey(id)) { _setLogs[id] = []; }
        _setLogs[id].add({ "reps" => reps, "weightKg" => weightKg, "rpe" => rpe });
    }

    function startRest() {
        var ex = currentExercise();
        var sec = (ex != null && ex.restSeconds() != null)
            ? ex.restSeconds()
            : Config.defaultRestSec(_session.modalityId());
        if (sec == null || sec <= 0) { return; }
        _restRemaining = sec;
        _state = RESTING;
    }

    function skipRest() {
        _restRemaining = 0;
        _state = ACTIVE;
    }

    // Advance to the next exercise (or finish).
    function nextExercise() {
        _exIndex += 1;
        if (_exIndex >= _session.exerciseCount()) {
            finish();
        } else {
            _state = ACTIVE;
            _driftSec = 0; _pendingDir = 0; _driftDir = 0;   // reset drift latch per exercise
            beginExerciseTiming();
        }
    }

    function finish() {
        if (_timer != null) { _timer.stop(); }
        if (_rec != null) {
            _rec.stop();
            _rec.save();     // writes the FIT to the device activity list
        }
        _state = COMPLETE;
        var summary = buildSummary();
        _sync.uploadSession(summary, method(:onUploadDone));
    }

    function onUploadDone(success, data) as Void {
        // View observes state()==COMPLETE; nothing else required — buffer handles failure.
    }

    // ── summary building (matches src/health_store.py shapes) ────────────────────────

    hidden function buildSummary() {
        var startIso = isoFromMoment(_startMoment);
        var endIso = isoFromMoment(Time.now());
        var dateStr = startIso.substring(0, 10);
        var key = _session.sessionId();
        var avgHR = (_hrCount > 0) ? (_hrSum / _hrCount) : null;
        var peakHR = (_hrPeak > 0) ? _hrPeak : null;

        var workout = {
            "id" => "watch_live_" + key + "_" + startIso,
            "source" => "garmin",
            "date" => dateStr,
            "startTime" => startIso,
            "endTime" => endIso,
            "durationMinutes" => (_elapsed / 60),
            "activityType" => _session.archetypeName(),
            "inferredModalityId" => _session.modalityId(),
            "heartRate" => {
                "avg" => avgHR,
                "max" => peakHR,
                "samples" => buildHrSamples(startIso)
            },
            "rawData" => {}
        };

        // Distance / elevation / GPS track for cardio sessions. The backend
        // recomputes elevation gain/loss from the track's altitudes when we send
        // loss==0 (see api.py health_upsert_workouts), so a device without a
        // barometric total still gets correct elevation.
        if (_isCardio && _distanceM > 0) {
            workout["distance"] = { "value" => (_distanceM / 1000.0), "unit" => "km" };
            workout["elevation"] = { "gain" => _ascent, "loss" => _descent };
            var track = subsample(_gpsTrack, 600);
            if (track.size() > 0) { workout["gpsTrack"] = track; }
        }

        var exercisesLog = {};
        var keys = _setLogs.keys();
        for (var i = 0; i < keys.size(); i++) {
            exercisesLog[keys[i]] = { "sets" => _setLogs[keys[i]] };
        }

        var sessionLog = {
            "sessionKey" => key,
            "completedAt" => endIso,
            "source" => "garmin",
            "exercises" => exercisesLog,
            "notes" => "",
            "avgHR" => avgHR,
            "peakHR" => peakHR
        };

        return {
            "sessionKey" => key,
            "date" => dateStr,
            "source" => "garmin",
            "workout" => workout,
            "sessionLog" => sessionLog
            // "bio" => {...}  // TODO: attach RHR/HRV/sleep when read from device.
        };
    }

    // Subsample to <= 600 points (mirrors the iOS cap) and stamp absolute times.
    hidden function buildHrSamples(startIso) {
        var n = _hrValues.size();
        if (n == 0) { return []; }
        var stride = (n > 600) ? (n / 600) : 1;
        var out = [];
        var base = _startMoment.value();   // epoch seconds
        for (var i = 0; i < n; i += stride) {
            var ts = new Time.Moment(base + _hrOffsets[i]);
            out.add({ "timestamp" => isoFromMoment(ts), "bpm" => _hrValues[i] });
        }
        return out;
    }

    // Even-stride subsample of an array down to <= maxN elements.
    hidden function subsample(arr, maxN) {
        var n = arr.size();
        if (n <= maxN) { return arr; }
        var stride = (n / maxN) + 1;
        var out = [];
        for (var i = 0; i < n; i += stride) { out.add(arr[i]); }
        return out;
    }

    // ── helpers ────────────────────────────────────────────────────────────────

    hidden function vibrate() {
        if (Attention has :vibrate) {
            Attention.vibrate([ new Attention.VibeProfile(75, 400) ]);
        }
    }

    // "YYYY-MM-DDTHH:MM:SSZ" in UTC — parseable by the backend's ISO8601 reader.
    hidden function isoFromMoment(moment) {
        var g = Gregorian.utcInfo(moment, Time.FORMAT_SHORT);
        return Lang.format("$1$-$2$-$3$T$4$:$5$:$6$Z", [
            g.year.format("%04d"), g.month.format("%02d"), g.day.format("%02d"),
            g.hour.format("%02d"), g.min.format("%02d"), g.sec.format("%02d")
        ]);
    }

    // Cardio modalities drive GPS/distance capture and the RUNNING sport type.
    hidden function isCardioModality(m) {
        return m != null && (m.equals("aerobic_base") || m.equals("anaerobic_intervals"));
    }

    // SPORT_*/SUB_SPORT_* are ActivityRecording constants (verified against SDK 9.2.0
    // by compilation — an unknown symbol fails the monkeyc build).
    hidden function sportForModality(m) {
        if (isCardioModality(m)) {
            return Rec.SPORT_RUNNING;   // refine: rowing/cycling per exercise
        }
        return Rec.SPORT_TRAINING;
    }

    hidden function subSportForModality(m) {
        if (m == null) { return Rec.SUB_SPORT_GENERIC; }
        if (m.find("strength") != null || m.equals("power")) {
            return Rec.SUB_SPORT_STRENGTH_TRAINING;
        }
        if (m.equals("aerobic_base")) { return Rec.SUB_SPORT_CARDIO_TRAINING; }
        return Rec.SUB_SPORT_GENERIC;
    }
}
