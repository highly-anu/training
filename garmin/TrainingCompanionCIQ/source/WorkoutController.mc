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
    // would reach 21,600 entries on a 6-hour long_mountain_day (~346 KB across
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

    // On-wrist editable working set (sets_reps). Seeded from the prescription when
    // the exercise becomes active; UP/DOWN adjust the focused field, BACK cycles it.
    hidden var _editReps;
    hidden var _editWeight;     // kg, or null when the slot prescribes no load
    hidden var _editRpe;        // or null
    hidden var _editFields;     // applicable field ids, e.g. ["reps","weight"]
    hidden var _editFieldIdx;

    // setLogs: { exerciseId => [ {reps, weightKg, rpe} ] }
    hidden var _setLogs;
    hidden var _uploadOk;   // null until the upload resolves

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
        _editFields = ["reps"]; _editFieldIdx = 0;
        _setLogs = {};
        _uploadOk = null;
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
            _hrLast = hr;
            pushHr(_elapsed, hr);
            _hrSum += hr; _hrCount += 1;
            if (hr > _hrPeak) { _hrPeak = hr; }
        }
        if (_isCardio) { captureGps(info); }
        if (_state == ACTIVE) { evaluateHrDrift(); updateIntervalTiming(); }
        if (_state == RESTING) {
            _restRemaining -= 1;
            // Graded cues: the athlete reads these without looking at the watch.
            if (_restRemaining == 30)     { Haptics.restWarn30(); }
            else if (_restRemaining == 10) { Haptics.restWarn10(); }
            if (_restRemaining <= 0) {
                Haptics.restOver();
                _state = ACTIVE;
            }
        }
        if (_holdRunning) { tickHold(); }
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
        }
    }

    // Set up interval state when an exercise becomes active. EMOM interval is
    // derived from the prescribed total time / rounds (falling back to 60s);
    // AMRAP reads its time cap.
    hidden function beginExerciseTiming() {
        _exStartSec = _elapsed;
        _emomInterval = 0; _emomTotal = 0; _emomRound = 1;
        _amrapRounds = 0; _capSec = 0; _capBuzzed = false;
        _workSec = 0; _intRestSec = 0; _intPhase = PHASE_WORK; _intPhaseLeft = 0;
        _side = SIDE_LEFT; _sideReps = 0;
        _holdLeft = 0; _holdRunning = false;

        var ex = currentExercise();
        if (ex == null) { return; }
        var slot = ex.slotType();
        if (slot.equals("emom")) {
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
        } else if (slot.equals("amrap")) {
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

    // True when the current exercise needs left/right tracking.
    function needsSideTracking() {
        var ex = currentExercise();
        return ex != null && ex.isUnilateral();
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
        var target = (ex != null && ex.sets() != null) ? ex.sets() : 1;
        if (currentSetCount() >= target) { nextExercise(); } else { startRest(); }
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
    function currentZone() {
        if (_hrZones == null || _hrLast == null) { return null; }
        for (var z = 1; z < _hrZones.size(); z += 1) {
            if (_hrLast < _hrZones[z]) { return z; }
        }
        return _hrZones.size() - 1;
    }

    // Mark a lap in the FIT file. addLap() was never called before, so per-exercise
    // and per-round splits never reached Garmin Connect at all.
    hidden function markLap() {
        if (_rec != null && (_rec has :addLap)) {
            try { _rec.addLap(); } catch (e) {}
        }
    }

    // Seed the editable working set from the prescription. Only the fields the slot
    // actually prescribes become adjustable (a bodyweight lift exposes reps only).
    hidden function seedSetEditor() {
        _editFields = ["reps"];
        _editFieldIdx = 0;
        var ex = currentExercise();
        if (ex == null) {
            _editReps = 0; _editWeight = null; _editRpe = null;
            return;
        }
        var r = ex.reps();
        _editReps = (r != null) ? r : 8;
        _editWeight = ex.weightKg();
        _editRpe = ex.targetRpe();
        if (_editWeight != null) { _editFields.add("weight"); }
        if (_editRpe != null)    { _editFields.add("rpe"); }
    }

    // Adjust the focused field by delta (±1) with a per-field step and clamp.
    function adjustEdit(delta) {
        var f = _editFields[_editFieldIdx];
        if (f.equals("reps")) {
            _editReps = clampNum(_editReps + delta, 0, 100);
        } else if (f.equals("weight")) {
            _editWeight = clampNum(_editWeight + (delta * 2.5), 0, 500);
        } else if (f.equals("rpe")) {
            _editRpe = clampNum(_editRpe + (delta * 0.5), 5.0, 10.0);
        }
    }

    function cycleEditField()  { _editFieldIdx = (_editFieldIdx + 1) % _editFields.size(); }
    function editReps()        { return _editReps; }
    function editWeight()      { return _editWeight; }
    function editRpe()         { return _editRpe; }
    function editFocusField()  { return _editFields[_editFieldIdx]; }
    function editFieldCount()  { return _editFields.size(); }
    function editHasField(id)  { return _editFields.indexOf(id) >= 0; }

    // Log the current set using the edited working values.
    function logCurrentSet() {
        logSet(_editReps, _editWeight, _editRpe);
        _sideReps += 1;
        Haptics.setLogged();
        // Unilateral work alternates automatically: the athlete shouldn't have to
        // press anything extra between sides.
        if (needsSideTracking()) { toggleSide(); }
    }

    hidden function clampNum(v, lo, hi) {
        return (v < lo) ? lo : ((v > hi) ? hi : v);
    }

    // Buzz at the top of each EMOM interval; buzz once when an AMRAP cap is reached.
    hidden function updateIntervalTiming() {
        var ex = currentExercise();
        if (ex == null) { return; }
        var slot = ex.slotType();
        var since = _elapsed - _exStartSec;

        if (slot.equals("emom") && _workSec > 0) {
            _intPhaseLeft -= 1;
            if (_intPhaseLeft > 0) { return; }

            if (_intPhase == PHASE_WORK && _intRestSec > 0) {
                // Work -> rest. Distinct cue: the athlete must stop, not start.
                _intPhase = PHASE_REST;
                _intPhaseLeft = _intRestSec;
                Haptics.intervalRest();
                return;
            }

            // Rest -> work, or a rest-less EMOM rolling to the next minute.
            if (_emomTotal > 0 && _emomRound >= _emomTotal) {
                _intPhaseLeft = 0;
                return;                       // block finished; SELECT advances
            }
            _emomRound += 1;
            _intPhase = PHASE_WORK;
            _intPhaseLeft = _workSec;
            markLap();
            Haptics.intervalWork();

        } else if (slot.equals("amrap") && _capSec > 0) {
            if (since >= _capSec && !_capBuzzed) {
                _capBuzzed = true;
                Haptics.sessionComplete();
            }
        }
    }

    // Static hold countdown, with the same graded end-of-period cue.
    hidden function tickHold() {
        _holdLeft -= 1;
        if (_holdLeft == 3) { Haptics.countTick(); }
        if (_holdLeft <= 0) {
            _holdRunning = false;
            _holdLeft = 0;
            Haptics.restOver();
            logSet(null, currentExercise() != null ? currentExercise().weightKg() : null, null);
            var ex2 = currentExercise();
            var target = (ex2 != null && ex2.sets() != null) ? ex2.sets() : 1;
            if (currentSetCount() >= target) { nextExercise(); } else { startRest(); }
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
    }

    function startRest() {
        var ex = currentExercise();
        var sec = (ex != null && ex.restSeconds() != null)
            ? ex.restSeconds()
            : Config.defaultRestSec(_session.modalityId());
        if (sec == null || sec <= 0) { return; }
        _restRemaining = sec;
        _restTotal = sec;
        _state = RESTING;
    }

    function skipRest() {
        _restRemaining = 0;
        _state = ACTIVE;
    }

    // Advance to the next exercise (or finish).
    function nextExercise() {
        _exIndex += 1;
        // Skip component movements already folded into the AMRAP screen above —
        // they are part of that round, not separate exercises to work through.
        while (_exIndex < _session.exerciseCount() && isFoldedComponent(_exIndex)) {
            _exIndex += 1;
        }
        if (_exIndex >= _session.exerciseCount()) {
            finish();
        } else {
            _state = ACTIVE;
            _driftSec = 0; _pendingDir = 0; _driftDir = 0;   // reset drift latch per exercise
            markLap();
            beginExerciseTiming();
        }
    }

    function finish() {
        // Idempotent: the BACK confirmation, the session menu and AppBase.onStop()
        // can all reach here, and stop()/save() must not run twice.
        if (_state == COMPLETE) { return; }
        if (_timer != null) { _timer.stop(); }
        if (_rec != null) {
            _rec.stop();
            _rec.save();     // writes the FIT to the device activity list
        }
        _state = COMPLETE;
        Haptics.sessionComplete();
        var summary = buildSummary();
        _sync.uploadSession(summary, method(:onUploadDone));
    }

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
