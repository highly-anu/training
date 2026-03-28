"""Flask REST API — bridges the frontend to the Python training engine."""
from __future__ import annotations

import glob
import os
import sys
from datetime import date as _date

import yaml
from flask import Flask, jsonify, request
from flask_cors import CORS

# Ensure src/ is importable when running from repo root
sys.path.insert(0, os.path.dirname(__file__))

from src import loader
from src.generator import generate
from src.phase_calendar import compute_phase_from_date
from src.validator import validate

app = Flask(__name__)
app.json.sort_keys = False   # preserve insertion order (days Mon→Sun)
CORS(app, resources={r"/api/*": {"origins": "*"}})

_DAY_NAMES = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
_DATA_DIR = os.path.join(os.path.dirname(__file__), 'data')


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _load_yaml(path: str) -> dict:
    with open(path, encoding='utf-8') as f:
        return yaml.safe_load(f)


def _all_goals() -> list[dict]:
    goals = []
    for path in sorted(glob.glob(os.path.join(_DATA_DIR, 'goals', '*.yaml'))):
        goals.append(_load_yaml(path))
    return goals


def _all_exercises() -> list[dict]:
    result = []
    for path in sorted(glob.glob(os.path.join(_DATA_DIR, 'exercises', '*.yaml'))):
        data = _load_yaml(path)
        for ex in data.get('exercises', []):
            # Ensure sources is always a list
            if isinstance(ex.get('sources'), str):
                ex['sources'] = [ex['sources']]
            result.append(ex)
    return result


def _all_modalities() -> list[dict]:
    result = []
    for path in sorted(glob.glob(os.path.join(_DATA_DIR, 'modalities', '*.yaml'))):
        result.append(_load_yaml(path))
    return result


def _equipment_profiles() -> list[dict]:
    raw = _load_yaml(os.path.join(_DATA_DIR, 'constraints', 'equipment_profiles.yaml'))
    return raw.get('equipment_profiles', [])


def _injury_flags() -> list[dict]:
    raw = _load_yaml(os.path.join(_DATA_DIR, 'constraints', 'injury_flags.yaml'))
    return raw.get('injury_flags', [])


_BENCHMARK_CATEGORY_MAP = {
    'max_strength':       'strength',
    'power':              'strength',
    'relative_strength':  'strength',
    'strength_endurance': 'conditioning',
    'aerobic_base':       'conditioning',
    'anaerobic_intervals': 'conditioning',
}
_BENCHMARK_UNIT_MAP = {
    'bw_ratio':     '×BW',
    'reps':         ' reps',
    'time_minutes': ' min',
}


def _parse_time(t: str) -> float:
    """Convert 'M:SS' time string to minutes as float."""
    parts = str(t).split(':')
    return round(int(parts[0]) + int(parts[1]) / 60, 3)


# (domain, exercise_key) -> (value_key, unit, lower_is_better, display_name)
_CELL_EXTRACT = {
    ('hips',      'back_squat'):           ('male_bw_pct', '×BW',   False, 'Back Squat'),
    ('hips',      'broad_jump'):           ('metres',      ' m',    False, 'Broad Jump'),
    ('push',      'shoulder_press'):       ('male_bw_pct', '×BW',   False, 'Shoulder Press'),
    ('push',      'thruster'):             ('male_bw_pct', '×BW',   False, 'Thruster'),
    ('pull',      'deadlift'):             ('male_bw_pct', '×BW',   False, 'Deadlift'),
    ('pull',      'power_clean'):          ('male_bw_pct', '×BW',   False, 'Power Clean'),
    ('core',      'four_point_ab_bridge'): ('time_min',    ' min',  False, 'Plank Hold'),
    ('skill',     'double_under'):         ('reps',        ' reps', False, 'Double-Under'),
    ('endurance', 'run_400m'):             ('male_time',   ' min',  True,  '400m Run'),
    ('endurance', 'run_800m'):             ('male_time',   ' min',  True,  '800m Run'),
    ('endurance', 'row_500m'):             ('male_time',   ' min',  True,  '500m Row'),
}


def _cell_benchmarks() -> list[dict]:
    path = os.path.join(_DATA_DIR, 'benchmarks', 'cell_standards.yaml')
    data = _load_yaml(path) or {}
    standards_data = data.get('standards', {})
    level_map = [('I', 'entry'), ('II', 'intermediate'), ('III', 'advanced'), ('IV', 'elite')]
    result = []

    for (domain, exercise), (key, unit, lower, name) in _CELL_EXTRACT.items():
        ex_data = standards_data.get(domain, {}).get(exercise, {})
        levels_data = ex_data.get('levels', {})
        standards: dict[str, float] = {}

        for roman, level_name in level_map:
            lvl = levels_data.get(roman, {})
            val = lvl.get(key)
            if val is None:
                break
            standards[level_name] = _parse_time(val) if key == 'male_time' else float(val)

        if len(standards) < 4:
            continue

        result.append({
            'id':              f'cell_{domain}_{exercise}',
            'name':            name,
            'category':        'cell',
            'domain':          domain,
            'unit':            unit,
            'standards':       standards,
            'lower_is_better': lower,
        })

    return result


def _all_benchmarks() -> list[dict]:
    result = []
    for fname in ('strength_standards.yaml', 'conditioning_standards.yaml'):
        path = os.path.join(_DATA_DIR, 'benchmarks', fname)
        items = _load_yaml(path) or []
        for item in items:
            domain = item.get('domain', '')
            metric_type = item.get('metric_type', '')
            levels = item.get('levels', {})
            standards: dict[str, float] = {}
            for lvl in ('entry', 'intermediate', 'advanced', 'elite'):
                lvl_data = levels.get(lvl, {})
                val = lvl_data.get('male') if isinstance(lvl_data, dict) else None
                if val is not None:
                    standards[lvl] = val
            if len(standards) < 4:
                continue
            b: dict = {
                'id':              item['id'],
                'name':            item['name'],
                'category':        _BENCHMARK_CATEGORY_MAP.get(domain, 'conditioning'),
                'unit':            _BENCHMARK_UNIT_MAP.get(metric_type, ''),
                'standards':       standards,
                'lower_is_better': bool(item.get('lower_is_better', False)),
            }
            if item.get('notes'):
                b['notes'] = item['notes'].strip()
            result.append(b)
    result.extend(_cell_benchmarks())
    return result


def _week_volume(week_data: dict) -> dict:
    """Compute volume metrics for one week (for volume_summary)."""
    strength_mods   = {'max_strength', 'power', 'relative_strength', 'strength_endurance'}
    cardio_mods     = {'aerobic_base', 'anaerobic_intervals', 'mixed_modal_conditioning'}
    durability_mods = {'durability'}
    mobility_mods   = {'mobility', 'movement_skill'}

    strength_sets = cond_min = dur_min = mob_min = total_min = 0

    for day_sessions in week_data['schedule'].values():
        for session in day_sessions:
            modality = session.get('modality', '')
            arch = session.get('archetype') or {}
            arch_duration = arch.get('duration_estimate_minutes', 0) or 0
            total_min += arch_duration

            if modality in strength_mods:
                strength_sets += sum(
                    ea['load']['sets']
                    for ea in session.get('exercises', [])
                    if not ea.get('meta') and ea.get('load') and 'sets' in ea['load']
                )
            elif modality in cardio_mods:
                cond_min += arch_duration
            elif modality in durability_mods:
                dur_min += arch_duration
            elif modality in mobility_mods:
                mob_min += arch_duration

    return {
        'week_number':    week_data['week_number'],
        'strength_sets':  strength_sets,
        'cond_minutes':   cond_min,
        'dur_minutes':    dur_min,
        'mob_minutes':    mob_min,
        'total_minutes':  total_min,
    }


def _clean_exercise_assignment(ea: dict) -> dict:
    """Strip internal fields; return what the frontend expects."""
    load = dict(ea.get('load') or {})
    # Surface load_note at the assignment level so the frontend can render it per-exercise
    load_note = load.pop('load_note', None)
    return {
        'exercise':    ea.get('exercise'),
        'load':        load,
        'slot_role':   ea.get('slot_role'),
        'meta':        bool(ea.get('meta')),
        'injury_skip': bool(ea.get('injury_skip')),
        'error':       ea.get('error'),
        'load_note':   load_note,
    }


def _transform_program(raw: dict, goal: dict, constraints: dict, validation) -> dict:
    """Convert the engine's dict output to the GeneratedProgram shape the frontend expects."""
    weeks = []
    for wk in raw.get('weeks', []):
        # Remap integer day keys to day names
        named_schedule: dict[str, list] = {}
        for day_int, sessions in sorted(wk['schedule'].items()):
            day_name = _DAY_NAMES[day_int - 1] if 1 <= day_int <= 7 else f'Day {day_int}'
            named_sessions = []
            for session in sessions:
                named_sessions.append({
                    'modality':  session.get('modality'),
                    'archetype': session.get('archetype'),
                    'is_deload': session.get('is_deload', wk.get('is_deload', False)),
                    'exercises': [
                        _clean_exercise_assignment(ea)
                        for ea in session.get('exercises', [])
                    ],
                })
            named_schedule[day_name] = named_sessions

        weeks.append({
            'week_number':   wk['week_number'],
            'week_in_phase': wk['week_in_phase'],
            'phase':         wk['phase'],
            'is_deload':     wk.get('is_deload', False),
            'framework':     wk.get('framework'),
            'schedule':      named_schedule,
        })

    volume_summary = []
    for raw_wk in raw.get('weeks', []):
        volume_summary.append(_week_volume(raw_wk))

    return {
        'goal':           goal,
        'constraints':    constraints,
        'validation':     {
            'feasible': validation.feasible,
            'errors':   validation.errors,
            'warnings': validation.warnings,
            'info':     validation.info,
        },
        'weeks':          weeks,
        'volume_summary': volume_summary,
    }


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.get('/api/goals')
def get_goals():
    return jsonify(_all_goals())


@app.get('/api/goals/<goal_id>')
def get_goal(goal_id: str):
    try:
        return jsonify(loader.load_goal(goal_id))
    except FileNotFoundError as e:
        return jsonify({'detail': str(e)}), 404


@app.get('/api/exercises')
def get_exercises():
    return jsonify(_all_exercises())


@app.get('/api/modalities')
def get_modalities():
    return jsonify(_all_modalities())


@app.get('/api/constraints/equipment-profiles')
def get_equipment_profiles():
    return jsonify(_equipment_profiles())


@app.get('/api/constraints/injury-flags')
def get_injury_flags():
    return jsonify(_injury_flags())


@app.get('/api/benchmarks')
def get_benchmarks():
    return jsonify(_all_benchmarks())


@app.get('/api/frameworks')
def get_frameworks():
    result = []
    fw_dir = os.path.join(_DATA_DIR, 'frameworks')
    for path in sorted(glob.glob(os.path.join(fw_dir, '*.yaml'))):
        result.append(_load_yaml(path))
    return jsonify(result)


@app.get('/api/philosophies')
def get_philosophies():
    return jsonify(loader.load_philosophies())


@app.post('/api/programs/generate')
def generate_program():
    import traceback as _tb
    body = request.get_json(silent=True) or {}
    try:
        return _generate_program_inner(body)
    except Exception as e:
        msg = _tb.format_exc()
        import os as _os
        _os.makedirs('C:/tmp', exist_ok=True)
        with open('C:/tmp/api_errors.txt', 'a') as _f:
            import json as _json
            _f.write(f'body: {_json.dumps(body)}\n{msg}\n---\n')
        raise


def _generate_program_inner(body):
    goal_id = body.get('goal_id')
    goal_ids = body.get('goal_ids', [])

    if not goal_id and not goal_ids:
        return jsonify({'detail': 'goal_id or goal_ids is required'}), 400
    if not goal_ids:
        goal_ids = [goal_id]

    constraints = body.get('constraints', {})

    # Normalise constraints — fill in any missing fields with sensible defaults
    constraints.setdefault('days_per_week', 5)
    constraints.setdefault('session_time_minutes', 75)
    constraints.setdefault('training_level', 'intermediate')
    constraints.setdefault('equipment', ['barbell', 'rack', 'plates', 'kettlebell',
                                          'pull_up_bar', 'ruck_pack', 'open_space'])
    constraints.setdefault('injury_flags', [])
    constraints.setdefault('training_phase', 'base')
    constraints.setdefault('periodization_week', 1)
    constraints.setdefault('fatigue_state', 'normal')

    # Framework override — stored in constraints so scheduler.select_framework picks it up
    framework_id = body.get('framework_id')
    if framework_id:
        constraints['forced_framework'] = framework_id

    goal_weights_raw = body.get('goal_weights', {})
    goals_loaded = []
    for gid in goal_ids:
        try:
            w = goal_weights_raw.get(gid, 1.0 / len(goal_ids))
            goals_loaded.append({'goal': loader.load_goal(gid), 'weight': w})
        except FileNotFoundError as e:
            return jsonify({'detail': str(e)}), 404

    blend_warnings: list[str] = []
    if len(goals_loaded) == 1:
        goal = goals_loaded[0]['goal']
        goal_dict_for_generate = None
    else:
        from src.blender import blend_goals as _blend
        goal, blend_warnings = _blend(goals_loaded)
        goal_dict_for_generate = goal

    # Priority overrides — normalised and applied on top of the loaded/blended goal
    priority_overrides = body.get('priority_overrides')
    if priority_overrides:
        total = sum(float(v) for v in priority_overrides.values()) or 1.0
        normalised = {k: float(v) / total for k, v in priority_overrides.items()}
        goal = dict(goal)
        goal['priorities'] = normalised
        goal_dict_for_generate = goal

    phase_schedule_override = None
    event_date_str = body.get('event_date')
    if event_date_str:
        try:
            from src.phase_calendar import build_remaining_schedule
            event_date = _date.fromisoformat(event_date_str)
            cal = compute_phase_from_date(goal, event_date)
            constraints['training_phase'] = cal['phase']
            constraints['periodization_week'] = cal['week_in_phase']
            # Build the exact week-by-week schedule from today to the event,
            # ignoring any num_weeks the frontend may have sent.
            phase_schedule_override = build_remaining_schedule(cal)
        except (ValueError, KeyError):
            pass  # malformed date — fall back to constraints as-is

    data = loader.load_all_data()

    # Merge custom injury flags from POST body into the engine's injury data
    extra_injury_flags: dict = {}
    for flag in body.get('custom_injury_flags', []):
        flag_id = flag.get('id')
        if flag_id:
            extra_injury_flags[flag_id] = flag
            if flag_id not in constraints['injury_flags']:
                constraints['injury_flags'].append(flag_id)
    merged_injury_flags = {**data['injury_flags'], **extra_injury_flags}

    validation = validate(goal, constraints, data['archetypes'], data['modalities'],
                          merged_injury_flags)

    for w in blend_warnings:
        validation.warnings.append({
            'code': 'GOAL_BLEND_CONFLICT',
            'message': w,
            'suggested_fix': 'Consider running these goals in separate training blocks.',
        })

    phase_total = sum(p.get('weeks', 0) for p in goal.get('phase_sequence', []))
    num_weeks = body.get('num_weeks', phase_total or 4)

    if not validation.feasible:
        raw = {'weeks': []}
    else:
        raw = generate(
            goal_id=goal_ids[0],
            goal_dict=goal_dict_for_generate,
            constraints=constraints,
            num_weeks=num_weeks,
            # When event date is set, phase_schedule_override drives the exact
            # week-by-week plan to the event; num_weeks is ignored by the engine.
            phase_schedule=phase_schedule_override,
            output_format='dict',
            extra_injury_flags=extra_injury_flags or None,
        )

    result = _transform_program(raw, goal, constraints, validation)
    return jsonify(result)


@app.errorhandler(Exception)
def handle_error(e):
    import traceback as _tb
    msg = _tb.format_exc()
    with open('C:/tmp/api_errors.txt', 'a') as _f:
        _f.write(msg + '\n---\n')
    app.logger.exception(e)
    return jsonify({'detail': str(e)}), 500


if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8000))
    print(f'Training API running on http://localhost:{port}/api')
    app.run(host='0.0.0.0', port=port, debug=True)
