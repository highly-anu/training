using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Lang;

// Renders the current exercise, dispatching layout by slotType, plus a rest
// overlay and live HR. Mirrors the iOS ExerciseViews/* set + the rest timer.
//
// NOTE: kept as a single dispatching view for the scaffold. Split into
// SetsRepsView / TimeDomainView / EMOMView / AMRAPView / etc. as they grow.
class ExerciseView extends Ui.View {

    hidden var _ctl;   // WorkoutController

    function initialize(ctl) {
        View.initialize();
        _ctl = ctl;
    }

    function onUpdate(dc) {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var cx = dc.getWidth() / 2;

        if (_ctl.state() == WorkoutController.RESTING) {
            drawRest(dc, cx);
            return;
        }

        var ex = _ctl.currentExercise();
        if (ex == null) { return; }

        // Header: progress + HR.
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, 12, Gfx.FONT_XTINY,
            (_ctl.exerciseIndex() + 1) + "/" + _ctl.exerciseTotal(),
            Gfx.TEXT_JUSTIFY_CENTER);
        var hr = _ctl.currentHR();
        if (hr != null) {
            dc.drawText(dc.getWidth() - 10, 12, Gfx.FONT_XTINY, hr + "♥",
                Gfx.TEXT_JUSTIFY_RIGHT);
        }

        // Body by slot type.
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        var cy = dc.getHeight() / 2;
        dc.drawText(cx, cy - 45, Gfx.FONT_SMALL, ex.name(), Gfx.TEXT_JUSTIFY_CENTER);

        var slot = ex.slotType();
        if (slot.equals("sets_reps") || slot.equals("static_hold")) {
            var target = (ex.sets() != null) ? ex.sets() : 1;
            dc.drawText(cx, cy - 5, Gfx.FONT_NUMBER_MEDIUM,
                _ctl.currentSetCount() + "/" + target, Gfx.TEXT_JUSTIFY_CENTER);
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + 35, Gfx.FONT_TINY, ex.loadDescription(), Gfx.TEXT_JUSTIFY_CENTER);
        } else if (slot.equals("time_domain") || slot.equals("skill_practice")
                   || slot.equals("amrap") || slot.equals("emom")
                   || slot.equals("for_time") || slot.equals("distance")) {
            // Elapsed clock for timed / interval / distance work.
            dc.drawText(cx, cy - 5, Gfx.FONT_NUMBER_MEDIUM, mmss(_ctl.elapsedSec()),
                Gfx.TEXT_JUSTIFY_CENTER);
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + 35, Gfx.FONT_TINY, ex.loadDescription(), Gfx.TEXT_JUSTIFY_CENTER);
            // TODO: EMOM per-minute cue + AMRAP round counter + Zone-drift HR alert
            //       (compare _ctl.currentHR() to ex.zoneLower()/zoneUpper()).
        } else {
            dc.drawText(cx, cy - 5, Gfx.FONT_TINY, ex.loadDescription(), Gfx.TEXT_JUSTIFY_CENTER);
        }
    }

    hidden function drawRest(dc, cx) {
        var cy = dc.getHeight() / 2;
        dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 40, Gfx.FONT_SMALL, Ui.loadResource(Rez.Strings.Rest),
            Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy, Gfx.FONT_NUMBER_HOT, mmss(_ctl.restRemaining()),
            Gfx.TEXT_JUSTIFY_CENTER);
    }

    hidden function mmss(sec) {
        if (sec == null) { sec = 0; }
        var m = sec / 60;
        var s = sec % 60;
        return m.format("%d") + ":" + s.format("%02d");
    }
}

class ExerciseDelegate extends Ui.BehaviorDelegate {
    hidden var _ctl;
    hidden var _view;

    function initialize(ctl, view) {
        BehaviorDelegate.initialize();
        _ctl = ctl;
        _view = view;
    }

    // SELECT: skip rest, log a set, or complete a timed exercise.
    function onSelect() {
        if (_ctl.state() == WorkoutController.RESTING) {
            _ctl.skipRest();
            return true;
        }
        var ex = _ctl.currentExercise();
        if (ex == null) { return true; }
        var slot = ex.slotType();
        if (slot.equals("sets_reps") || slot.equals("static_hold")) {
            _ctl.logSet(ex.reps(), ex.weightKg(), ex.targetRpe());
            var target = (ex.sets() != null) ? ex.sets() : 1;
            if (_ctl.currentSetCount() >= target) {
                _ctl.nextExercise();
            } else {
                _ctl.startRest();
            }
        } else {
            _ctl.nextExercise();
        }
        maybeComplete();
        return true;
    }

    // Manual navigation between exercises.
    function onNextPage() { _ctl.nextExercise(); maybeComplete(); return true; }

    // MENU ends the session early (saves what's been done).
    function onMenu() {
        _ctl.finish();
        maybeComplete();
        return true;
    }

    hidden function maybeComplete() {
        if (_ctl.state() == WorkoutController.COMPLETE) {
            Ui.switchToView(new SessionCompleteView(), new SessionCompleteDelegate(), Ui.SLIDE_UP);
        }
    }
}
