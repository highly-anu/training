"""Flask REST API — bridges the frontend to the Python training engine."""
from __future__ import annotations

import glob
import os
import re
import sys
import tempfile
from datetime import date as _date, timedelta as _timedelta

import yaml
from dotenv import load_dotenv
load_dotenv()
from flask import Flask, jsonify, redirect, request
from flask_cors import CORS

# Ensure src/ is importable when running from repo root
sys.path.insert(0, os.path.dirname(__file__))

from src import loader
from src.generator import generate
from src.phase_calendar import compute_phase_from_date
from src.progression import calculate_load
from src.selector import populate_session
from src.validator import validate
from src.auth import require_auth
from flask import g

app = Flask(__name__)
app.json.sort_keys = False   # preserve insertion order (days Mon→Sun)

_raw_origins = os.environ.get('FRONTEND_URL') or ''
_allowed_origins = set(o.strip() for o in _raw_origins.split(',') if o.strip()) or {'*'}

@app.after_request
def _cors(response):
    origin = request.headers.get('Origin', '')
    if '*' in _allowed_origins or origin in _allowed_origins:
        response.headers['Access-Control-Allow-Origin'] = origin or '*'
        response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS, PATCH'
        response.headers['Access-Control-Allow-Headers'] = 'Authorization, Content-Type'
        response.headers['Access-Control-Max-Age'] = '600'
    return response

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
    for path in sorted(glob.glob(os.path.join(_DATA_DIR, 'goals', '**', '*.yaml'), recursive=True)):
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

    strength_sets = strength_minutes = cond_min = dur_min = mob_min = total_min = 0

    for day_sessions in week_data['schedule'].values():
        for session in day_sessions:
            modality = session.get('modality', '')
            arch = session.get('archetype') or {}

            # Prefer computed duration from exercise loads (reflects week-by-week progression);
            # fall back to the static YAML estimate only when no loads are present.
            computed_dur = sum(
                ea.get('load', {}).get('duration_minutes', 0)
                for ea in session.get('exercises', [])
                if not ea.get('meta') and ea.get('load')
            )
            arch_duration = computed_dur if computed_dur > 0 else (arch.get('duration_estimate_minutes', 0) or 0)
            total_min += arch_duration

            if modality in strength_mods:
                sets_counted = sum(
                    ea['load']['sets']
                    for ea in session.get('exercises', [])
                    if not ea.get('meta') and ea.get('load') and 'sets' in ea['load']
                )
                strength_sets += sets_counted
                if sets_counted == 0 and computed_dur > 0:
                    # time-domain strength session (e.g. KB pentathlon, breathing ladder)
                    strength_minutes += computed_dur
            elif modality in cardio_mods:
                cond_min += arch_duration
            elif modality in durability_mods:
                dur_min += arch_duration
            elif modality in mobility_mods:
                mob_min += arch_duration

    return {
        'week_number':      week_data['week_number'],
        'strength_sets':    strength_sets,
        'strength_minutes': strength_minutes,
        'cond_minutes':     cond_min,
        'dur_minutes':      dur_min,
        'mob_minutes':      mob_min,
        'total_minutes':    total_min,
    }


def _clean_exercise_assignment(ea: dict) -> dict:
    """Strip internal fields; return what the frontend expects."""
    load = dict(ea.get('load') or {})
    # Surface load_note at the assignment level so the frontend can render it per-exercise
    load_note = load.pop('load_note', None)
    slot = ea.get('slot') or {}
    return {
        'exercise':    ea.get('exercise'),
        'load':        load,
        'slot_role':   ea.get('slot_role'),
        'slot_type':   slot.get('slot_type'),
        'rest_sec':    slot.get('rest_sec'),
        'meta':        bool(ea.get('meta')),
        'injury_skip': bool(ea.get('injury_skip')),
        'error':       ea.get('error'),
        'load_note':   load_note,
        'notes':       slot.get('notes'),
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


_VALID_PHASES = {'base', 'build', 'peak', 'taper', 'deload', 'maintenance', 'rehab', 'post_op'}


@app.post('/api/goals')
def create_goal():
    body = request.get_json(silent=True) or {}
    if not body.get('id') or not body.get('name'):
        return jsonify({'detail': 'id and name are required'}), 400
    priorities = body.get('priorities') or {}
    if not priorities:
        return jsonify({'detail': 'priorities is required'}), 400
    total = sum(priorities.values())
    if not (0.95 <= total <= 1.05):
        return jsonify({'detail': f'priorities must sum to ~1.0 (got {total:.2f})'}), 400
    phase_sequence = body.get('phase_sequence') or []
    for entry in phase_sequence:
        if entry.get('phase') not in _VALID_PHASES:
            return jsonify({'detail': f"unknown phase: {entry.get('phase')!r}"}), 400
    existing_ids = {g['id'] for g in _all_goals()}
    if body['id'] in existing_ids:
        return jsonify({'detail': f"Goal id '{body['id']}' already exists"}), 409
    custom_dir = os.path.join(_DATA_DIR, 'goals', 'custom')
    os.makedirs(custom_dir, exist_ok=True)
    path = os.path.join(custom_dir, f"{body['id']}.yaml")
    with open(path, 'w', encoding='utf-8') as f:
        yaml.dump(body, f, allow_unicode=True, default_flow_style=False, sort_keys=False)
    return jsonify(body), 201


@app.get('/api/exercises')
def get_exercises():
    return jsonify(_all_exercises())


@app.get('/api/modalities')
def get_modalities():
    return jsonify(_all_modalities())


@app.post('/api/modalities')
def create_modality():
    body = request.get_json(silent=True) or {}
    if not body.get('id') or not body.get('name'):
        return jsonify({'detail': 'id and name are required'}), 400
    if body.get('recovery_cost') not in ('high', 'medium', 'low'):
        return jsonify({'detail': 'recovery_cost must be high, medium, or low'}), 400
    existing_ids = {m['id'] for m in _all_modalities()}
    if body['id'] in existing_ids:
        return jsonify({'detail': f"Modality id '{body['id']}' already exists"}), 409
    path = os.path.join(_DATA_DIR, 'modalities', f"{body['id']}.yaml")
    with open(path, 'w', encoding='utf-8') as f:
        yaml.dump(body, f, allow_unicode=True, default_flow_style=False, sort_keys=False)
    return jsonify(body), 201


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


@app.get('/api/archetypes')
def get_archetypes():
    return jsonify(sorted(loader.load_all_archetypes(), key=lambda a: a.get('id', '')))


@app.get('/api/ontology')
def get_ontology():
    """Lightweight static graph of the full ontology for heatmap visualization."""
    # Philosophies
    philosophies = []
    for path in sorted(glob.glob(os.path.join(_DATA_DIR, 'philosophies', '*.yaml'))):
        p = _load_yaml(path)
        philosophies.append({'id': p['id'], 'name': p.get('name', p['id'])})

    # Frameworks (with source_philosophy + modality links)
    frameworks = []
    fw_dir = os.path.join(_DATA_DIR, 'frameworks')
    for path in sorted(glob.glob(os.path.join(fw_dir, '*.yaml'))):
        fw = _load_yaml(path)
        frameworks.append({
            'id': fw['id'],
            'name': fw.get('name', fw['id']),
            'source_philosophy': fw.get('source_philosophy'),
            'sessions_per_week_keys': list(fw.get('sessions_per_week', {}).keys()),
        })

    # Modalities
    modalities = []
    for path in sorted(glob.glob(os.path.join(_DATA_DIR, 'modalities', '*.yaml'))):
        m = _load_yaml(path)
        modalities.append({'id': m['id'], 'name': m.get('name', m['id'])})

    # Archetypes — include slot exercise_filter so the heatmap can reflect actual selection logic
    archetypes = []
    for arch in loader.load_all_archetypes():
        slots = []
        for slot in arch.get('slots', []):
            ef = slot.get('exercise_filter') or {}
            slots.append({
                'role': slot.get('role', ''),
                'skip_exercise': bool(slot.get('skip_exercise', False)),
                'exercise_filter': {
                    'movement_pattern': ef.get('movement_pattern'),
                    'category': ef.get('category'),
                },
            })
        archetypes.append({
            'id': arch['id'],
            'name': arch.get('name', arch['id']),
            'modality': arch.get('modality'),
            'slots': slots,
        })
    archetypes.sort(key=lambda a: a['id'])

    # Exercises — include movement_patterns for slot-filter matching in heatmap
    exercises = []
    all_ex = loader.load_all_exercises()
    for ex in sorted(all_ex.values(), key=lambda e: e['id']):
        mod = ex.get('modality', [])
        if isinstance(mod, str):
            mod = [mod]
        exercises.append({
            'id': ex['id'],
            'name': ex.get('name', ex['id']),
            'category': ex.get('category'),
            'modality': mod,
            'movement_patterns': ex.get('movement_patterns', []),
        })

    return jsonify({
        'philosophies': philosophies,
        'frameworks': frameworks,
        'modalities': modalities,
        'archetypes': archetypes,
        'exercises': exercises,
    })


@app.post('/api/exercises')
def create_exercise():
    body = request.get_json(silent=True) or {}
    if not body.get('id') or not body.get('name'):
        return jsonify({'detail': 'id and name are required'}), 400
    existing_ids = {ex['id'] for ex in _all_exercises()}
    if body['id'] in existing_ids:
        return jsonify({'detail': f"Exercise id '{body['id']}' already exists"}), 409
    custom_path = os.path.join(_DATA_DIR, 'exercises', 'custom.yaml')
    if os.path.exists(custom_path):
        data = _load_yaml(custom_path) or {'exercises': []}
    else:
        data = {'exercises': []}
    data['exercises'].append(body)
    with open(custom_path, 'w', encoding='utf-8') as f:
        yaml.dump(data, f, allow_unicode=True, default_flow_style=False, sort_keys=False)
    return jsonify(body), 201


def _find_exercise_file_and_index(ex_id: str):
    """Return (path, index, data) for an exercise by id, or (None, None, None)."""
    for path in sorted(glob.glob(os.path.join(_DATA_DIR, 'exercises', '*.yaml'))):
        data = _load_yaml(path) or {}
        for i, ex in enumerate(data.get('exercises', [])):
            if ex.get('id') == ex_id:
                return path, i, data
    return None, None, None


@app.put('/api/exercises/<ex_id>')
def update_exercise(ex_id: str):
    body = request.get_json(silent=True) or {}
    path, idx, data = _find_exercise_file_and_index(ex_id)
    if path is None:
        return jsonify({'detail': f"Exercise '{ex_id}' not found"}), 404
    data['exercises'][idx].update({k: v for k, v in body.items() if k != 'id'})
    with open(path, 'w', encoding='utf-8') as f:
        yaml.dump(data, f, allow_unicode=True, default_flow_style=False, sort_keys=False)
    return jsonify(data['exercises'][idx]), 200


def _find_archetype_file(arch_id: str) -> str | None:
    """Return the YAML file path for an archetype by id, or None."""
    for path in glob.glob(os.path.join(_DATA_DIR, 'archetypes', '**', '*.yaml'), recursive=True):
        try:
            data = _load_yaml(path)
            if data.get('id') == arch_id:
                return path
        except Exception:
            continue
    return None


@app.put('/api/archetypes/<arch_id>')
def update_archetype(arch_id: str):
    body = request.get_json(silent=True) or {}
    path = _find_archetype_file(arch_id)
    if not path:
        return jsonify({'detail': f"Archetype '{arch_id}' not found"}), 404
    data = _load_yaml(path)
    data.update({k: v for k, v in body.items() if v is not None})
    with open(path, 'w', encoding='utf-8') as f:
        yaml.dump(data, f, allow_unicode=True, default_flow_style=False, sort_keys=False)
    return jsonify(data), 200


@app.put('/api/frameworks/<fw_id>')
def update_framework(fw_id: str):
    body = request.get_json(silent=True) or {}
    path = os.path.join(_DATA_DIR, 'frameworks', f'{fw_id}.yaml')
    if not os.path.exists(path):
        return jsonify({'detail': f"Framework '{fw_id}' not found"}), 404
    data = _load_yaml(path)
    allowed = {'name', 'source_philosophy', 'sessions_per_week', 'notes'}
    for k, v in body.items():
        if k in allowed and v is not None:
            data[k] = v
    with open(path, 'w', encoding='utf-8') as f:
        yaml.dump(data, f, allow_unicode=True, default_flow_style=False, sort_keys=False)
    return jsonify(data), 200


@app.post('/api/archetypes')
def create_archetype():
    body = request.get_json(silent=True) or {}
    if not body.get('id') or not body.get('name'):
        return jsonify({'detail': 'id and name are required'}), 400
    arch_id = body['id']
    if not re.fullmatch(r'[A-Za-z0-9_-]+', arch_id):
        return jsonify({'detail': 'id must contain only letters, digits, underscores, and hyphens'}), 400
    existing_ids = {a.get('id') for a in loader.load_all_archetypes()}
    if arch_id in existing_ids:
        return jsonify({'detail': f"Archetype id '{arch_id}' already exists"}), 409
    custom_dir = os.path.join(_DATA_DIR, 'archetypes', 'custom')
    os.makedirs(custom_dir, exist_ok=True)
    out_path = os.path.join(custom_dir, f"{arch_id}.yaml")
    with open(out_path, 'w', encoding='utf-8') as f:
        yaml.dump(body, f, allow_unicode=True, default_flow_style=False, sort_keys=False)
    return jsonify(body), 201


@app.post('/api/programs/generate')
@require_auth
def generate_program():
    import traceback as _tb
    body = request.get_json(silent=True) or {}
    try:
        return _generate_program_inner(body)
    except Exception as e:
        msg = _tb.format_exc()
        with open(os.path.join(tempfile.gettempdir(), 'api_errors.txt'), 'a') as _f:
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
    program_start_monday = None
    start_date_str = body.get('start_date')
    if start_date_str:
        try:
            sd = _date.fromisoformat(start_date_str)
            # Monday of the week containing start_date (weekday() is 0 for Mon)
            program_start_monday = sd - _timedelta(days=sd.weekday())
        except ValueError:
            pass

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

    include_trace = bool(body.get('include_trace')) or request.args.get('trace') == '1'

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
            include_trace=include_trace,
        )

    result = _transform_program(raw, goal, constraints, validation)
    if include_trace and 'generation_trace' in raw:
        result['generation_trace'] = raw['generation_trace']
    if program_start_monday:
        result['program_start_date'] = program_start_monday.isoformat()
    return jsonify(result)


@app.post('/api/sessions/generate')
@require_auth
def generate_session():
    """Generate a single replacement session for a given modality/phase/constraints.

    Accepts an optional archetype_id to force a specific archetype (Browse tab);
    without it the selector chooses the best-fit archetype (Generate tab).
    """
    import traceback as _tb
    body = request.get_json(silent=True) or {}
    try:
        return _generate_session_inner(body)
    except Exception as e:
        msg = _tb.format_exc()
        with open(os.path.join(tempfile.gettempdir(), 'api_errors.txt'), 'a') as _f:
            import json as _json
            _f.write(f'session-generate body: {_json.dumps(body)}\n{msg}\n---\n')
        raise


def _generate_session_inner(body):
    goal_id  = body.get('goal_id')
    modality = body.get('modality')
    phase    = body.get('phase')
    week_in_phase = body.get('week_in_phase', 1)
    is_deload = bool(body.get('is_deload', False))

    if not goal_id:
        return jsonify({'detail': 'goal_id is required'}), 400
    if not modality:
        return jsonify({'detail': 'modality is required'}), 400
    if not phase:
        return jsonify({'detail': 'phase is required'}), 400

    constraints = dict(body.get('constraints', {}))
    constraints.setdefault('session_time_minutes', 75)
    constraints.setdefault('training_level', 'intermediate')
    constraints.setdefault('equipment', ['barbell', 'rack', 'plates', 'kettlebell',
                                          'pull_up_bar', 'ruck_pack', 'open_space'])
    constraints.setdefault('injury_flags', [])
    constraints.setdefault('fatigue_state', 'normal')

    try:
        goal = loader.load_goal(goal_id)
    except FileNotFoundError as e:
        return jsonify({'detail': str(e)}), 404

    data = loader.load_all_data()

    # Merge custom injury flags
    extra_injury_flags: dict = {}
    for flag in body.get('custom_injury_flags', []):
        flag_id = flag.get('id')
        if flag_id:
            extra_injury_flags[flag_id] = flag
            if flag_id not in constraints['injury_flags']:
                constraints['injury_flags'].append(flag_id)
    merged_injury_flags = {**data['injury_flags'], **extra_injury_flags}

    # Resolve forced archetype if archetype_id provided (Browse tab)
    archetype_id = body.get('archetype_id')
    forced_arch: dict | None = None
    if archetype_id:
        forced_arch = next((a for a in data['archetypes'] if a.get('id') == archetype_id), None)
        if forced_arch is None:
            return jsonify({'detail': f'Archetype {archetype_id!r} not found'}), 404
        # Use the archetype's own modality — the request modality is the session being replaced
        modality = forced_arch.get('modality', modality)

    session_stub = {'modality': modality, 'is_deload': is_deload}
    populated = populate_session(
        session_stub, goal, constraints,
        data['exercises'], data['archetypes'],
        merged_injury_flags, phase, week_in_phase,
        forced_archetype=forced_arch,
    )

    if populated.get('archetype') is None:
        return jsonify({'detail': f'No archetype found for {modality!r} in phase {phase!r}'}), 422

    # Apply progression loads
    prog_model = data['modalities'].get(modality, {}).get('progression_model', 'linear_load')
    for ea in populated.get('exercises', []):
        if ea.get('exercise') is None:
            continue
        ea['load'] = calculate_load(
            ea['exercise'],
            ea['slot'],
            prog_model,
            week_in_phase,
            phase,
            constraints.get('training_level', 'intermediate'),
            is_deload,
            session_time_minutes=constraints.get('session_time_minutes', 75),
        )

    arch = populated.get('archetype', {})
    return jsonify({
        'modality':  modality,
        'archetype': arch,
        'is_deload': is_deload,
        'duration_min': arch.get('duration_estimate_minutes') if arch else None,
        'exercises': [_clean_exercise_assignment(ea) for ea in populated.get('exercises', [])],
    })


@app.get('/api/oauth/strava/status')
@require_auth
def strava_status():
    import oauth as _oauth
    _oauth.init_db()
    return jsonify(_oauth.get_strava_status(g.user_id))


@app.get('/api/oauth/strava/authorize')
@require_auth
def strava_authorize():
    import oauth as _oauth
    _oauth.init_db()
    if not _oauth.is_configured():
        return jsonify({'detail': 'STRAVA_CLIENT_ID / STRAVA_CLIENT_SECRET not set in environment'}), 503
    return jsonify({'auth_url': _oauth.generate_auth_url(g.user_id)})


@app.get('/api/oauth/strava/callback')
def strava_callback():
    import oauth as _oauth
    _oauth.init_db()
    frontend_url = os.environ.get('FRONTEND_URL', 'http://localhost:5173')
    error = request.args.get('error')
    if error:
        return redirect(f'{frontend_url}/import?strava=error&reason={error}')
    code = request.args.get('code', '')
    state = request.args.get('state', '')
    try:
        _oauth.handle_callback(code, state)
        return redirect(f'{frontend_url}/import?strava=connected')
    except Exception as e:
        return redirect(f'{frontend_url}/import?strava=error&reason={e}')


@app.delete('/api/oauth/strava/disconnect')
@require_auth
def strava_disconnect():
    import oauth as _oauth
    _oauth.init_db()
    _oauth.disconnect(g.user_id)
    return jsonify({'disconnected': True})


@app.post('/api/oauth/strava/sync')
@require_auth
def strava_sync():
    import oauth as _oauth
    _oauth.init_db()
    status = _oauth.get_strava_status(g.user_id)
    if not status.get('connected'):
        return jsonify({'detail': 'Strava not connected'}), 401
    body = request.get_json(silent=True) or {}
    since = body.get('since_timestamp')
    activities = _oauth.sync_activities(g.user_id, since_timestamp=since)
    return jsonify({'activities': activities, 'count': len(activities)})


def _clean_hr_samples(samples: list, session_avg_hr: float | None = None) -> list:
    """Remove sensor lock-on artifacts and smooth outliers from HR sample lists.

    1. Startup trim  — drop readings in the first 30 s that are below 75 % of
       session average HR, but only for real exercise sessions (avg > 100 bpm).
       This eliminates the optical-HR cold-start lag common on Apple Watch.
    2. Rolling median — replace every sample with the median of its ±7.5 s
       neighbourhood (min 3 neighbours required) to suppress mid-workout spikes
       without distorting genuine effort changes.
    """
    from statistics import median as _median
    from datetime import datetime, timezone

    if not samples:
        return samples

    # Parse timestamps once
    parsed: list[tuple[float, int, str]] = []  # (unix_ts, bpm, iso_str)
    for s in samples:
        try:
            dt = datetime.fromisoformat(s['timestamp'])
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            parsed.append((dt.timestamp(), int(s['bpm']), s['timestamp']))
        except Exception:
            continue

    if not parsed:
        return samples

    # 1 — Startup trim: drop all leading readings below threshold until HR first
    #     stabilises at exercise level. Handles cold-start lag of any duration
    #     (Apple Watch can take 3-5 min to lock on). Guard: never trim > 5 min.
    avg = session_avg_hr or (sum(b for _, b, _ in parsed) / len(parsed))
    if avg > 100:
        threshold = avg * 0.75
        start_ts = parsed[0][0]
        first_valid = next(
            (i for i, (ts, bpm, _) in enumerate(parsed)
             if bpm >= threshold or ts - start_ts > 300),
            0,
        )
        parsed = parsed[first_valid:]

    if not parsed:
        return samples

    # 2 — Rolling median (±7.5 s window)
    cleaned = []
    for ts, bpm, iso in parsed:
        window = sorted(b for t, b, _ in parsed if abs(t - ts) <= 7.5)
        smoothed = int(round(_median(window))) if len(window) >= 3 else bpm
        cleaned.append({'timestamp': iso, 'bpm': smoothed})

    return cleaned


@app.post('/api/workouts/parse')
def parse_workout_file():
    """Server-side workout file parser for large exports (> 50 MB).
    Accepts multipart/form-data with field 'workout_file'.
    Supports Apple Health XML (.xml) and Strava activities JSON (.json).
    Returns a list of ImportedWorkout-shaped objects.
    """
    import xml.etree.ElementTree as ET
    import json as _json
    import math

    f = request.files.get('workout_file')
    if not f:
        return jsonify({'detail': 'workout_file field required'}), 400

    filename = (f.filename or '').lower()

    APPLE_HEALTH_MAP = {
        'HKWorkoutActivityTypeRunning': 'aerobic_base',
        'HKWorkoutActivityTypeCycling': 'aerobic_base',
        'HKWorkoutActivityTypeSwimming': 'aerobic_base',
        'HKWorkoutActivityTypeWalking': 'durability',
        'HKWorkoutActivityTypeHiking': 'durability',
        'HKWorkoutActivityTypeHighIntensityIntervalTraining': 'anaerobic_intervals',
        'HKWorkoutActivityTypeCrossTraining': 'mixed_modal_conditioning',
        'HKWorkoutActivityTypeTraditionalStrengthTraining': 'max_strength',
        'HKWorkoutActivityTypeFunctionalStrengthTraining': 'strength_endurance',
        'HKWorkoutActivityTypeCoreTraining': 'strength_endurance',
        'HKWorkoutActivityTypeYoga': 'mobility',
        'HKWorkoutActivityTypeFlexibility': 'mobility',
        'HKWorkoutActivityTypeMartialArts': 'combat_sport',
        'HKWorkoutActivityTypeBoxing': 'combat_sport',
        'HKWorkoutActivityTypeRowingMachine': 'aerobic_base',
    }

    STRAVA_MAP = {
        'Run': 'aerobic_base', 'TrailRun': 'aerobic_base', 'VirtualRun': 'aerobic_base',
        'Ride': 'aerobic_base', 'VirtualRide': 'aerobic_base', 'Swim': 'aerobic_base',
        'Walk': 'durability', 'Hike': 'durability',
        'WeightTraining': 'max_strength',
        'HIIT': 'anaerobic_intervals', 'Crossfit': 'mixed_modal_conditioning',
        'Workout': 'mixed_modal_conditioning', 'Yoga': 'mobility', 'Rowing': 'aerobic_base',
        'MartialArts': 'combat_sport',
    }

    import uuid as _uuid
    import hashlib as _hashlib

    def _deterministic_id(source, start_time, activity_type, duration_minutes):
        raw = f"{source}|{start_time}|{activity_type}|{duration_minutes}"
        h = _hashlib.sha256(raw.encode()).hexdigest()[:24]
        return f"{source}-{h}"

    def _minutes_between(start_str, end_str):
        from datetime import datetime
        try:
            fmt = '%Y-%m-%d %H:%M:%S %z'
            s = datetime.strptime(start_str, fmt)
            e = datetime.strptime(end_str, fmt)
            return round((e - s).total_seconds() / 60)
        except Exception:
            return 0

    def _local_date(iso_str):
        from datetime import datetime
        try:
            d = datetime.fromisoformat(iso_str.replace(' +', '+').replace(' -', '-'))
            return d.strftime('%Y-%m-%d')
        except Exception:
            return iso_str[:10]

    if filename.endswith('.xml'):
        results = []
        try:
            context = ET.iterparse(f.stream, events=('start',))
            for _event, elem in context:
                if elem.tag != 'Workout':
                    continue
                activity_type = elem.get('workoutActivityType', '')
                start_date = elem.get('startDate', '')
                end_date = elem.get('endDate', '')
                if not start_date or not end_date:
                    continue

                hr_avg = hr_max = hr_min = None
                calories = None
                distance_val = distance_unit = None

                for child in elem:
                    t = child.get('type', '')
                    if t == 'HKQuantityTypeIdentifierHeartRate':
                        avg = child.get('average')
                        mx = child.get('maximum')
                        mn = child.get('minimum')
                        if avg: hr_avg = float(avg)
                        if mx: hr_max = float(mx)
                        if mn: hr_min = float(mn)
                    elif t == 'HKQuantityTypeIdentifierActiveEnergyBurned':
                        s = child.get('sum')
                        if s: calories = math.floor(float(s))
                    elif t in ('HKQuantityTypeIdentifierDistanceWalkingRunning',
                               'HKQuantityTypeIdentifierDistanceCycling'):
                        s = child.get('sum')
                        u = child.get('unit', '')
                        if s:
                            distance_val = float(s)
                            distance_unit = 'km' if 'km' in u.lower() else 'm'

                dur = _minutes_between(start_date, end_date)
                workout = {
                    'id': _deterministic_id('apple_health', start_date, activity_type, dur),
                    'source': 'apple_health',
                    'date': _local_date(start_date),
                    'startTime': start_date,
                    'endTime': end_date,
                    'durationMinutes': dur,
                    'activityType': activity_type,
                    'inferredModalityId': APPLE_HEALTH_MAP.get(activity_type),
                    'heartRate': {
                        'avg': hr_avg, 'max': hr_max, 'min': hr_min, 'samples': []
                    },
                    'calories': calories,
                    'distance': {'value': distance_val, 'unit': distance_unit} if distance_val else None,
                    'rawData': {},
                }
                results.append(workout)
                elem.clear()  # free memory
        except ET.ParseError as e:
            return jsonify({'detail': f'XML parse error: {e}'}), 422
        return jsonify(results)

    elif filename.endswith('.json'):
        try:
            data = _json.load(f.stream)
        except _json.JSONDecodeError as e:
            return jsonify({'detail': f'JSON parse error: {e}'}), 422
        if not isinstance(data, list):
            return jsonify({'detail': 'Expected a JSON array of Strava activities'}), 422
        results = []
        for a in data:
            if not isinstance(a, dict) or not a.get('start_date'):
                continue
            sport_type = a.get('sport_type') or a.get('type') or 'Workout'
            elapsed = a.get('elapsed_time', 0)
            from datetime import datetime, timezone
            try:
                start_dt = datetime.fromisoformat(a['start_date'].replace('Z', '+00:00'))
                end_dt = datetime.fromtimestamp(start_dt.timestamp() + elapsed, tz=timezone.utc)
            except Exception:
                continue
            dist = a.get('distance', 0)
            kj = a.get('kilojoules')
            dur_min = round(elapsed / 60)
            results.append({
                'id': _deterministic_id('strava', start_dt.isoformat(), sport_type, dur_min),
                'source': 'strava',
                'date': start_dt.strftime('%Y-%m-%d'),
                'startTime': start_dt.isoformat(),
                'endTime': end_dt.isoformat(),
                'durationMinutes': dur_min,
                'activityType': sport_type,
                'inferredModalityId': STRAVA_MAP.get(sport_type),
                'heartRate': {
                    'avg': a.get('average_heartrate'),
                    'max': a.get('max_heartrate'),
                    'min': None,
                    'samples': [],
                },
                'calories': round(kj * 0.239) if kj else None,
                'distance': {'value': round(dist / 1000, 3), 'unit': 'km'} if dist else None,
                'rawData': {},
            })
        return jsonify(results)

    elif filename.endswith('.fit'):
        try:
            import fitparse as _fitparse
        except ImportError:
            return jsonify({'detail': 'fitparse library not installed — run pip install fitparse'}), 503

        from datetime import datetime as _dt, timezone as _tz

        _FIT_SPORT_MAP = {
            'running':           'aerobic_base',
            'cycling':           'aerobic_base',
            'swimming':          'aerobic_base',
            'walking':           'durability',
            'hiking':            'durability',
            'rowing':            'aerobic_base',
            'elliptical':        'aerobic_base',
            'yoga':              'mobility',
            'flexibility':       'mobility',
            'training':          'mixed_modal_conditioning',
            'generic':           'mixed_modal_conditioning',
            'strength_training': 'max_strength',
            'cardio':            'aerobic_base',
            'cross_training':    'mixed_modal_conditioning',
            'hiit':              'anaerobic_intervals',
            'boxing':            'combat_sport',
            'martial_arts':      'combat_sport',
        }

        # Semicircles → degrees conversion factor
        _SEMI_TO_DEG = 180.0 / (2 ** 31)

        try:
            fit = _fitparse.FitFile(f.stream)

            # ── Collect all record-level data (GPS, HR, altitude, cadence, power) ──
            records = []
            for rec in fit.get_messages('record'):
                ts = rec.get_value('timestamp')
                if ts is None:
                    continue
                if ts.tzinfo is None:
                    ts = ts.replace(tzinfo=_tz.utc)

                lat_semi = rec.get_value('position_lat')
                lon_semi = rec.get_value('position_long')
                lat = float(lat_semi) * _SEMI_TO_DEG if lat_semi is not None else None
                lng = float(lon_semi) * _SEMI_TO_DEG if lon_semi is not None else None

                records.append({
                    'timestamp': ts.isoformat(),
                    'lat':       lat,
                    'lng':       lng,
                    'altitude':  float(rec.get_value('enhanced_altitude') or rec.get_value('altitude') or 0) if (rec.get_value('enhanced_altitude') or rec.get_value('altitude')) is not None else None,
                    'bpm':       int(rec.get_value('heart_rate')) if rec.get_value('heart_rate') is not None else None,
                    'cadence':   int(rec.get_value('cadence')) if rec.get_value('cadence') is not None else None,
                    'power':     int(rec.get_value('power')) if rec.get_value('power') is not None else None,
                    'speed':     float(rec.get_value('enhanced_speed') or rec.get_value('speed') or 0) if (rec.get_value('enhanced_speed') or rec.get_value('speed')) is not None else None,
                })

            # Build GPS track (only points with coordinates)
            gps_track = [
                {'lat': r['lat'], 'lng': r['lng'], 'altitude': r['altitude'], 'timestamp': r['timestamp'], 'bpm': r['bpm']}
                for r in records if r['lat'] is not None and r['lng'] is not None
            ]

            # Build HR samples (all points with valid HR, filter zeros)
            hr_samples = _clean_hr_samples(
                [{'timestamp': r['timestamp'], 'bpm': r['bpm']}
                 for r in records if r['bpm'] is not None and r['bpm'] > 0]
            )

            # ── Session-level summary (unchanged logic) ──
            results = []
            for session in fit.get_messages('session'):
                sport = str(session.get_value('sport') or 'generic').lower()
                sub_sport = str(session.get_value('sub_sport') or '').lower()

                start_time = session.get_value('start_time')  # UTC naive datetime
                elapsed = float(
                    session.get_value('total_elapsed_time')
                    or session.get_value('total_timer_time')
                    or 0
                )

                if not start_time:
                    continue

                if start_time.tzinfo is None:
                    start_time = start_time.replace(tzinfo=_tz.utc)
                end_time = _dt.fromtimestamp(start_time.timestamp() + elapsed, tz=_tz.utc)

                # Prefer sub_sport, but skip 'generic' since it's uninformative
                modality = (
                    (_FIT_SPORT_MAP.get(sub_sport) if sub_sport not in ('generic', 'none', '') else None)
                    or _FIT_SPORT_MAP.get(sport)
                )
                avg_hr  = session.get_value('avg_heart_rate')
                max_hr  = session.get_value('max_heart_rate')
                calories = session.get_value('total_calories')
                dist_m   = session.get_value('total_distance')  # meters

                # Elevation gain/loss from records
                elev_gain = 0.0
                elev_loss = 0.0
                prev_alt = None
                for pt in gps_track:
                    if pt['altitude'] is not None:
                        if prev_alt is not None:
                            diff = pt['altitude'] - prev_alt
                            if diff > 0:
                                elev_gain += diff
                            else:
                                elev_loss += abs(diff)
                        prev_alt = pt['altitude']

                # Use sub_sport for display when it adds meaning
                display_type = (
                    sub_sport
                    if sub_sport and sub_sport not in ('generic', 'none', '')
                    else sport
                ).replace('_', ' ').title()

                fit_dur = round(elapsed / 60)
                results.append({
                    'id':                _deterministic_id('fit_file', start_time.isoformat(), display_type, fit_dur),
                    'source':            'fit_file',
                    'date':              start_time.strftime('%Y-%m-%d'),
                    'startTime':         start_time.isoformat(),
                    'endTime':           end_time.isoformat(),
                    'durationMinutes':   fit_dur,
                    'activityType':      display_type,
                    'inferredModalityId': modality,
                    'heartRate': {
                        'avg': float(avg_hr)  if avg_hr  is not None else None,
                        'max': float(max_hr)  if max_hr  is not None else None,
                        'min': None,
                        'samples': hr_samples,
                    },
                    'calories':  int(calories) if calories is not None else None,
                    'distance':  {'value': round(float(dist_m) / 1000, 3), 'unit': 'km'} if dist_m else None,
                    'gpsTrack':  gps_track if gps_track else None,
                    'elevation': {'gain': round(elev_gain), 'loss': round(elev_loss)} if elev_gain or elev_loss else None,
                    'rawData':   {'sport': sport, 'sub_sport': sub_sport},
                })

            return jsonify(results)
        except Exception as e:
            return jsonify({'detail': f'FIT parse error: {e}'}), 422

    return jsonify({'detail': 'Unsupported file type — use .xml, .json, or .fit'}), 415


# ---------------------------------------------------------------------------
# User profile & program (Supabase Postgres)
# ---------------------------------------------------------------------------

def _profile_to_frontend(row: dict) -> dict:
    return {
        'trainingLevel':     row.get('training_level', 'intermediate'),
        'equipment':         row.get('equipment') or [],
        'injuryFlags':       row.get('injury_flags') or [],
        'customInjuryFlags': row.get('custom_injury_flags') or [],
        'activeGoalId':      row.get('active_goal_id'),
        'dateOfBirth':       str(row['date_of_birth']) if row.get('date_of_birth') else None,
    }


@app.get('/api/profile')
@require_auth
def get_profile():
    import json as _json
    try:
        from src.db import get_conn
        user_id = g.user_id
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute('SELECT * FROM user_profiles WHERE id = %s', (user_id,))
                row = cur.fetchone()
                if row is None:
                    cur.execute(
                        'INSERT INTO user_profiles (id) VALUES (%s) RETURNING *', (user_id,)
                    )
                    row = cur.fetchone()
                    conn.commit()
        return jsonify(_profile_to_frontend(dict(row)) if row else {})
    except Exception as e:
        app.logger.warning('get_profile error: %s', e)
        return jsonify({})


@app.put('/api/profile')
@require_auth
def update_profile():
    import json as _json
    try:
        from src.db import get_conn
        user_id = g.user_id
        body = request.get_json(silent=True) or {}
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute('''
                    INSERT INTO user_profiles
                        (id, training_level, equipment, injury_flags,
                         custom_injury_flags, active_goal_id, date_of_birth, updated_at)
                    VALUES (%s, %s, %s::jsonb, %s::jsonb, %s::jsonb, %s, %s, NOW())
                    ON CONFLICT (id) DO UPDATE SET
                        training_level      = EXCLUDED.training_level,
                        equipment           = EXCLUDED.equipment,
                        injury_flags        = EXCLUDED.injury_flags,
                        custom_injury_flags = EXCLUDED.custom_injury_flags,
                        active_goal_id      = EXCLUDED.active_goal_id,
                        date_of_birth       = EXCLUDED.date_of_birth,
                        updated_at          = NOW()
                ''', (
                    user_id,
                    body.get('trainingLevel', 'intermediate'),
                    _json.dumps(body.get('equipment', [])),
                    _json.dumps(body.get('injuryFlags', [])),
                    _json.dumps(body.get('customInjuryFlags', [])),
                    body.get('activeGoalId'),
                    body.get('dateOfBirth'),
                ))
                conn.commit()
        return jsonify({'saved': True})
    except Exception as e:
        app.logger.warning('update_profile error: %s', e)
        return jsonify({'saved': False, 'detail': str(e)}), 503


@app.get('/api/user/program')
@require_auth
def get_user_program():
    try:
        from src.db import get_conn
        user_id = g.user_id
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute('SELECT * FROM user_programs WHERE user_id = %s', (user_id,))
                row = cur.fetchone()
        if not row:
            return jsonify(None)
        return jsonify({
            'currentProgram':    row.get('current_program'),
            'programStartDate':  str(row['program_start_date']) if row.get('program_start_date') else None,
            'eventDate':         str(row['event_date']) if row.get('event_date') else None,
            'sourceGoalIds':     row.get('source_goal_ids') or [],
            'sourceGoalWeights': row.get('source_goal_weights') or {},
        })
    except Exception as e:
        app.logger.warning('get_user_program error: %s', e)
        return jsonify(None)


@app.put('/api/user/program')
@require_auth
def save_user_program():
    import json as _json
    try:
        from src.db import get_conn
        user_id = g.user_id
        body = request.get_json(silent=True) or {}
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute('''
                    INSERT INTO user_programs
                        (user_id, current_program, program_start_date,
                         event_date, source_goal_ids, source_goal_weights, updated_at)
                    VALUES (%s, %s::jsonb, %s, %s, %s::jsonb, %s::jsonb, NOW())
                    ON CONFLICT (user_id) DO UPDATE SET
                        current_program     = EXCLUDED.current_program,
                        program_start_date  = EXCLUDED.program_start_date,
                        event_date          = EXCLUDED.event_date,
                        source_goal_ids     = EXCLUDED.source_goal_ids,
                        source_goal_weights = EXCLUDED.source_goal_weights,
                        updated_at          = NOW()
                ''', (
                    user_id,
                    _json.dumps(body.get('currentProgram')),
                    body.get('programStartDate'),
                    body.get('eventDate'),
                    _json.dumps(body.get('sourceGoalIds', [])),
                    _json.dumps(body.get('sourceGoalWeights', {})),
                ))
                conn.commit()
        return jsonify({'saved': True})
    except Exception as e:
        app.logger.warning('save_user_program error: %s', e)
        return jsonify({'saved': False, 'detail': str(e)}), 503


# ---------------------------------------------------------------------------
# Health data storage
# ---------------------------------------------------------------------------

from src import health_store as _health


@app.get('/api/health/snapshot')
@require_auth
def health_snapshot():
    return jsonify({
        'workouts':        _health.get_workouts(g.user_id),
        'sessionLogs':     _health.get_session_logs(g.user_id),
        'dailyBio':        _health.get_daily_bio(g.user_id),
        'matches':         _health.get_matches(g.user_id),
        'performanceLogs': _health.get_performance_logs(g.user_id),
    })


@app.post('/api/health/workouts')
@require_auth
def health_upsert_workouts():
    body = request.get_json(silent=True) or {}
    workouts = body.get('workouts', [])
    if not isinstance(workouts, list):
        return jsonify({'detail': 'workouts must be an array'}), 400
    _health.upsert_workouts(g.user_id, workouts)
    return jsonify({'saved': len(workouts)})


@app.delete('/api/health/workouts/<workout_id>')
@require_auth
def health_delete_workout(workout_id: str):
    _health.delete_workout(g.user_id, workout_id)
    return jsonify({'deleted': workout_id})


@app.put('/api/health/sessions/<path:session_key>')
@require_auth
def health_upsert_session(session_key: str):
    log = request.get_json(silent=True) or {}
    log['sessionKey'] = session_key
    _health.upsert_session_log(g.user_id, log)
    return jsonify({'saved': session_key})


@app.get('/api/health/bio/synced-dates')
@require_auth
def health_synced_dates():
    return jsonify(_health.get_synced_dates(g.user_id))


@app.put('/api/health/bio/<date>')
@require_auth
def health_upsert_bio(date: str):
    entry = request.get_json(silent=True) or {}
    entry['date'] = date
    _health.upsert_daily_bio(g.user_id, entry)
    return jsonify({'saved': date})


@app.post('/api/health/matches')
@require_auth
def health_upsert_match():
    match = request.get_json(silent=True) or {}
    _health.upsert_match(g.user_id, match)
    return jsonify({'saved': match.get('importedWorkoutId')})


@app.post('/api/health/performance')
@require_auth
def health_add_performance():
    body = request.get_json(silent=True) or {}
    benchmark_id = body.get('benchmarkId', '')
    value = body.get('value')
    logged_at = body.get('loggedAt', '')
    if not benchmark_id or value is None:
        return jsonify({'detail': 'benchmarkId and value required'}), 400
    _health.add_performance_entry(g.user_id, benchmark_id, float(value), logged_at)
    return jsonify({'saved': benchmark_id})


@app.delete('/api/health/performance/<benchmark_id>')
@require_auth
def health_delete_performance(benchmark_id: str):
    _health.delete_performance_log(g.user_id, benchmark_id)
    return jsonify({'deleted': benchmark_id})


@app.errorhandler(Exception)
def handle_error(e):
    import traceback as _tb
    msg = _tb.format_exc()
    err_path = os.path.join(os.path.dirname(__file__), 'data', 'api_errors.txt')
    with open(err_path, 'a') as _f:
        _f.write(msg + '\n---\n')
    app.logger.exception(e)
    return jsonify({'detail': str(e)}), 500


if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8000))
    print(f'Training API running on http://localhost:{port}/api')
    app.run(host='0.0.0.0', port=port, debug=True)
