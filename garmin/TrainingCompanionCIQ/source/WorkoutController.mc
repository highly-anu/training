using Toybox.ActivityRecording as Rec;
using Toybox.Activity;
using Toybox.Timer;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.Lang;
using Toybox.Attention;
using Toybox.WatchUi;

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
        _setLogs = {};
    }

    // ── lifecycle ────────────────────────────────────────────────────────────────

    function start() {
        _startMoment = Time.now();
        _rec = Rec.createSession({
            :name => _session.archetypeName(),
            :sport => sportForModality(_session.modalityId()),
            :subSport => subSportForModality(_session.modalityId())
        });
        _rec.start();
        _timer = new Timer.Timer();
        _timer.start(method(:onTick), 1000, true);
        _state = ACTIVE;
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
        if (_state == RESTING) {
            _restRemaining -= 1;
            if (_restRemaining <= 0) {
                vibrate();
                _state = ACTIVE;
            }
        }
        WatchUi.requestUpdate();
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
            // TODO: distance / elevation / gpsTrack from Activity.Info for cardio.
        };

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

    // TODO(sdk): confirm SPORT_*/SUB_SPORT_* constant names against ActivityRecording.
    hidden function sportForModality(m) {
        if (m != null && (m.equals("aerobic_base") || m.equals("anaerobic_intervals"))) {
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
