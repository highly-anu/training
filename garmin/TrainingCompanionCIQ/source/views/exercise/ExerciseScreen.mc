using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Lang;

// ONE persistent view for the whole workout.
//
// Exercise-to-exercise navigation swaps the renderer and kicks a transition
// tween rather than pushing a new View: the heap stays flat for the whole
// session, the animation clock and prefetched icons survive, and the outer ring
// can morph continuously while only the body slides. A system SLIDE_LEFT would
// slide the ring too, which breaks the instrument metaphor.
//
// Three pages in a loop — Exercise, Progress, Metrics — driven by swipe so the
// UP/DOWN buttons stay free for editing the working set.
class ExerciseScreen extends Ui.View {

    const PAGE_MAIN = 0;
    const PAGE_PROGRESS = 1;
    const PAGE_METRICS = 2;
    const PAGE_COUNT = 3;

    hidden var _ctl;
    hidden var _g;
    hidden var _page;
    hidden var _renderer;
    hidden var _slotKey;       // slotType the current renderer was built for
    hidden var _lastIndex;
    hidden var _iconId;

    function initialize(ctl) {
        View.initialize();
        _ctl = ctl;
        _page = PAGE_MAIN;
        _lastIndex = -1;
        _slotKey = null;
    }

    function onLayout(dc) {
        // Built ONCE. Every coordinate downstream is a fraction of this.
        _g = new Grid(dc);
        Text.init(_g);
        Anim.init();
        // Long sessions and low battery drop to static rendering. The corpus
        // includes a 360-minute long_mountain_day; 25 Hz tweens all day is not a
        // trade worth making.
        Anim.applySessionBudget(_ctl.session().estimatedMinutes());
        if (ArchetypeBehavior.isLongHaul(_ctl.archetypeId())) {
            Anim.applySessionBudget(999);
        }
        bindRenderer();
    }

    function onShow()  { bindRenderer(); }
    function onHide()  { Anim.stopAll(); Icons.release(); }

    function page()     { return _page; }
    function setPage(p) {
        _page = ((p % PAGE_COUNT) + PAGE_COUNT) % PAGE_COUNT;
        Ui.requestUpdate();
    }

    function renderer() { return _renderer; }

    // Pick the renderer for the current slot type, and prefetch its icon.
    //
    // Resources are loaded HERE, never in onUpdate — "loading a resource can be
    // an expensive operation, so do not load resources when handling screen
    // updates."
    function bindRenderer() {
        var ex = _ctl.currentExercise();
        var slot = (ex != null) ? ex.slotType() : "";
        var archetypeRound = ArchetypeBehavior.isRoundTimer(_ctl.archetypeId());
        var key = archetypeRound ? "__round" : slot;

        if (_slotKey == null || !_slotKey.equals(key)) {
            _renderer = build(key, slot);
            _slotKey = key;
        }

        if (_lastIndex != _ctl.exerciseIndex()) {
            _lastIndex = _ctl.exerciseIndex();
            _iconId = Icons.forExercise(ex);
            Icons.prefetch(_iconId);
            // Ring sweeps to the new position; body slides in behind it.
            Anim.start(Anim.SLOT_RING, 0.0, 1.0, 450, Anim.EASE_OUT, null);
            Anim.start(Anim.SLOT_TRANSITION, 1.0, 0.0, 320, Anim.EASE_IN_OUT, null);
        }
    }

    hidden function build(key, slot) {
        if (key.equals("__round"))        { return new RoundTimerRenderer(); }
        if (slot.equals("sets_reps"))     { return new SetsRepsRenderer(); }
        if (slot.equals("emom"))          { return new EmomRenderer(); }
        if (slot.equals("amrap"))         { return new AmrapRenderer(); }
        if (slot.equals("amrap_movement")){ return new AmrapRenderer(); }
        if (slot.equals("for_time"))      { return new ForTimeRenderer(); }
        if (slot.equals("distance"))      { return new DistanceRenderer(); }
        if (slot.equals("static_hold"))   { return new StaticHoldRenderer(); }
        // time_domain and skill_practice share a screen: both are "hold this
        // block for this long", differing only in what the sub-line says.
        return new TimeDomainRenderer();
    }

    function onUpdate(dc) {
        dc.setColor(Theme.TEXT, Theme.BG);
        dc.clear();
        if (dc has :setAntiAlias) { dc.setAntiAlias(true); }

        if (_g == null) { _g = new Grid(dc); Text.init(_g); }

        var accent = Theme.accent(_ctl.modality());
        var ex = _ctl.currentExercise();

        if (_ctl.state() == WorkoutController.RESTING) {
            drawScreen(dc, accent, new RestRenderer(), ex, true);
            return;
        }

        if (_page == PAGE_PROGRESS) { drawProgress(dc, accent); return; }
        if (_page == PAGE_METRICS)  { drawMetrics(dc, accent);  return; }

        if (ex == null) {
            dc.setColor(Theme.TEXT_DIM, Gfx.COLOR_TRANSPARENT);
            dc.drawText(_g.cx, _g.cy, Text.label(), "No exercises",
                        Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
            Chrome.drawHint(dc, _g, "hold UP to finish");
            return;
        }

        drawScreen(dc, accent, _renderer, ex, false);
    }

    // The shared frame: outer ring, inner ring, crown, icon, name, core, base, hint.
    hidden function drawScreen(dc, accent, r, ex, isRest) {
        var g = _g;

        // Outer ring — where am I in the SESSION.
        var sweep = Anim.settled(Anim.SLOT_RING) ? 1.0 : Anim.value(Anim.SLOT_RING);
        Ring.drawProgress(dc, g.cx, g.cy, g.ringR, g.ringPen,
                          Theme.dimmed(accent, 22), accent,
                          _ctl.sessionProgress() * sweep, true);

        // Inner ring — where am I in THIS thing.
        var segs = r.innerSegments(_ctl, ex);
        if (segs != null && segs > 0) {
            Ring.drawSegments(dc, g.cx, g.cy, g.ringRInner, g.ringPenInner,
                              segs, r.innerFilled(_ctl, ex),
                              Theme.dimmed(accent, 26), accent);
        } else {
            var p = r.innerProgress(_ctl, ex);
            if (p != null) {
                Ring.drawProgress(dc, g.cx, g.cy, g.ringRInner, g.ringPenInner,
                                  Theme.dimmed(accent, 26), accent, p, true);
            }
        }

        Chrome.drawCrown(dc, g, accent,
                         _ctl.exerciseIndex(), _ctl.exerciseTotal(),
                         isRest ? null : Chrome.roleLabel(ex != null ? ex.slotRole() : null),
                         _ctl.currentHR(), _ctl.currentZone(), _ctl.driftDirection());

        // Exercise name, fitted rather than clipped. Archetype and exercise names
        // in this corpus run long enough to overflow a round screen twice over.
        if (!isRest && ex != null) {
            var ny = g.yCrown + (g.h * 105 / 1000);
            var chord = g.chordWidth(ny);
            var left  = g.cx - (chord / 2);
            var gap   = g.iconChip / 3;
            // The icon sits at the left of the chord and the NAME is centred in
            // what remains to its right. Centring the name on cx instead let a
            // long name's left edge run straight under the icon.
            Icons.drawCentered(dc, left + (g.iconChip / 2), ny, g.iconChip,
                               _iconId, Theme.dimmed(accent, 85));
            var tLeft  = left + g.iconChip + gap;
            var tRight = g.cx + (chord / 2);
            Text.drawFitted(dc, (tLeft + tRight) / 2, ny, tRight - tLeft,
                            ex.name(), Theme.TEXT, (g.w * 58) / 1000,
                            ["RobotoCondensedBold", "RobotoMedium"]);
        }

        Chrome.drawCore(dc, g, r.core(_ctl, ex),
                        isRest ? Theme.TEXT : accent, r.coreWide(_ctl, ex));
        Chrome.drawSub(dc, g, r.sub(_ctl, ex), Theme.TEXT_DIM);
        r.drawBase(dc, g, accent, _ctl, ex);
        Chrome.drawHint(dc, g, r.hint(_ctl, ex));
        if (!isRest) { Chrome.drawPageDots(dc, g, _page, PAGE_COUNT); }
    }

    // Page 2 — every exercise, with what's done.
    hidden function drawProgress(dc, accent) {
        var g = _g;
        Ring.drawProgress(dc, g.cx, g.cy, g.ringR, g.ringPen,
                          Theme.dimmed(accent, 22), accent, _ctl.sessionProgress(), true);
        dc.setColor(Theme.TEXT_DIM, Gfx.COLOR_TRANSPARENT);
        dc.drawText(g.cx, g.yCrown, Text.hint(), "SESSION",
                    Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);

        var list = _ctl.session().exercises();
        var cur = _ctl.exerciseIndex();
        var step = g.h * 78 / 1000;
        // Window of five around the current exercise.
        var first = cur - 2;
        if (first < 0) { first = 0; }
        var last = first + 5;
        if (last > list.size()) { last = list.size(); first = (last - 5 < 0) ? 0 : last - 5; }
        var y = g.cy - (((last - first - 1) * step) / 2);
        for (var i = first; i < last; i += 1) {
            var done = (i < cur);
            var isCur = (i == cur);
            var col = isCur ? Theme.TEXT : (done ? Theme.dimmed(accent, 70) : Theme.TEXT_HINT);
            if (done) {
                Icons.draw(dc, g.cx - (g.chordWidth(y) / 2) + (g.iconChip / 2),
                           y - (g.iconChip / 2), Rez.Drawables.IcUiCheck, col);
            }
            Text.drawFitted(dc, g.cx, y, g.chordWidth(y) - g.iconChip * 2,
                            list[i].name(), col, (g.w * 50) / 1000,
                            ["RobotoCondensedBold", "RobotoMedium"]);
            y += step;
        }
        Chrome.drawPageDots(dc, g, _page, PAGE_COUNT);
        Chrome.drawHint(dc, g, "swipe to return");
    }

    // Page 3 — live metrics.
    hidden function drawMetrics(dc, accent) {
        var g = _g;
        var zone = _ctl.currentZone();
        var zc = Theme.zoneColor(zone);
        var hr = _ctl.currentHR();

        // The HR ring is coloured by the zone the athlete is ACTUALLY in, and
        // filled by position within it — the whole point of a metrics page.
        Ring.drawProgress(dc, g.cx, g.cy, g.ringR, g.ringPen,
                          Theme.dimmed(zc, 22), zc,
                          (zone != null) ? (zone.toFloat() / 5.0) : 0.0, true);

        dc.setColor(Theme.TEXT_DIM, Gfx.COLOR_TRANSPARENT);
        dc.drawText(g.cx, g.yCrown, Text.hint(), "LIVE",
                    Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);

        Chrome.drawCore(dc, g, (hr != null) ? hr.toString() : "--", zc, false);
        Chrome.drawSub(dc, g, (zone != null) ? ("ZONE " + zone.toString()) : "bpm",
                       Theme.TEXT_DIM);

        var line = Text.mmss(_ctl.elapsedSec());
        if (_ctl.distanceKm() > 0.05) { line += "   " + Text.kg(_ctl.distanceKm()) + " km"; }
        dc.setColor(Theme.TEXT_DIM, Gfx.COLOR_TRANSPARENT);
        dc.drawText(g.cx, g.yBase, Text.label(), line,
                    Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);

        Chrome.drawPageDots(dc, g, _page, PAGE_COUNT);
        Chrome.drawHint(dc, g, "swipe to return");
    }
}
