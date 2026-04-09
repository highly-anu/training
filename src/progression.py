"""Calculate load targets per exercise slot."""
from __future__ import annotations
from typing import Optional

# ---------------------------------------------------------------------------
# Starting loads by exercise and training level (kg)
# ---------------------------------------------------------------------------
_STARTING_LOADS: dict[str, dict] = {
    'back_squat':     {'novice': 40,  'intermediate': 70,  'advanced': 100, 'elite': 130},
    'front_squat':    {'novice': 30,  'intermediate': 55,  'advanced': 80,  'elite': 110},
    'deadlift':       {'novice': 50,  'intermediate': 90,  'advanced': 130, 'elite': 170},
    'strict_press':   {'novice': 25,  'intermediate': 40,  'advanced': 60,  'elite': 80},
    'bench_press':    {'novice': 35,  'intermediate': 60,  'advanced': 90,  'elite': 120},
    'power_clean':    {'novice': 30,  'intermediate': 50,  'advanced': 75,  'elite': 100},
    'hang_power_clean': {'novice': 25, 'intermediate': 45, 'advanced': 70,  'elite': 95},
    'romanian_deadlift': {'novice': 40, 'intermediate': 75, 'advanced': 110, 'elite': 140},
    'trap_bar_deadlift': {'novice': 50, 'intermediate': 90, 'advanced': 130, 'elite': 170},
    'sumo_deadlift':     {'novice': 50, 'intermediate': 90,  'advanced': 130, 'elite': 170},
    'floor_press':       {'novice': 35, 'intermediate': 50,  'advanced': 75,  'elite': 100},
}

# Linear increment per session (kg)
_LINEAR_INCREMENTS: dict[str, float] = {
    'back_squat':     2.5,
    'front_squat':    2.5,
    'deadlift':       5.0,
    'romanian_deadlift': 2.5,
    'trap_bar_deadlift': 5.0,
    'strict_press':   1.25,
    'bench_press':    2.5,
    'power_clean':    2.5,
    'hang_power_clean': 2.5,
    'floor_press':    2.5,
    '_default':       2.5,
}

# Sessions/week that drive load progression for each exercise (approx)
_SESSIONS_PER_WEEK: dict[str, int] = {
    'back_squat': 3,
    'front_squat': 2,
    'deadlift': 1,
    'strict_press': 2,
    'bench_press': 2,
    'power_clean': 2,
    '_default': 2,
}

# RPE → load factor relative to a "comfortable working weight" baseline (RPE 8)
# Used to suggest a starting weight when exercise has starting_load_kg data
_RPE_LOAD_FACTOR: dict[int, float] = {
    10: 1.09,   # 0 RIR — maximal
    9:  1.05,   # 1 RIR
    8:  1.00,   # 2 RIR — standard working set
    7:  0.95,   # 3 RIR
    6:  0.90,   # 4 RIR — deload / technique
}


def _round_kg(kg: float, step: float = 2.5) -> float:
    return round(kg / step) * step


# ---------------------------------------------------------------------------
# Progression model implementations
# ---------------------------------------------------------------------------

def _linear_load(exercise: dict, slot: dict, week: int,
                 level: str, is_deload: bool) -> dict:
    ex_id = exercise.get('id', '')
    start = (
        exercise.get('starting_load_kg', {}).get(level)
        or _STARTING_LOADS.get(ex_id, {}).get(level)
    )
    increment = (
        exercise.get('weekly_increment_kg')
        or _LINEAR_INCREMENTS.get(ex_id, _LINEAR_INCREMENTS['_default'])
    )
    sessions_pw = _SESSIONS_PER_WEEK.get(ex_id, _SESSIONS_PER_WEEK['_default'])

    sets = slot.get('sets', 3)
    reps = slot.get('reps', 5)

    if start is None:
        # No predefined starting load — note depends on whether exercise takes external load
        if exercise.get('category') in ('bodyweight', 'mobility', 'skill'):
            note = 'Scale reps to ability.'
        else:
            note = 'Add weight each session. Record your working weight.'
        return {'sets': sets, 'reps': reps, 'load_note': note}

    total_sessions = (week - 1) * sessions_pw
    weight = start + total_sessions * increment

    if is_deload:
        deload_sc = slot.get('scaling', {}) if isinstance(slot.get('scaling'), dict) else {}
        intensity_pct = deload_sc.get('intensity_pct', 0.9)
        vol_mult = deload_sc.get('volume_multiplier', 0.6)
        weight = _round_kg(weight * intensity_pct)
        sets = max(1, round(sets * vol_mult))
        load_note = 'Deload — reduced intensity'
    elif week == 1:
        load_note = 'Establish baseline load'
    else:
        inc_str = f'{increment:g}kg'
        load_note = f'+{inc_str} from last session'

    return {'sets': sets, 'reps': reps, 'weight_kg': _round_kg(weight), 'load_note': load_note}


def _rpe_autoregulation(exercise: dict, slot: dict, level: str, is_deload: bool) -> dict:
    sets = slot.get('sets', 3)
    reps = slot.get('reps', 5)
    target_rpe = 6 if is_deload else int(slot.get('rpe_target', 8))
    rir = 10 - target_rpe  # reps in reserve

    base_load = (
        exercise.get('starting_load_kg', {}).get(level)
        or _STARTING_LOADS.get(exercise.get('id', ''), {}).get(level)
    )

    result: dict = {
        'sets': sets,
        'reps': reps,
        'target_rpe': target_rpe,
        'rir': rir,
    }

    if base_load is not None:
        factor = _RPE_LOAD_FACTOR.get(target_rpe, 1.00)
        result['suggested_weight_kg'] = _round_kg(base_load * factor)
        result['load_note'] = (
            f'RPE {target_rpe} ({rir} RIR) — '
            f'start near {result["suggested_weight_kg"]}kg, adjust by feel'
        )
    else:
        result['load_note'] = (
            f'RPE {target_rpe} ({rir} reps in reserve) — self-regulate load to feel'
        )

    return result


def _time_to_task(slot: dict, week: int, phase: str, is_deload: bool,
                  max_minutes: int | None = None) -> dict:
    base_sec = slot.get('duration_sec', 5400)  # default 90 min

    phase_targets = {
        'base':        base_sec,
        'build':       int(base_sec * 1.25),
        'peak':        int(base_sec * 1.40),
        'taper':       int(base_sec * 0.60),
        'deload':      int(base_sec * 0.60),
        'maintenance': base_sec,
    }
    target_sec = phase_targets.get(phase, base_sec)

    # 10% weekly ramp up to target
    current_sec = min(base_sec * (1 + (week - 1) * 0.10), target_sec)
    if is_deload:
        current_sec *= 0.60

    minutes = max(1, round(current_sec / 60))
    # Never exceed the athlete's session time limit
    if max_minutes is not None:
        minutes = min(minutes, max_minutes)
    intensity = slot.get('intensity', 'zone2')
    zone_label = 'Zone 1–2 (conversational pace)' if intensity == 'zone2' else intensity
    return {'duration_minutes': minutes, 'zone_target': zone_label}


def _distance_slot(slot: dict, week: int, level: str, phase: str, is_deload: bool) -> dict:
    base_m = slot.get('distance_m', 8000)
    intensity = slot.get('intensity', 'zone2')

    # Short fixed per-set distances (e.g. 40m carry sets) — no scaling
    if base_m < 500:
        return {'distance_m': base_m, 'intensity': intensity}

    level_mult = {'novice': 0.5, 'intermediate': 0.75, 'advanced': 1.0, 'elite': 1.25}
    phase_mult = {'base': 1.0, 'build': 1.25, 'peak': 1.40, 'taper': 0.60, 'deload': 0.60}

    distance_m = (base_m
                  * level_mult.get(level, 0.75)
                  * phase_mult.get(phase, 1.0)
                  * (1 + (week - 1) * 0.08))

    if is_deload:
        distance_m *= 0.60

    return {'distance_km': round(distance_m / 1000, 1), 'intensity': intensity}


def _density_slot(slot: dict, week: int, is_deload: bool) -> dict:
    duration_sec = slot.get('duration_sec', slot.get('time_cap_sec', 1200))
    base_rounds = max(1, round(duration_sec / 180))
    rounds = base_rounds + max(0, week - 1)

    if is_deload:
        rounds = max(1, round(rounds * 0.70))
        duration_sec = round(duration_sec * 0.75)

    slot_type = slot.get('slot_type', 'amrap').upper()
    return {
        'time_minutes': max(5, round(duration_sec / 60)),
        'target_rounds': rounds,
        'format': slot_type,
    }


def _skill_slot(slot: dict) -> dict:
    minutes = slot.get('duration_minutes', 15)
    return {'duration_minutes': minutes, 'focus': 'movement quality over quantity'}


# ---------------------------------------------------------------------------
# Public dispatcher
# ---------------------------------------------------------------------------

def calculate_load(
    exercise: dict,
    slot: dict,
    progression_model: str,
    week_number: int,
    phase: str,
    training_level: str,
    is_deload: bool,
    session_time_minutes: int | None = None,
) -> dict:
    """Calculate the load prescription for one exercise in one slot."""
    slot_type = slot.get('slot_type', 'sets_reps')

    if slot_type == 'sets_reps':
        if progression_model in ('linear_load', 'volume_block', 'density'):
            return _linear_load(exercise, slot, week_number, training_level, is_deload)
        elif progression_model == 'rpe_autoregulation':
            return _rpe_autoregulation(exercise, slot, training_level, is_deload)
        else:
            sets = slot.get('sets', 3)
            reps = slot.get('reps', 5)
            return {'sets': sets, 'reps': reps}

    elif slot_type == 'time_domain':
        return _time_to_task(slot, week_number, phase, is_deload, session_time_minutes)

    elif slot_type == 'distance':
        return _distance_slot(slot, week_number, training_level, phase, is_deload)

    elif slot_type in ('amrap', 'emom'):
        return _density_slot(slot, week_number, is_deload)

    elif slot_type == 'amrap_movement':
        # Component movement within an AMRAP — show reps per round only
        return {'reps_per_round': slot.get('reps_per_round', 10)}

    elif slot_type == 'for_time':
        if 'distance_m' in slot:
            return _distance_slot(slot, week_number, training_level, phase, is_deload)
        return _density_slot(slot, week_number, is_deload)

    elif slot_type == 'skill_practice':
        return _skill_slot(slot)

    elif slot_type == 'static_hold':
        duration = slot.get('hold_seconds', 30)
        sets = slot.get('sets', 3)
        return {'sets': sets, 'hold_seconds': duration}

    else:
        return {'sets': slot.get('sets', 3), 'reps': slot.get('reps', 5)}
