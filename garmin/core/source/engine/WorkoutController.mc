using Toybox.ActivityRecording as Rec;
using Toybox.Activity;
using Toybox.Timer;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.Lang;
using Toybox.WatchUi;
using Toybox.UserProfile;

// Drives one session: recording, HR capture, set/rest progression, and the final
// upload. Mirrors ios/.../WorkoutManager.swift + WorkoutSessionState.swift.
class WorkoutController {

    // States (mirror WorkoutSessionState phases). DONE: every step is finished but
    // the activity is still recording, as on Garmin's own workouts — "Workout
    // complete" shows and the athlete saves from the stop menu.
    enum {
        IDLE, ACTIVE, RESTING, COMPLETE, DONE
    }

    // Reservoir capacity. Matches the <= 600 both upload paths already enforce.
    const SAMPLE_CAP = 600;

    enum { PHASE_WORK, PHASE_REST }
    enum { SIDE_LEFT, SIDE_RIGHT }

    hidden var _session;        // WorkoutSession
    hidden var _state;
    hidden var _exIndex;
    hidden var _restRemaining;  // seconds
    hidden var _restTotal;      // the full rest period, for the draining ring
    hidden var _sync;

    // Recording + metrics.
    hidden var _rec;            // ActivityRecording session
    hidden var _timer;
    hidden var _startMoment;
    hidden var _elapsed;        // seconds since start

    // HR reservoir — FIXED capacity, decimating. An unbounded per-second array
    // would reach 21,600 entries on a 6-hour mountain day (~346 KB across
    // the two arrays, 45% of the 768 KB app limit) and the app would die before
    // finish() ever saved the FIT. Both consumers already subsample to <= 600,
    // so capping here is lossless relative to what is actually uploaded.
    hidden var _hrOff;          // [Number] second offsets, _hrN valid entries
    hidden var _hrVal;          // [Number] bpm
    hidden var _hrN;            // entries in use
    hidden var _hrStride;       // current decimation stride (doubles on overflow)
    hidden var _hrPhase;        // samples seen since the last kept one
    hidden var _hrSum;
    hidden var _hrCount;
    hidden var _hrPeak;
    hidden var _hrLast;         // last sampled bpm, so onUpdate never has to
                                // call Activity.getActivityInfo() itself
    hidden var _zoneSec;        // [Number] seconds in zones 1-5 (index 0-4), for HR Zones

    // GPS / distance / elevation — captured for cardio sessions only.
    // Parallel Float arrays rather than an array of {lat,lng,altitude}
    // Dictionaries: 4,320 three-entry Dictionaries is ~490 KB, three fixed
    // Float arrays are ~14 KB. The Dictionaries are built once, in
    // buildSummary(), where they are actually needed.
    hidden var _isCardio;
    hidden var _distanceM;      // meters (Activity.Info.elapsedDistance)
    hidden var _ascent;         // meters climbed (Activity.Info.totalAscent)
    hidden var _descent;        // meters descended (Activity.Info.totalDescent)
    hidden var _gpsLat;
    hidden var _gpsLng;
    hidden var _gpsAlt;
    hidden var _gpsN;
    hidden var _gpsStride;
    hidden var _gpsPhase;
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
    hidden var _lapDue;         // a lap to mark on the next tick (markLap)

    // Real work/rest interval structure, from the slot's workSec/intervalRestSec.
    // Deriving an interval as (total time / rounds) cannot express Tabata — 8
    // rounds of 20s work and 10s rest is a 30s cycle, not a 30s work period.
    hidden var _workSec;        // 0 when the slot is not interval-structured
    hidden var _intRestSec;
    hidden var _intPhase;       // PHASE_WORK | PHASE_REST
    hidden var _intPhaseLeft;   // seconds remaining in the current phase

    // Side alternation for unilateral movements (TGU, single-leg, lunges).
    hidden var _side;           // SIDE_LEFT | SIDE_RIGHT
    hidden var _sideReps;       // reps logged on the current side

    // Static hold run state.
    hidden var _holdLeft;       // seconds remaining in the active hold, 0 = idle
    hidden var _holdRunning;

    // The working set (sets_reps): what LAP logs. Seeded from the prescription when
    // the exercise becomes active; Edit Set changes the last logged set and carries
    // the new values forward to the sets after it, as Garmin's Strength does.
    hidden var _editReps;
    hidden var _editWeight;     // kg, or null when the slot prescribes no load
    hidden var _editRpe;        // or null
    hidden var _advanceAfterRest;  // the rest follows an exercise's last set
    hidden var _lastLogName;    // where the last logged set lives, for Edit Set
    hidden var _lastLogIdx;
    hidden var _calories;       // Activity.Info.calories, kcal
    hidden var _speed;          // Activity.Info.currentSpeed, m/s (cardio)
    hidden var _gateRest;       // this interval rest ends on HR, not on the clock
    hidden var _gateBelow;      // consecutive seconds under the HR target
    hidden var _metroTimer;     // the metronome's own beat (1 Hz is too slow for 70 RPM)
    hidden var _metroMs;        // its current period, 0 when stopped
    hidden var _metronome;      // metronome on (hold-UP toggles it)
    hidden var _alert;          // a step alert waiting to be shown: [title, line]
    hidden var _te;             // Activity.Info.trainingEffect, read at the end

    // setLogs: { exerciseId => [ {reps, weightKg, rpe} ] }
    hidden var _setLogs;
    hidden var _outcomes;   // name -> { durationSec, distanceKm }: what a step produced that is not a set
    hidden var _exStartDistM;   // _distanceM when the current exercise became active
    hidden var _stepTimes;      // exercise index -> [exercise, start, end] in _elapsed seconds
    hidden var _resultDecision; // "save" | "dismiss" | null: the Results menu's answer
    hidden var _entered;        // name -> true: a result the athlete typed, which the clock never overwrites
    hidden var _uploadOk;   // null until the upload resolves
    hidden var _lastError;  // first failure swallowed to keep the workout alive
    hidden var _paused;     // stop menu open: clock and recording held
    hidden var _discarded;  // ended without saving or uploading
    hidden var _countIn;    // Countdown Start: seconds left before the timer starts, 0 = none

    function initialize(session, sync) {
        _session = session;
        _sync = sync;
        _state = IDLE;
        _exIndex = 0;
        _restRemaining = 0; _restTotal = 0;
        _elapsed = 0;
        _hrOff = new [SAMPLE_CAP];
        _hrVal = new [SAMPLE_CAP];
        _hrN = 0; _hrStride = 1; _hrPhase = 0;
        _hrSum = 0; _hrCount = 0; _hrPeak = 0; _hrLast = null;
        _zoneSec = [0, 0, 0, 0, 0];
        _isCardio = false;
        _distanceM = 0; _ascent = 0; _descent = 0;
        _gpsLat = new [SAMPLE_CAP];
        _gpsLng = new [SAMPLE_CAP];
        _gpsAlt = new [SAMPLE_CAP];
        _gpsN = 0; _gpsStride = 1; _gpsPhase = 0;
        _lastGpsSec = -1000;
        _hrZones = null;
        _driftSec = 0; _pendingDir = 0; _driftDir = 0;
        _exStartSec = 0;
        _emomInterval = 0; _emomTotal = 0; _emomRound = 1;
        _amrapRounds = 0; _capSec = 0; _capBuzzed = false;
        _workSec = 0; _intRestSec = 0; _intPhase = PHASE_WORK; _intPhaseLeft = 0;
        _side = SIDE_LEFT; _sideReps = 0;
        _holdLeft = 0; _holdRunning = false;
        _editReps = 0; _editWeight = null; _editRpe = null;
        _advanceAfterRest = false;
        _lastLogName = null; _lastLogIdx = 0;
        _calories = 0; _te = null;
        _speed = 0.0; _gateRest = false; _gateBelow = 0; _metroMs = 0;
        _metronome = true; _alert = null;
        _setLogs = {};
        _outcomes = {};
        _exStartDistM = 0;
        _stepTimes = {};
        _resultDecision = null;
        _entered = {};
        _uploadOk = null;
        _lastError = null;
        _paused = false;
        _discarded = false;
        _lapDue = false;
        _countIn = 0;
        seedSetEditor();
    }

    // ── lifecycle ────────────────────────────────────────────────────────────────

    // The workout screen is up but nothing records until START, as on Garmin's
    // own workouts. The clock runs only to show the live HR.
    function prepare() {
        Cues.load();
        _isCardio = isCardioSession();
        _hrZones = readHrZones();
        if (_timer == null) {
            _timer = new Timer.Timer();
            _timer.start(method(:onTick), 1000, true);
        }
    }

    // BACK before START: leave without having recorded anything.
    function cancel() {
        if (_state != IDLE) { return; }
        _countIn = 0;
        if (_timer != null) { try { _timer.stop(); } catch (e) {} }
        _timer = null;
    }

    function isReady() { return _state == IDLE; }

    // Countdown Start: the seconds left before the timer starts (3, 2, 1), else 0.
    function countInLeft() { return _countIn; }

    // The seconds left of a lead-in into work (3, 2, 1) — Countdown Start's, or a
    // rest's last — else 0: the screen says "Work in 3" while the ticks play.
    function leadInLeft() {
        if (_countIn > 0) { return _countIn; }
        if (Cues.leadInOn && _state == RESTING && _restRemaining > 0
                && _restRemaining <= Vocab.LEAD_IN_SEC) {
            return _restRemaining;
        }
        return 0;
    }

    // START: begin recording — after "Work in 3, 2, 1" when Countdown Start is on,
    // as on Garmin's own activities. The clock is restarted on the press so the
    // counts fall a second apart from it. Set Next values chosen while ready
    // carry over.
    function start() {
        if (_state != IDLE || _countIn > 0) { return; }
        prepare();
        if (Cues.countdownStartOn) {
            _countIn = Vocab.LEAD_IN_SEC;
            if (_timer != null) { try { _timer.stop(); } catch (e) {} }
            _timer = new Timer.Timer();
            _timer.start(method(:onTick), 1000, true);
            Haptics.leadTick();
            return;
        }
        begin();
    }

    hidden function begin() {
        _startMoment = Time.now();
        _rec = Rec.createSession({
            :name => _session.archetypeName(),
            :sport => _isCardio ? Rec.SPORT_RUNNING : Rec.SPORT_TRAINING,
            :subSport => subSportForModality(_session.modalityId())
        });
        _rec.start();
        _state = ACTIVE;
        var r = _editReps;
        var w = _editWeight;
        var p = _editRpe;
        beginExerciseTiming();
        _editReps = r;
        _editWeight = w;
        _editRpe = p;
    }

    function onTick() as Void {
        // A throw in a timer callback kills the whole app mid-set. Keep the
        // workout alive and remember what failed; the finish screen shows it.
        try { tick(); } catch (e) { _lastError = "tick: " + e.getErrorMessage(); }
        try { syncMetronome(); } catch (e) {}
    }

    // A paced work period beats at the target RPM on its own timer (the third of
    // three: this, the clock and the step alert); everything else stops it. An
    // interval paces its work phases only; a timed block (a pentathlon set) is
    // all work.
    hidden function syncMetronome() {
        var ms = 0;
        var ex = currentExercise();
        if (_state == ACTIVE && !_paused && _metronome && ex != null && pacedNow(ex)
                && ex.targetRpm() != null && ex.targetRpm() > 0) {
            ms = 60000 / ex.targetRpm();
        }
        if (ms == _metroMs) { return; }
        stopMetronome();
        if (ms > 0) {
            _metroTimer = new Timer.Timer();
            _metroTimer.start(method(:onBeat), ms, true);
            _metroMs = ms;
        }
    }

    hidden function pacedNow(ex) {
        if (_workSec > 0) { return _intPhase == PHASE_WORK; }
        return ex.isTemplate("timed");
    }

    hidden function stopMetronome() {
        if (_metroTimer != null) { try { _metroTimer.stop(); } catch (e) {} }
        _metroTimer = null;
        _metroMs = 0;
    }

    function onBeat() as Void { Haptics.metronome(); }

    hidden function tick() {
        if (_state == IDLE && _countIn > 0) {
            _countIn -= 1;
            if (_countIn > 0) { Haptics.leadTick(); }
            else { Haptics.leadGo(); begin(); }
            WatchUi.requestUpdate();
            return;
        }
        if (_state == IDLE) {
            var i0 = Activity.getActivityInfo();
            if (i0 != null && i0.currentHeartRate != null) { _hrLast = i0.currentHeartRate; }
            WatchUi.requestUpdate();
            return;
        }
        flushLap();
        if (_paused) { return; }
        _elapsed += 1;
        var info = Activity.getActivityInfo();
        if (info != null && info.currentHeartRate != null) {
            var hr = info.currentHeartRate;
            _hrLast = hr;
            pushHr(_elapsed, hr);
            _hrSum += hr; _hrCount += 1;
            if (hr > _hrPeak) { _hrPeak = hr; }
            var z = zoneOf(hr);
            if (z != null) { _zoneSec[z - 1] += 1; }
        }
        if (info != null) {
            if ((info has :calories) && info.calories != null) { _calories = info.calories; }
            if ((info has :trainingEffect) && info.trainingEffect != null) { _te = info.trainingEffect; }
        }
        if (_isCardio) { captureGps(info); }
        if (_state == ACTIVE) { evaluateHrDrift(); updateIntervalTiming(); }
        if (_state == RESTING) {
            _restRemaining -= 1;
            // Graded cues: the athlete reads these without looking at the watch.
            if (_restRemaining == 30)     { Haptics.restWarn30(); }
            else if (_restRemaining == 10) { Haptics.restWarn10(); }
            if (Cues.leadInOn && Cues.leadIn(_restRemaining) == :tick) { Haptics.leadTick(); }
            if (_restRemaining <= 0) {
                if (Cues.leadInOn) { Haptics.leadGo(); } else { Haptics.restOver(); }
                endRest();
            }
        }
        if (_holdRunning) { tickHold(); }
        StepAlert.flush(self);
        WatchUi.requestUpdate();
    }

    // ── bounded sample reservoirs ──────────────────────────────────────────────────

    // Keep every _hrStride-th sample. On overflow, halve the buffer in place and
    // double the stride — amortized O(1) per sample, and it runs at most
    // log2(21600/600) ~= 6 times across a 6-hour session. Coverage stays uniform
    // across the whole session rather than truncating at the cap.
    hidden function pushHr(sec, bpm) {
        _hrPhase += 1;
        if (_hrPhase < _hrStride) { return; }
        _hrPhase = 0;
        if (_hrN >= SAMPLE_CAP) {
            var w = 0;
            for (var r = 0; r < _hrN; r += 2) {
                _hrOff[w] = _hrOff[r]; _hrVal[w] = _hrVal[r]; w += 1;
            }
            _hrN = w; _hrStride *= 2;
        }
        _hrOff[_hrN] = sec; _hrVal[_hrN] = bpm; _hrN += 1;
    }

    // Same scheme for the GPS track. alt may be null.
    hidden function pushGps(lat, lng, alt) {
        _gpsPhase += 1;
        if (_gpsPhase < _gpsStride) { return; }
        _gpsPhase = 0;
        if (_gpsN >= SAMPLE_CAP) {
            var w = 0;
            for (var r = 0; r < _gpsN; r += 2) {
                _gpsLat[w] = _gpsLat[r]; _gpsLng[w] = _gpsLng[r]; _gpsAlt[w] = _gpsAlt[r];
                w += 1;
            }
            _gpsN = w; _gpsStride *= 2;
        }
        _gpsLat[_gpsN] = lat; _gpsLng[_gpsN] = lng; _gpsAlt[_gpsN] = alt;
        _gpsN += 1;
    }

    // Capture distance / elevation / a subsampled GPS point from Activity.Info.
    // Every field is guarded with `has` + null checks: indoor sessions and watches
    // without a GPS fix simply contribute nothing.
    hidden function captureGps(info) {
        if (info == null) { return; }
        if ((info has :elapsedDistance) && info.elapsedDistance != null) {
            _distanceM = info.elapsedDistance;
        }
        if ((info has :currentSpeed) && info.currentSpeed != null) {
            _speed = info.currentSpeed;
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
                pushGps(deg[0], deg[1], alt);
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
            Haptics.hrDrift(dir);
            // Garmin's target alert, in words as well as a buzz.
            Native.toast((dir > 0) ? "Heart rate too high" : "Heart rate too low", false);
        }
    }

    // Set up interval state when an exercise becomes active. EMOM interval is
    // derived from the prescribed total time / rounds (falling back to 60s);
    // AMRAP reads its time cap.
    hidden function beginExerciseTiming() {
        _exStartSec = _elapsed;
        _exStartDistM = _distanceM;
        _emomInterval = 0; _emomTotal = 0; _emomRound = 1;
        _amrapRounds = 0; _capSec = 0; _capBuzzed = false;
        _workSec = 0; _intRestSec = 0; _intPhase = PHASE_WORK; _intPhaseLeft = 0;
        _side = SIDE_LEFT; _sideReps = 0;
        _holdLeft = 0; _holdRunning = false;
        _gateRest = false; _gateBelow = 0;

        var ex = currentExercise();
        if (ex == null) { return; }
        // A timed step or an AMRAP block is announced as it starts (name, then what
        // it asks for); sets with rests between them are not.
        if (announces(ex)) { queueAlert(ex.name(), Steps.prescription(ex)); }
        // The step runs as its screen spec's template says (ScreenSpec), not by
        // slot type: a package can run a class's timed blocks as a round timer.
        if (ex.isTemplate("interval")) {
            var rounds = ex.targetRounds();
            _emomTotal = (rounds != null) ? rounds : 0;

            // Prefer the prescribed interval. Tabata sends workSec 20 /
            // intervalRestSec 10; EMOM strength sends workSec 60 / rest 0.
            var w = ex.workSec();
            if (w != null && w > 0) {
                _workSec = w;
                var ir = ex.intervalRestSec();
                _intRestSec = (ir != null) ? ir : 0;
            } else {
                // Legacy payload: fall back to splitting the block evenly.
                var tmin = ex.timeMinutes();
                _workSec = (tmin != null && rounds != null && rounds > 0)
                    ? ((tmin * 60) / rounds) : 60;
                _intRestSec = 0;
            }
            _emomInterval = _workSec + _intRestSec;
            _intPhase = PHASE_WORK;
            _intPhaseLeft = _workSec;
        } else if (ex.isTemplate("rounds")) {
            var cap = ex.timeMinutes();
            _capSec = (cap != null) ? (cap * 60) : 0;
        }
        seedSetEditor();
    }

    // ── intervals ────────────────────────────────────────────────────────────────

    function isInterval()       { return _workSec > 0; }
    function intervalPhase()    { return _intPhase; }
    function intervalWorking()  { return _intPhase == PHASE_WORK; }
    function intervalLeft()     { return _intPhaseLeft; }
    function intervalWorkSec()  { return _workSec; }
    function intervalRestSec()  { return _intRestSec; }

    // Fraction of the current work (or rest) period elapsed, for the inner ring.
    function intervalProgress() {
        var span = intervalWorking() ? _workSec : _intRestSec;
        if (span == null || span <= 0) { return 0.0; }
        var done = span - _intPhaseLeft;
        return done.toFloat() / span.toFloat();
    }

    // ── side alternation ─────────────────────────────────────────────────────────

    function side()      { return _side; }
    function sideIsLeft(){ return _side == SIDE_LEFT; }
    function sideReps()  { return _sideReps; }

    function toggleSide() {
        _side = (_side == SIDE_LEFT) ? SIDE_RIGHT : SIDE_LEFT;
        _sideReps = 0;
        Haptics.sideChange();
    }

    // True when the current exercise is counted per side: a unilateral movement,
    // or one its package marks side_tracked (the get-up).
    function needsSideTracking() {
        var ex = currentExercise();
        return ex != null && ex.sideTracked();
    }

    // ── static hold ──────────────────────────────────────────────────────────────

    function holdRunning()   { return _holdRunning; }
    function holdRemaining() { return _holdLeft; }

    function startHold() {
        var ex = currentExercise();
        if (ex == null) { return; }
        var h = ex.holdSeconds();
        _holdLeft = (h != null) ? h : 30;
        _holdRunning = true;
    }

    // Stopping a hold early still records it — a failed hold is data, and the
    // athlete should not have to choose between honesty and progressing.
    function stopHoldEarly() {
        if (!_holdRunning) { return; }
        var actual = holdTarget() - _holdLeft;
        _holdRunning = false;
        _holdLeft = 0;
        var ex = currentExercise();
        logSet(actual, (ex != null) ? ex.weightKg() : null, null);
        Haptics.setLogged();
        if (needsSideTracking()) { toggleSide(); }
        afterSet();
    }

    function holdTarget() {
        var ex = currentExercise();
        if (ex == null) { return 30; }
        var h = ex.holdSeconds();
        return (h != null) ? h : 30;
    }

    // ── session-level progress (outer ring) ──────────────────────────────────────

    // The amrap_movement slots belonging to the current amrap.
    //
    // They arrive as SIBLINGS in the payload, linked by parentSlotRole, so they
    // have to be gathered here rather than read off a nested structure. Rendering
    // them as separate sequential exercises — which is what happened before the
    // link existed — turns one 20-minute AMRAP into three unrelated blocks.
    function componentsForCurrent() {
        var ex = currentExercise();
        if (ex == null) { return null; }
        var role = ex.slotRole();
        if (role == null) { return null; }
        var out = [];
        var list = _session.exercises();
        for (var i = 0; i < list.size(); i += 1) {
            var c = list[i];
            if (!c.slotType().equals("amrap_movement")) { continue; }
            var p = c.parentSlotRole();
            // Fall back to "the nearest preceding amrap" for payloads generated
            // before parentSlotRole existed.
            if (p == null ? (i > _exIndex) : p.equals(role)) { out.add(c); }
        }
        return out;
    }

    // Indices of slots folded into the current amrap, so the screen can skip past
    // them instead of showing each component as its own exercise.
    function isFoldedComponent(i) {
        var list = _session.exercises();
        if (i >= list.size()) { return false; }
        var c = list[i];
        if (!c.slotType().equals("amrap_movement")) { return false; }
        return c.parentSlotRole() != null;
    }

    // ── completion stats ─────────────────────────────────────────────────────────
    //
    // The finish screen used to show a bare green tick and nothing else — no
    // duration, no HR, no set count, no indication of whether the upload landed.

    function avgHR()  { return (_hrCount > 0) ? (_hrSum / _hrCount) : null; }
    function peakHR() { return (_hrPeak > 0) ? _hrPeak : null; }

    // Total sets logged across every exercise this session.
    function totalSetsLogged() {
        var n = 0;
        var keys = _setLogs.keys();
        for (var i = 0; i < keys.size(); i += 1) { n += _setLogs[keys[i]].size(); }
        return n;
    }

    // null = still in flight, true = accepted, false = buffered for retry.
    function uploadOk() { return _uploadOk; }

    function sessionProgress() {
        var total = exerciseTotal();
        if (total == null || total <= 0) { return 0.0; }
        return _exIndex.toFloat() / total.toFloat();
    }

    function modality()      { return _session.modalityId(); }
    function archetypeId()   { return _session.archetypeId(); }
    function archetypeName() { return _session.archetypeName(); }
    function session()       { return _session; }

    // Live distance in km — the distance screens read this rather than the
    // prescription, and the app already tracks it for cardio sessions.
    function distanceKm()    { return _distanceM / 1000.0; }
    function ascentM()       { return _ascent; }

    // The HR zone the athlete is actually in, 1-5, or null.
    function currentZone() { return (_hrLast == null) ? null : zoneOf(_hrLast); }

    // The zone a bpm falls in on the athlete's own boundaries, 1-5 (below zone
    // 1's floor counts as zone 1, as the watch's gauge shows it), or null.
    function zoneOf(hr) {
        if (_hrZones == null || _hrZones.size() < 2) { return null; }
        var top = _hrZones.size() - 1;
        if (top > 5) { top = 5; }
        for (var z = 1; z < top; z += 1) {
            if (hr < _hrZones[z]) { return z; }
        }
        return top;
    }

    // Seconds in each zone, zone 1 first; null when the watch has no zones.
    function zoneSeconds() { return (_hrZones == null || _hrZones.size() < 2) ? null : _zoneSec; }

    // The bpm each zone starts at, zone 1 first (the boundaries' lower edges).
    function zoneFloors() {
        if (_hrZones == null || _hrZones.size() < 2) { return null; }
        var out = [];
        for (var z = 0; z < 5 && z < _hrZones.size() - 1; z += 1) { out.add(_hrZones[z]); }
        return out;
    }

    // Mark a lap in the FIT file. addLap() was never called before, so per-exercise
    // and per-round splits never reached Garmin Connect at all.
    //
    // The lap goes in on the next tick, a second after the cue that came with it.
    // A lap sets off the watch's own lap announcement ("Set 3, 2:00", Settings ▸
    // Audio Prompts, which a watch app cannot turn off), and the announcement
    // swallowed the lead-in's go and the vibration played in the same instant.
    hidden function markLap() { _lapDue = true; }

    hidden function flushLap() {
        if (!_lapDue) { return; }
        _lapDue = false;
        if (_rec != null && (_rec has :addLap)) {
            try { _rec.addLap(); } catch (e) {}
        }
    }

    // Seed the working set from the prescription.
    hidden function seedSetEditor() {
        var ex = currentExercise();
        if (ex == null) {
            _editReps = 0; _editWeight = null; _editRpe = null;
            return;
        }
        _editReps = repsNumber(ex.reps());
        _editWeight = ex.weightKg();
        _editRpe = ex.targetRpe();
    }

    // The server sends reps as text ("5", "8-12", "max"), and the editor does
    // arithmetic on it: DOWN on "5" threw a type error and killed the app. Take
    // the leading whole number, or 8 when there is none ("max", "AMRAP").
    hidden function repsNumber(r) {
        if (r instanceof Lang.Number) { return r; }
        if (!(r instanceof Lang.String)) { return 8; }
        var n = 0;
        var any = false;
        for (var i = 0; i < r.length(); i += 1) {
            var d = "0123456789".find(r.substring(i, i + 1));
            if (d == null) { break; }
            n = (n * 10) + d;
            any = true;
        }
        return any ? n : 8;
    }

    // Set Next: the reps / load / RPE the next sets of this exercise will log.
    function setWorking(vals) {
        if (vals.hasKey("reps"))   { _editReps = vals["reps"]; }
        if (vals.hasKey("weight")) { _editWeight = vals["weight"]; }
        if (vals.hasKey("rpe"))    { _editRpe = vals["rpe"]; }
    }

    function editReps()   { return _editReps; }
    function editWeight() { return _editWeight; }
    function editRpe()    { return _editRpe; }

    // LAP on a sets/reps screen: the set is done. Log the working values, then rest
    // (or move on), as Garmin's Strength activity does on LAP.
    function completeSet() {
        logSet(_editReps, _editWeight, _editRpe);
        _sideReps += 1;
        Haptics.setLogged();
        // Unilateral work alternates automatically: the athlete shouldn't have to
        // press anything extra between sides.
        if (needsSideTracking()) { toggleSide(); }
        afterSet();
    }

    // After a set: rest before the next set; after the last set, rest before the
    // next exercise when the prescription has a rest, else move straight on.
    hidden function afterSet() {
        var ex = currentExercise();
        var rest = Steps.restSec(ex, _session.modalityId());
        if (currentSetCount() < Steps.setCount(ex)) {
            if (rest > 0) { startRest(rest, false); }
            return;
        }
        if (hasNextExercise() && rest > 0) { startRest(rest, true); return; }
        nextExercise();
    }

    // The last logged set, for Edit Set: { reps, weightKg, rpe } or null.
    function lastSet() {
        if (_lastLogName == null || !_setLogs.hasKey(_lastLogName)) { return null; }
        var arr = _setLogs[_lastLogName];
        return (_lastLogIdx < arr.size()) ? arr[_lastLogIdx] : null;
    }

    function lastSetName()   { return _lastLogName; }
    function lastSetNumber() { return _lastLogIdx + 1; }

    // Edit Set: replace the last logged set's values; the sets after it on the
    // same exercise start from the new values.
    function editLastSet(reps, weightKg, rpe) {
        var set = lastSet();
        if (set == null) { return; }
        set["reps"] = reps;
        set["weightKg"] = weightKg;
        set["rpe"] = rpe;
        var ex = currentExercise();
        if (ex != null && ex.name().equals(_lastLogName)) {
            if (reps != null) { _editReps = reps; }
            _editWeight = weightKg;
            _editRpe = rpe;
        }
    }

    // Sets logged for one exercise (the step list's "Now: 2/5").
    function setsDoneFor(ex) {
        if (ex == null) { return 0; }
        var id = ex.name();
        return _setLogs.hasKey(id) ? _setLogs[id].size() : 0;
    }

    // Reps actually logged for one exercise, for a cumulative target (100
    // get-ups): an edited set counts what it logged, not the next set's reps.
    // An exercise prescribed without reps counts its sets.
    function repsDoneFor(ex) {
        if (ex == null || !_setLogs.hasKey(ex.name())) { return 0; }
        var arr = _setLogs[ex.name()];
        if (ex.reps() == null) { return arr.size(); }
        var n = 0;
        for (var i = 0; i < arr.size(); i += 1) {
            var r = arr[i]["reps"];
            if (r instanceof Lang.Number) { n += r; }
        }
        return n;
    }

    // kg moved across every logged set with both reps and a load.
    function totalVolumeKg() {
        var v = 0.0;
        var keys = _setLogs.keys();
        for (var i = 0; i < keys.size(); i += 1) {
            var arr = _setLogs[keys[i]];
            var ex = exerciseNamed(keys[i]);
            for (var j = 0; j < arr.size(); j += 1) {
                var r = arr[j]["reps"];
                var w = arr[j]["weightKg"];
                if (r instanceof Lang.Number && w != null) { v += r * Steps.totalKg(ex, w); }
            }
        }
        return v;
    }

    // "5x3 @ 110" — one exercise's logged sets, for the summary.
    function loggedText(name) {
        if (!_setLogs.hasKey(name)) { return null; }
        var arr = _setLogs[name];
        if (arr.size() == 0) { return null; }
        var r = arr[arr.size() - 1]["reps"];
        var w = arr[arr.size() - 1]["weightKg"];
        var t = arr.size().toString() + "x" + ((r != null) ? r.toString() : "-");
        if (w != null) { t += " @ " + Steps.loadText(exerciseNamed(name), w); }
        return t;
    }

    hidden function exerciseNamed(name) {
        var list = _session.exercises();
        for (var i = 0; i < list.size(); i += 1) {
            if (name.equals(list[i].name())) { return list[i]; }
        }
        return null;
    }

    function calories()       { return _calories; }
    function trainingEffect() { return _te; }

    // The HR reservoir, for the summary's chart.
    function hrCount() { return _hrN; }
    function hrAt(i)   { return _hrVal[i]; }
    function hrSecAt(i) { return _hrOff[i]; }   // the sample's second into the session

    // Where the live HR sits across the five-zone gauge, 0.0-1.0, or null.
    function hrGaugeFraction() {
        if (_hrZones == null || _hrZones.size() < 6 || _hrLast == null) { return null; }
        if (_hrLast <= _hrZones[0]) { return 0.0; }
        for (var z = 1; z <= 5; z += 1) {
            var lo = _hrZones[z - 1];
            var hi = _hrZones[z];
            if (_hrLast < hi || z == 5) {
                var f = (hi > lo) ? ((_hrLast - lo).toFloat() / (hi - lo).toFloat()) : 0.0;
                if (f > 1.0) { f = 1.0; }
                return ((z - 1) + f) / 5.0;
            }
        }
        return 1.0;
    }

    hidden function clampNum(v, lo, hi) {
        return (v < lo) ? lo : ((v > hi) ? hi : v);
    }

    // Interval and timed-step clock, run once a second while ACTIVE. Keyed on the
    // step's template (ScreenSpec), not its slot type:
    //
    //   interval      work and rest phases with their own cues; a target RPM ticks
    //                 the metronome, a hand switch fires mid-set, and a rest with an
    //                 HR target ends once HR has stayed under it for 5 s (the rest
    //                 time is then only a cap). The block ends itself after its last
    //                 round, as Garmin's repeat steps do.
    //   rounds        ends itself when the cap runs out
    //   timed         with a duration: ends itself at 0:00 (a round_timer block
    //                 does not: LAP counts its rounds and leaves it); a hand
    //                 switch fires at its second, as in an interval's work
    //
    // LAP still ends any of them early.
    hidden function updateIntervalTiming() {
        var ex = currentExercise();
        if (ex == null) { return; }
        var since = _elapsed - _exStartSec;

        if (ex.isTemplate("interval") && _workSec > 0) {
            _intPhaseLeft -= 1;
            if (_intPhase == PHASE_WORK) {
                var sw = ex.switchAtSec();
                if (sw != null && (_workSec - _intPhaseLeft) == sw) {
                    toggleSide();
                    queueAlert("Switch hands", (_side == SIDE_LEFT) ? "Left hand" : "Right hand");
                }
            } else if (_gateRest) {
                var gate = ex.restUntilHr();
                if (_hrLast != null && gate != null && _hrLast < gate) { _gateBelow += 1; }
                else { _gateBelow = 0; }
                // Under the target: the rest is over, after the lead-in when it is on.
                var lead = (Cues.leadInOn && (_emomTotal == 0 || _emomRound < _emomTotal))
                    ? Vocab.LEAD_IN_SEC : 0;
                if (_gateBelow >= 5 && _intPhaseLeft > lead) { _intPhaseLeft = lead; }
            }
            // The lead-in into the next round's work: the end of a rest, or of a
            // rest-less EMOM's minute.
            if (Cues.leadInOn && _intPhaseLeft > 0 && Cues.leadIn(_intPhaseLeft) == :tick
                    && (_emomTotal == 0 || _emomRound < _emomTotal)
                    && (_intPhase == PHASE_REST || _intRestSec == 0)) {
                Haptics.leadTick();
            }
            if (_intPhaseLeft > 0) { return; }

            if (_intPhase == PHASE_WORK && _intRestSec > 0) {
                // Work -> rest. Distinct cue: the athlete must stop, not start.
                _intPhase = PHASE_REST;
                _gateRest = (ex.restUntilHr() != null);
                _gateBelow = 0;
                _intPhaseLeft = _intRestSec;
                Haptics.intervalRest();
                if (_workSec >= 60 || _gateRest) { queueAlert(restLabel(ex), restValue(ex)); }
                return;
            }

            // Rest -> work, or a rest-less EMOM rolling to the next minute.
            if (_emomTotal > 0 && _emomRound >= _emomTotal) {
                nextExercise();
                return;
            }
            _emomRound += 1;
            _intPhase = PHASE_WORK;
            _gateRest = false;
            _intPhaseLeft = _workSec;
            markLap();
            if (Cues.leadInOn) { Haptics.leadGo(); } else { Haptics.intervalWork(); }
            if (_workSec >= 60 || ex.restUntilHr() != null) {
                queueAlert(workLabel(ex) + " " + _emomRound.toString() + "/" + _emomTotal.toString(),
                           workValue(ex));
            }

        } else if (ex.isTemplate("rounds") && _capSec > 0) {
            if (since >= _capSec && !_capBuzzed) {
                _capBuzzed = true;
                Haptics.sessionComplete();
                nextExercise();
            }
        } else if (ex.isTemplate("timed")) {
            var sw = ex.switchAtSec();
            if (sw != null && since == sw) {
                toggleSide();
                queueAlert("Switch hands", (_side == SIDE_LEFT) ? "Left hand" : "Right hand");
            }
            var mins = ex.durationMinutes();
            if (mins != null && mins > 0 && since >= mins * 60) {
                Haptics.restOver();
                nextExercise();
            }
        }
    }

    // Garmin's own words for interval phases: Run / Recover on a run, Work / Rest
    // otherwise.
    function isRunInterval(ex) {
        return ex != null && ex.zoneLower() != null && ex.targetRpm() == null && isLocomotion(ex);
    }
    function workLabel(ex) { return isRunInterval(ex) ? "Run" : "Work"; }
    function restLabel(ex) { return isRunInterval(ex) ? "Recover" : "Rest"; }

    function workValue(ex) {
        var t = Text.mmss(_workSec);
        if (ex.targetRpm() != null) { return t + "  " + ex.targetRpm().toString() + " RPM"; }
        var z = ex.zoneLower();
        if (z != null) {
            var hi = ex.zoneUpper();
            return t + "  Zone " + z.toString() + ((hi != null && hi != z) ? ("-" + hi.toString()) : "");
        }
        return t;
    }

    function restValue(ex) {
        var gate = ex.restUntilHr();
        if (gate != null) { return "until HR " + gate.toString(); }
        return Text.mmss(_intRestSec);
    }

    function gateRest()       { return _gateRest; }
    function restPhaseElapsed() { return _intRestSec - _intPhaseLeft; }
    function metronomeOn()    { return _metronome; }
    function toggleMetronome() { _metronome = !_metronome; syncMetronome(); }

    // "5:12" per km from the live speed, or "--" when standing.
    function paceText() {
        if (_speed == null || _speed < 0.3) { return "--"; }
        return Text.mmss((1000.0 / _speed).toNumber());
    }

    function isCardio() { return _isCardio; }

    // Step alerts: queued by the engine, shown by StepAlert from the tick or a
    // key handler, so the controller never pushes a view itself.
    hidden function queueAlert(title, line) { _alert = [title, line]; }

    hidden function announces(ex) {
        if (ex.isTemplate("interval") || ex.isTemplate("rounds") || ex.isTemplate("for_time")) { return true; }
        return (ex.isTemplate("timed") || ex.isTemplate("round_timer"))
            && ex.durationMinutes() != null && ex.durationMinutes() > 0;
    }
    function takeAlert() { var a = _alert; _alert = null; return a; }

    // Static hold countdown, with the same graded end-of-period cue.
    hidden function tickHold() {
        _holdLeft -= 1;
        if (_holdLeft == 3) { Haptics.leadTick(); }
        if (_holdLeft <= 0) {
            _holdRunning = false;
            _holdLeft = 0;
            Haptics.restOver();
            logSet(holdTarget(), currentExercise() != null ? currentExercise().weightKg() : null, null);
            if (needsSideTracking()) { toggleSide(); }
            afterSet();
        }
    }

    // Log one completed AMRAP / for-time round (mirrored into setLogs so it uploads).
    function logRound() {
        _amrapRounds += 1;
        markLap();
        Haptics.lap();
        var ex = currentExercise();
        if (ex == null) { return; }
        _setLogs[ex.name()] = [ { "reps" => _amrapRounds, "weightKg" => null, "rpe" => null } ];
    }

    function emomRound()          { return _emomRound; }

    // The movement of the round in progress: an alternating interval's even
    // rounds are its alternate (the payload's alternateName); every other step,
    // and a step not the current one, is its own name.
    function roundName(ex) {
        var alt = ex.alternateName();
        if (alt == null || !ex.isTemplate("interval") || ex != currentExercise()) { return ex.name(); }
        return WorkoutController.alternatesAt(_emomRound) ? alt : ex.name();
    }

    // Odd rounds the step's own movement, even rounds its alternate.
    static function alternatesAt(round) { return round % 2 == 0; }
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

    // What a step produced that is not a set: a for-time step's clock, the
    // distance a distance step covered. Read when the step is left (its last
    // round, Skip, or Save mid-step) and kept by exercise for the upload.
    hidden function noteStepEnd(ex) {
        if (ex == null) { return; }
        // The step's window, for the session log's exerciseTimeline: a step
        // returned to keeps its first start.
        var start = _stepTimes.hasKey(_exIndex) ? _stepTimes[_exIndex][1] : _exStartSec;
        _stepTimes[_exIndex] = [ex, start, _elapsed];
        if (_entered.hasKey(ex.name())) { return; }
        var out = _outcomes.hasKey(ex.name()) ? _outcomes[ex.name()] : {};
        // A clock, a timed block's seconds (a cadence is its reps over them)
        // and an interval's seconds.
        if (ex.isTemplate("for_time") || ex.isTemplate("timed") || ex.isTemplate("interval")) {
            out["durationSec"] = exerciseElapsedSec();
        }
        // An interval's rounds: those whose work was done — the one in progress
        // when the step was left mid-work does not count.
        if (ex.isTemplate("interval") && _workSec > 0) {
            out["rounds"] = intervalRoundsDone(_emomRound, _intPhase == PHASE_WORK, _intPhaseLeft);
        }
        var d = _distanceM - _exStartDistM;
        if ((ex.isTemplate("distance") || isLocomotion(ex)) && d > 0) { out["distanceKm"] = d / 1000.0; }
        if (out.size() > 0) { _outcomes[ex.name()] = out; }
    }

    // The rounds of an interval step done when it was left: the current round,
    // less one when its work was still running.
    static function intervalRoundsDone(round, inWork, phaseLeft) {
        var done = (inWork && phaseLeft > 0) ? round - 1 : round;
        return (done > 0) ? done : 0;
    }

    // ── test results (the standards a session tests) ─────────────────────────────

    // Save pressed mid-step (a run finished without a LAP): the step's clock
    // is read now, so the Results menu shows it instead of asking for it.
    function closeStep() {
        if (_state == ACTIVE || _state == RESTING) { noteStepEnd(currentExercise()); }
    }

    // The session's scored test steps, in order; empty on any other day.
    function testSteps() {
        var out = [];
        var list = _session.exercises();
        for (var i = 0; i < list.size(); i += 1) {
            if (list[i].standard() != null) { out.add(list[i]); }
        }
        return out;
    }

    // What one test step produced, as a number in the step's own terms —
    // seconds for a clock or a hold, a count of reps or rounds, km — or null.
    function resultValue(ex) {
        var st = ex.standard();
        var kind = (st != null) ? st["result"] : null;
        if (kind == null) { return null; }
        var name = ex.name();
        var o = _outcomes.hasKey(name) ? _outcomes[name] : {};
        if (kind.equals("duration")) { return o.hasKey("durationSec") ? o["durationSec"] : null; }
        if (kind.equals("distance")) { return o.hasKey("distanceKm") ? o["distanceKm"] : null; }
        if (!_setLogs.hasKey(name) || _setLogs[name].size() == 0) { return null; }
        var arr = _setLogs[name];
        if (kind.equals("rounds")) { return arr[0]["reps"]; }
        // reps: summed over a timed step (reps in six minutes), the best set
        // otherwise; a hold: the longest. The server reads them the same way.
        var sum = 0;
        var best = 0;
        for (var i = 0; i < arr.size(); i += 1) {
            var r = arr[i]["reps"];
            if (r instanceof Lang.Number) { sum += r; if (r > best) { best = r; } }
        }
        var v = (kind.equals("reps") && ex.isTemplate("timed")) ? sum : best;
        return (v > 0) ? v : null;
    }

    // "7:32", "102 reps", "20 rounds", "45 s", "2.00 km" — or null.
    function resultText(ex) {
        var v = resultValue(ex);
        if (v == null) { return null; }
        var kind = ex.standard()["result"];
        if (kind.equals("duration")) { return Text.mmss(v); }
        if (kind.equals("distance")) { return v.format("%.2f") + " km"; }
        if (kind.equals("hold")) { return v.toString() + " s"; }
        if (kind.equals("rounds")) { return v.toString() + ((v == 1) ? " round" : " rounds"); }
        return v.toString() + ((v == 1) ? " rep" : " reps");
    }

    // Results > a step: what the athlete counted or corrected, kept where the
    // upload reads it — a timed step's reps as its one set, a clock as the
    // step's durationSec.
    function setResult(ex, v) {
        var kind = ex.standard()["result"];
        var name = ex.name();
        _entered[name] = true;
        if (kind.equals("duration") || kind.equals("distance")) {
            var o = _outcomes.hasKey(name) ? _outcomes[name] : {};
            o[kind.equals("duration") ? "durationSec" : "distanceKm"] = v;
            _outcomes[name] = o;
            return;
        }
        var arr = _setLogs.hasKey(name) ? _setLogs[name] : [];
        if (kind.equals("rounds") || arr.size() == 0 || ex.isTemplate("timed")) {
            _setLogs[name] = [ { "reps" => v, "weightKg" => (kind.equals("rounds") ? null : ex.weightKg()), "rpe" => null } ];
            return;
        }
        // A max set among several: the best one is the result.
        var at = 0;
        for (var i = 1; i < arr.size(); i += 1) {
            var r = arr[i]["reps"];
            var b = arr[at]["reps"];
            if (r instanceof Lang.Number && (!(b instanceof Lang.Number) || r > b)) { at = i; }
        }
        arr[at]["reps"] = v;
    }

    function setResultDecision(d) { _resultDecision = d; }

    // ── counts asked at the end (a step's `logs`) ─────────────────────────────

    // The steps whose reps the athlete counts and enters at the end — a timed
    // kettlebell set's, whose cadence is its reps over its seconds. A test step
    // asks for its result instead.
    function countSteps() {
        var out = [];
        var list = _session.exercises();
        for (var i = 0; i < list.size(); i += 1) {
            if (list[i].standard() == null && list[i].asksReps()) { out.add(list[i]); }
        }
        return out;
    }

    // The reps entered for a count step, or null before they are.
    function countValue(ex) {
        var name = ex.name();
        if (!_entered.hasKey(name) || !_setLogs.hasKey(name) || _setLogs[name].size() == 0) { return null; }
        return _setLogs[name][0]["reps"];
    }

    // The count as the step's one set, as a timed test's reps are.
    function setCount(ex, v) {
        _entered[ex.name()] = true;
        _setLogs[ex.name()] = [ { "reps" => v, "weightKg" => ex.weightKg(), "rpe" => null } ];
    }

    // ── progression ────────────────────────────────────────────────────────────────    // ── progression ────────────────────────────────────────────────────────────────

    function state()           { return _state; }
    function currentExercise() {
        var list = _session.exercises();
        return (_exIndex < list.size()) ? list[_exIndex] : null;
    }
    function exerciseIndex()    { return _exIndex; }
    function exerciseTotal()    { return _session.exerciseCount(); }
    function restRemaining()    { return _restRemaining; }
    function restTotal()        { return _restTotal; }

    // Name of the exercise after this one, so the rest screen can show it.
    function nextExerciseName() {
        var list = _session.exercises();
        var i = _exIndex;
        // The current exercise is still active during its own inter-set rest.
        if (currentSetCount() >= ((currentExercise() != null
                                   && currentExercise().sets() != null)
                                  ? currentExercise().sets() : 1)) {
            i += 1;
            while (i < list.size() && isFoldedComponent(i)) { i += 1; }
        }
        return (i < list.size()) ? list[i].name() : null;
    }
    function elapsedSec()       { return _elapsed; }
    // Served from the 1 Hz tick cache — onUpdate calls this every frame, and
    // Activity.getActivityInfo() is not free. The value cannot change between ticks.
    function currentHR() { return _hrLast; }

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
        _lastLogName = id;
        _lastLogIdx = _setLogs[id].size() - 1;
    }

    hidden function startRest(sec, advance) {
        if (sec == null || sec <= 0) { return; }
        _restRemaining = sec;
        _restTotal = sec;
        _advanceAfterRest = advance;
        _state = RESTING;
    }

    // LAP during a rest ends it, as on Garmin's Strength.
    function skipRest() {
        if (_state != RESTING) { return; }
        _restRemaining = 0;
        endRest();
    }

    hidden function endRest() {
        var adv = _advanceAfterRest;
        _advanceAfterRest = false;
        if (adv) { nextExercise(); } else { _state = ACTIVE; }
    }

    function restAdvances() { return _advanceAfterRest; }

    // Skip (hold-UP menu): leave the current exercise, rest included.
    function skip() {
        if (_state == DONE || _state == COMPLETE) { return; }
        _advanceAfterRest = false;
        nextExercise();
    }

    function hasNextExercise() { return nextIndex() < _session.exerciseCount(); }

    function upcomingExercise() {
        var i = nextIndex();
        var list = _session.exercises();
        return (i < list.size()) ? list[i] : null;
    }

    hidden function nextIndex() {
        var i = _exIndex + 1;
        while (i < _session.exerciseCount() && isFoldedComponent(i)) { i += 1; }
        return i;
    }

    // The next step, for the "Next:" line: [title, value].
    function nextStep() {
        var ex = currentExercise();
        if (_state == DONE || ex == null) { return ["Finish", null]; }
        if (_state == RESTING) {
            if (_advanceAfterRest) { return stepOf(upcomingExercise()); }
            var n = Steps.setCount(ex);
            return [ex.name(), "Set " + (currentSetCount() + 1).toString() + "/" + n.toString()
                               + "  " + Steps.preview(ex)];
        }
        var rest = Steps.restSec(ex, _session.modalityId());
        if (Steps.isSetBased(ex) && rest > 0
                && (currentSetCount() + 1 < Steps.setCount(ex) || hasNextExercise())) {
            return ["Rest", Text.mmss(rest)];
        }
        return stepOf(upcomingExercise());
    }

    hidden function stepOf(ex) {
        if (ex == null) { return ["Finish", null]; }
        return [ex.name(), Steps.preview(ex)];
    }

    // Advance to the next exercise (or finish).
    function nextExercise() {
        noteStepEnd(currentExercise());
        _exIndex += 1;
        // Skip component movements already folded into the AMRAP screen above —
        // they are part of that round, not separate exercises to work through.
        while (_exIndex < _session.exerciseCount() && isFoldedComponent(_exIndex)) {
            _exIndex += 1;
        }
        if (_exIndex >= _session.exerciseCount()) {
            // Every step done. Keep recording until the athlete saves, as Garmin's
            // own workouts do; the screen says "Workout complete".
            _state = DONE;
            _advanceAfterRest = false;
            markLap();
            Haptics.sessionComplete();
            queueAlert("Workout complete", "Press START to save");
        } else {
            _state = ACTIVE;
            _driftSec = 0; _pendingDir = 0; _driftDir = 0;   // reset drift latch per exercise
            markLap();
            beginExerciseTiming();
        }
    }

    // The stop menu (Resume / Save / Discard) opens: hold the clock and the
    // recording. Resume continues the same FIT session.
    function pause() {
        if (_state == COMPLETE || _paused) { return; }
        flushLap();
        _paused = true;
        stopMetronome();
        try { if (_rec != null) { _rec.stop(); } } catch (e) { noteError("pause", e); }
    }

    function resume() {
        if (!_paused) { return; }
        _paused = false;
        try { if (_rec != null) { _rec.start(); } } catch (e) { noteError("resume", e); }
        WatchUi.requestUpdate();
    }

    function isPaused() { return _paused; }

    // End without saving: nothing is written to the activity list or uploaded.
    function discardSession() {
        if (_state == COMPLETE) { return; }
        if (_state == IDLE) { cancel(); _state = COMPLETE; _discarded = true; return; }
        _state = COMPLETE;
        _paused = false;
        _discarded = true;
        if (_timer != null) { try { _timer.stop(); } catch (e) {} }
        stopMetronome();
        try {
            if (_rec != null) { _rec.stop(); _rec.discard(); }
        } catch (e) { noteError("discard", e); }
    }

    function wasDiscarded() { return _discarded; }

    // Leaving before the upload answered: buffer it so the next open retries.
    function parkPendingUpload() {
        if (_uploadOk == null && !_discarded && _sync != null) { _sync.parkPending(); }
    }

    function finish() {
        // Idempotent: the BACK confirmation, the session menu and AppBase.onStop()
        // can all reach here, and stop()/save() must not run twice.
        if (_state == COMPLETE) { return; }
        // Never started: nothing was recorded, so nothing is saved or uploaded.
        if (_state == IDLE) { cancel(); _state = COMPLETE; _discarded = true; return; }
        // Saved mid-step (Fran finished, Save pressed before the last LAP):
        // the step's clock still counts.
        if (_state != DONE) { try { noteStepEnd(currentExercise()); } catch (e) {} }
        _state = COMPLETE;
        _paused = false;
        if (_timer != null) { try { _timer.stop(); } catch (e) {} }
        stopMetronome();
        try {
            var info = Activity.getActivityInfo();
            if (info != null && (info has :trainingEffect) && info.trainingEffect != null) {
                _te = info.trainingEffect;
            }
        } catch (e) {}
        // Each step is guarded on its own: whichever one fails must not stop the
        // workout reaching its finish screen, and the failure is shown there.
        try {
            if (_rec != null) {
                flushLap();
                _rec.stop();
                // A demo session is not a real activity: discard it rather than
                // writing it to the watch's history (and on to Garmin Connect).
                if (DemoSession.enabled()) { _rec.discard(); } else { _rec.save(); }
            }
        } catch (e) { noteError("save", e); }
        // The glance's ring and the pre-start page's "Completed" read this.
        try { DayLog.record(_session.sessionId(), _elapsed / 60, totalSetsLogged()); } catch (e) {}
        try {
            _sync.uploadSession(buildSummary(), method(:onUploadDone));
        } catch (e) {
            noteError("summary", e);
            _uploadOk = false;
        }
    }

    hidden function noteError(where, e) {
        if (_lastError == null) { _lastError = where + ": " + e.getErrorMessage(); }
    }

    function lastError() { return _lastError; }

    function onUploadDone(success, data) as Void {
        // The finish screen reports this, so a failed sync is visible rather than
        // silent. A failure is still buffered and retried on next open.
        _uploadOk = success;
        WatchUi.requestUpdate();
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
            var track = buildGpsTrack();
            if (track.size() > 0) { workout["gpsTrack"] = track; }
        }

        var sessionLog = {
            "sessionKey" => key,
            "completedAt" => endIso,
            "source" => "garmin",
            "exercises" => Wire.exercises(_setLogs, _outcomes, _session.exercises()),
            "exerciseTimeline" => Wire.timeline(_stepTimes),
            "notes" => "",
            "avgHR" => avgHR,
            "peakHR" => peakHR
        };
        // Save results / Not a test, for each test step that produced a value;
        // the server makes each a result only then (src/standard_results.py).
        if (_resultDecision != null) {
            var decisions = {};
            var steps = testSteps();
            for (var i = 0; i < steps.size(); i += 1) {
                if (resultValue(steps[i]) != null) {
                    decisions[steps[i].standard()["id"]] = { "decision" => _resultDecision };
                }
            }
            if (decisions.size() > 0) { sessionLog["standardResults"] = decisions; }
        }

        return {
            "sessionKey" => key,
            "date" => dateStr,
            "source" => "garmin",
            "workout" => workout,
            "sessionLog" => sessionLog
            // Resting HR, Body Battery and recovery time are not per session:
            // SyncManager.sendWellness posts them once a day, on app open.
        };
    }

    // Walk the reservoir and stamp absolute times. The reservoir is already
    // bounded at SAMPLE_CAP, so no further subsampling is needed here.
    hidden function buildHrSamples(startIso) {
        var out = [];
        if (_hrN == 0) { return out; }
        var base = _startMoment.value();   // epoch seconds
        for (var i = 0; i < _hrN; i += 1) {
            var ts = new Time.Moment(base + _hrOff[i]);
            out.add({ "timestamp" => isoFromMoment(ts), "bpm" => _hrVal[i] });
        }
        return out;
    }

    // Materialize the GPS Dictionaries only here, at upload time.
    hidden function buildGpsTrack() {
        var out = [];
        for (var i = 0; i < _gpsN; i += 1) {
            out.add({ "lat" => _gpsLat[i], "lng" => _gpsLng[i], "altitude" => _gpsAlt[i] });
        }
        return out;
    }

    // ── helpers ────────────────────────────────────────────────────────────────

    // "YYYY-MM-DDTHH:MM:SSZ" in UTC — parseable by the backend's ISO8601 reader.
    hidden function isoFromMoment(moment) {
        var g = Gregorian.utcInfo(moment, Time.FORMAT_SHORT);
        return Lang.format("$1$-$2$-$3$T$4$:$5$:$6$Z", [
            g.year.format("%04d"), g.month.format("%02d"), g.day.format("%02d"),
            g.hour.format("%02d"), g.min.format("%02d"), g.sec.format("%02d")
        ]);
    }

    // A session is cardio — GPS, distance, the run page, the RUNNING sport type —
    // when its modality is aerobic AND it actually moves: a run, a ruck, a hike. An
    // aerobic-base kettlebell session (anti-glycolic swings) is aerobic work done on
    // the spot, and recording it as a run with GPS was wrong.
    hidden function isCardioSession() {
        var m = _session.modalityId();
        if (!isCardioModality(m) && (m == null || !m.equals("durability"))) { return false; }
        var list = _session.exercises();
        for (var i = 0; i < list.size(); i += 1) {
            if (isLocomotion(list[i])) { return true; }
        }
        return false;
    }

    function isLocomotion(ex) {
        if (ex == null) { return false; }
        var c = ex.category();
        var p = ex.movementPattern();
        if (c != null && c.equals("aerobic")) { return true; }
        if (p != null && (p.equals("aerobic_monostructural") || p.equals("locomotion"))) { return true; }
        return ex.isTemplate("distance") && ex.distanceKm() != null;
    }

    // Cardio modalities drive GPS/distance capture and the RUNNING sport type.
    hidden function isCardioModality(m) {
        return m != null && (m.equals("aerobic_base") || m.equals("anaerobic_intervals"));
    }

    // SUB_SPORT_* are ActivityRecording constants (verified against SDK 9.2.0 by
    // compilation — an unknown symbol fails the monkeyc build).
    hidden function subSportForModality(m) {
        if (m == null) { return Rec.SUB_SPORT_GENERIC; }
        if (m.find("strength") != null || m.equals("power")) {
            return Rec.SUB_SPORT_STRENGTH_TRAINING;
        }
        if (m.equals("aerobic_base")) { return Rec.SUB_SPORT_CARDIO_TRAINING; }
        return Rec.SUB_SPORT_GENERIC;
    }
}
