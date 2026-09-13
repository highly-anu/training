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
            // Colour + arrow the HR readout when live HR drifts out of the
            // prescribed zone: red ▲ = ease off, blue ▼ = push harder.
            var drift = _ctl.driftDirection();
            var hrColor = Gfx.COLOR_LT_GRAY;
            var prefix = "";
            if (drift > 0) { hrColor = Gfx.COLOR_RED; prefix = "▲"; }
            else if (drift < 0) { hrColor = Gfx.COLOR_BLUE; prefix = "▼"; }
            dc.setColor(hrColor, Gfx.COLOR_TRANSPARENT);
            dc.drawText(dc.getWidth() - 10, 12, Gfx.FONT_XTINY, prefix + hr + "♥",
                Gfx.TEXT_JUSTIFY_RIGHT);
        }

        // Body by slot type.
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        var cy = dc.getHeight() / 2;
        dc.drawText(cx, cy - 45, Gfx.FONT_SMALL, ex.name(), Gfx.TEXT_JUSTIFY_CENTER);

        var slot = ex.slotType();
        if (slot.equals("sets_reps")) {
            drawSetEditor(dc, cx, cy, ex);
        } else if (slot.equals("static_hold")) {
            var target = (ex.sets() != null) ? ex.sets() : 1;
            dc.drawText(cx, cy - 5, Gfx.FONT_NUMBER_MEDIUM,
                _ctl.currentSetCount() + "/" + target, Gfx.TEXT_JUSTIFY_CENTER);
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + 35, Gfx.FONT_TINY, ex.loadDescription(), Gfx.TEXT_JUSTIFY_CENTER);
        } else if (slot.equals("emom")) {
            // Countdown to the next interval + round progress.
            dc.drawText(cx, cy - 5, Gfx.FONT_NUMBER_MEDIUM, mmss(_ctl.emomSecToNext()),
                Gfx.TEXT_JUSTIFY_CENTER);
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            var et = _ctl.emomTotal();
            var rlabel = "Rd " + _ctl.emomRound() + ((et > 0) ? "/" + et : "");
            dc.drawText(cx, cy + 35, Gfx.FONT_TINY, rlabel, Gfx.TEXT_JUSTIFY_CENTER);
        } else if (slot.equals("amrap")) {
            // Time-cap countdown + rounds logged (press SELECT per round).
            dc.drawText(cx, cy - 5, Gfx.FONT_NUMBER_MEDIUM, mmss(_ctl.exerciseRemainingSec()),
                Gfx.TEXT_JUSTIFY_CENTER);
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + 35, Gfx.FONT_TINY, "Rounds: " + _ctl.amrapRounds(),
                Gfx.TEXT_JUSTIFY_CENTER);
        } else if (slot.equals("for_time")) {
            // Elapsed clock + rounds done toward the target (press SELECT per round).
            dc.drawText(cx, cy - 5, Gfx.FONT_NUMBER_MEDIUM, mmss(_ctl.exerciseElapsedSec()),
                Gfx.TEXT_JUSTIFY_CENTER);
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            var tr = ex.targetRounds();
            dc.drawText(cx, cy + 35, Gfx.FONT_TINY,
                "Rounds: " + _ctl.amrapRounds() + ((tr != null) ? "/" + tr : ""),
                Gfx.TEXT_JUSTIFY_CENTER);
        } else if (slot.equals("time_domain") || slot.equals("skill_practice")
                   || slot.equals("distance")) {
            // Elapsed clock for timed / skill / distance work.
            dc.drawText(cx, cy - 5, Gfx.FONT_NUMBER_MEDIUM, mmss(_ctl.exerciseElapsedSec()),
                Gfx.TEXT_JUSTIFY_CENTER);
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + 35, Gfx.FONT_TINY, ex.loadDescription(), Gfx.TEXT_JUSTIFY_CENTER);
        } else {
            dc.drawText(cx, cy - 5, Gfx.FONT_TINY, ex.loadDescription(), Gfx.TEXT_JUSTIFY_CENTER);
        }
    }

    // Editable working set: reps (big) + the prescribed load (weight or RPE), with
    // the focused field highlighted. SELECT logs it; UP/DOWN adjust; BACK cycles field.
    hidden function drawSetEditor(dc, cx, cy, ex) {
        var target = (ex.sets() != null) ? ex.sets() : 1;
        var focus = _ctl.editFocusField();

        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 46, Gfx.FONT_TINY,
            "Set " + (_ctl.currentSetCount() + 1) + "/" + target, Gfx.TEXT_JUSTIFY_CENTER);

        dc.setColor(focus.equals("reps") ? Gfx.COLOR_YELLOW : Gfx.COLOR_WHITE,
            Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 22, Gfx.FONT_NUMBER_MEDIUM, _ctl.editReps() + " reps",
            Gfx.TEXT_JUSTIFY_CENTER);

        if (_ctl.editHasField("weight")) {
            dc.setColor(focus.equals("weight") ? Gfx.COLOR_YELLOW : Gfx.COLOR_LT_GRAY,
                Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + 30, Gfx.FONT_SMALL,
                _ctl.editWeight().toFloat().format("%.1f") + " kg", Gfx.TEXT_JUSTIFY_CENTER);
        } else if (_ctl.editHasField("rpe")) {
            dc.setColor(focus.equals("rpe") ? Gfx.COLOR_YELLOW : Gfx.COLOR_LT_GRAY,
                Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + 30, Gfx.FONT_SMALL,
                "RPE " + _ctl.editRpe().toFloat().format("%.1f"), Gfx.TEXT_JUSTIFY_CENTER);
        }

        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        var hint = (_ctl.editFieldCount() > 1) ? "▲▼ adjust · ← field" : "▲▼ reps";
        dc.drawText(cx, cy + 56, Gfx.FONT_XTINY, hint, Gfx.TEXT_JUSTIFY_CENTER);
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
            // sets_reps logs the on-wrist edited values; static_hold logs as prescribed.
            if (slot.equals("sets_reps")) {
                _ctl.logCurrentSet();
            } else {
                _ctl.logSet(ex.reps(), ex.weightKg(), ex.targetRpe());
            }
            var target = (ex.sets() != null) ? ex.sets() : 1;
            if (_ctl.currentSetCount() >= target) {
                _ctl.nextExercise();
            } else {
                _ctl.startRest();
            }
        } else if (slot.equals("amrap") || slot.equals("for_time")) {
            // SELECT counts a round; swipe/next-page advances to the next exercise.
            _ctl.logRound();
        } else {
            _ctl.nextExercise();
        }
        maybeComplete();
        return true;
    }

    // While editing a sets_reps set: UP/DOWN adjust the focused field. Otherwise
    // DOWN advances to the next exercise (manual navigation); UP is a no-op.
    function onNextPage() {
        if (isEditing()) { _ctl.adjustEdit(-1); Ui.requestUpdate(); return true; }
        _ctl.nextExercise(); maybeComplete(); return true;
    }

    function onPreviousPage() {
        if (isEditing()) { _ctl.adjustEdit(1); Ui.requestUpdate(); return true; }
        return false;
    }

    // BACK cycles the focused edit field while editing; otherwise leaves it to the
    // system (exit the workout view).
    function onBack() {
        if (isEditing() && _ctl.editFieldCount() > 1) {
            _ctl.cycleEditField(); Ui.requestUpdate(); return true;
        }
        return false;
    }

    // MENU (hold-UP) ends the session early (saves what's been done).
    function onMenu() {
        _ctl.finish();
        maybeComplete();
        return true;
    }

    // True when an editable sets_reps set is active (not resting).
    hidden function isEditing() {
        if (_ctl.state() != WorkoutController.ACTIVE) { return false; }
        var ex = _ctl.currentExercise();
        return ex != null && ex.slotType().equals("sets_reps");
    }

    hidden function maybeComplete() {
        if (_ctl.state() == WorkoutController.COMPLETE) {
            Ui.switchToView(new SessionCompleteView(), new SessionCompleteDelegate(), Ui.SLIDE_UP);
        }
    }
}
