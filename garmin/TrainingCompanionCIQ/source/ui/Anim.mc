using Toybox.Timer;
using Toybox.System;
using Toybox.WatchUi;
using Toybox.Math;
using Toybox.Application;

// Procedural tween engine — ONE timer, fixed slots, self-stopping.
//
// Why not WatchUi.animate(): it drives a single scalar per call, so it cannot
// interpolate a packed RGB integer (the HR-zone crossfade needs exactly that);
// it offers four easing curves and no stagger; cancelAllAnimations() is GLOBAL
// with no per-tween cancel, which is untenable when every exercise change has to
// cancel exactly one tween; and its frame rate is unspecified and unstoppable,
// which is a battery problem on a 6-hour session.
//
// Why not Monkey Motion (.mmm): AnimationLayer has no :tintColor, so twelve
// modality accents would mean twelve baked copies of every animation; and
// AnimationLayer.getDc() "will always return null", so live timer text cannot be
// composited over it. Every animated screen here needs live numbers.
//
// Battery discipline: the timer runs ONLY while a tween is live and stops itself
// the moment none is. Steady state is the existing 1 Hz controller tick.
module Anim {

    // 50ms / 20fps. 40ms was rejected by the device: "Timer interval is too
    // small. It has been set to the minimum supported value." 50ms is the floor.
    const FRAME_MS  = 50;
    const MAX_SLOTS = 4;

    enum { SLOT_RING, SLOT_TRANSITION, SLOT_PULSE, SLOT_COLOR }
    enum { EASE_LINEAR, EASE_OUT, EASE_IN_OUT, EASE_BACK }

    // method(:onTick) needs a receiver object, and a module has no `self` —
    // so the timer callback lives on a one-instance helper that forwards back in.
    class Ticker {
        function initialize() {}
        function onTick() as Void { Anim.onTick(); }
    }

    var _timer;
    var _ticker;
    // Parallel fixed arrays allocated once — no per-tween allocation, no GC churn.
    var _t0    = new [MAX_SLOTS];
    var _dur   = new [MAX_SLOTS];
    var _from  = new [MAX_SLOTS];
    var _to    = new [MAX_SLOTS];
    var _ease  = new [MAX_SLOTS];
    var _val   = new [MAX_SLOTS];
    var _cb    = new [MAX_SLOTS];
    var _reduce = false;

    var _inited = false;

    // Idempotent, and called lazily from start()/onTick() rather than relying on
    // every view remembering to call it. `new [MAX_SLOTS]` yields an array of
    // NULLS, so an un-inited slot made onTick evaluate `now - null` and throw
    // UnexpectedTypeException — any view that animated without calling init()
    // first (SessionCompleteView did) crashed on its first frame.
    function init() {
        if (_inited) { return; }
        for (var i = 0; i < MAX_SLOTS; i += 1) {
            _t0[i] = 0; _dur[i] = 0; _from[i] = 0.0; _to[i] = 0.0;
            _ease[i] = EASE_LINEAR; _val[i] = 0.0; _cb[i] = null;
        }
        _inited = true;
        refreshReduceMotion();
    }

    // Motion is suppressed on low battery and by an explicit user setting. In
    // that mode start() jumps straight to the end value, so every screen still
    // renders correctly — just instantly.
    function refreshReduceMotion() {
        var off = false;
        try {
            off = (Application.Properties.getValue("reduceMotion") == true);
        } catch (e) {
            off = false;
        }
        if (!off) {
            var stats = System.getSystemStats();
            if (stats != null && stats.battery != null && stats.battery < 15) {
                off = true;
            }
        }
        _reduce = off;
    }

    // Long sessions opt out of motion entirely — the corpus includes a
    // 360-minute long_mountain_day and a 240-minute scrambling_durability.
    function applySessionBudget(estimatedMinutes) {
        if (estimatedMinutes != null && estimatedMinutes > 90) { _reduce = true; }
    }

    function reduced() { return _reduce; }

    function start(slot, from, to, durMs, ease, cb) {
        init();
        if (_reduce || durMs == null || durMs <= 0) {
            _val[slot] = to;
            if (cb != null) { cb.invoke(); }
            WatchUi.requestUpdate();
            return;
        }
        _t0[slot]   = System.getTimer();
        _dur[slot]  = durMs;
        _from[slot] = from;
        _to[slot]   = to;
        _ease[slot] = ease;
        _val[slot]  = from;
        _cb[slot]   = cb;
        if (_ticker == null) { _ticker = new Ticker(); }
        if (_timer == null)  { _timer = new Timer.Timer(); }
        _timer.start(_ticker.method(:onTick), FRAME_MS, true);
    }

    function value(slot)  { var v = _val[slot]; return (v == null) ? 0.0 : v; }
    function settled(slot) { return _dur[slot] == null || _dur[slot] <= 0; }
    function set(slot, v)  { _val[slot] = v; _dur[slot] = 0; }

    function cancel(slot) { _dur[slot] = 0; _cb[slot] = null; }

    function stopAll() {
        for (var i = 0; i < MAX_SLOTS; i += 1) { _dur[i] = 0; _cb[i] = null; }
        if (_timer != null) { _timer.stop(); }
    }

    function onTick() as Void {
        init();
        var now = System.getTimer();
        var live = 0;
        for (var i = 0; i < MAX_SLOTS; i += 1) {
            if (_dur[i] == null || _dur[i] <= 0) { continue; }
            var e = now - _t0[i];
            // System.getTimer() wraps at 2^31 ms (~24.8 days of uptime). A tween
            // straddling the wrap would otherwise never complete.
            if (e < 0) { e = _dur[i]; }
            if (e >= _dur[i]) {
                _val[i] = _to[i];
                _dur[i] = 0;
                var c = _cb[i];
                _cb[i] = null;
                if (c != null) { c.invoke(); }
            } else {
                var f = apply(_ease[i], e.toFloat() / _dur[i].toFloat());
                _val[i] = _from[i] + ((_to[i] - _from[i]) * f);
                live += 1;
            }
        }
        WatchUi.requestUpdate();
        if (live == 0 && _timer != null) { _timer.stop(); }
    }

    function apply(kind, t) {
        if (kind == EASE_OUT) {
            var u = 1.0 - t;
            return 1.0 - (u * u * u);
        }
        if (kind == EASE_IN_OUT) {
            if (t < 0.5) { return 4.0 * t * t * t; }
            var v = (-2.0 * t) + 2.0;
            return 1.0 - ((v * v * v) / 2.0);
        }
        if (kind == EASE_BACK) {
            // Slight overshoot — the set-dot pop.
            var s = 1.70158;
            var u2 = t - 1.0;
            return (u2 * u2 * (((s + 1.0) * u2) + s)) + 1.0;
        }
        return t;
    }
}
