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

# Ensure src/ is importable when running from repo root
sys.path.insert(0, os.path.dirname(__file__))

from src import fit_import as _fit_import
from src import workout_ids as _workout_ids
from src import goals, loader, provenance
from src.similarity import compute_all_similarities
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

# Cloudflare Pages preview deployments use *.pages.dev subdomains that change per-commit.
# Allow any pages.dev origin so preview URLs work without Fly.io config changes.
_ALLOWED_ORIGIN_SUFFIXES = ('.pages.dev', '.pages.dev/')

def _origin_allowed(origin: str) -> bool:
    if not origin:
        return True
    if '*' in _allowed_origins or origin in _allowed_origins:
        return True
    return any(origin.endswith(s) for s in _ALLOWED_ORIGIN_SUFFIXES)

@app.before_request
def _handle_options():
    if request.method == 'OPTIONS':
        return app.make_default_options_response()

@app.after_request
def _cors(response):
    origin = request.headers.get('Origin', '')
    if _origin_allowed(origin):
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


def _all_exercises() -> list[dict]:
    global_index, _ = loader.load_all_exercises()
    media = loader.load_exercise_media()
    result = []
    for ex in global_index.values():
        ex = dict(ex)
        if isinstance(ex.get('sources'), str):
            ex['sources'] = [ex['sources']]
        if ex['id'] in media:
            ex.update(media[ex['id']])
        result.append(ex)
    return sorted(result, key=lambda e: e.get('id', ''))


def _all_modalities() -> list[dict]:
    return sorted(loader.load_all_modalities().values(), key=lambda m: m.get('id', ''))


def _equipment_profiles() -> list[dict]:
    return loader.load_equipment_profiles()


# Similarity cache — computed once at first request (lazy, not blocking startup)
_similarity_cache: dict | None = None

def _get_similarity() -> dict:
    global _similarity_cache
    if _similarity_cache is None:
        philosophies = loader.load_philosophies()
        frameworks   = loader.load_all_frameworks()
        modalities   = loader.load_all_modalities()
        archetypes   = loader.load_all_archetypes()
        exercises, _ = loader.load_all_exercises()
        _similarity_cache = compute_all_similarities(
            philosophies, frameworks, modalities, archetypes, exercises
        )
    return _similarity_cache


def _injury_flags() -> list[dict]:
    return list(loader.load_injury_flags().values())


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
        # Unfilled because the philosophy's packages own nothing for this slot,
        # as opposed to equipment or level ruling everything out.
        'coverage_gap': bool(ea.get('coverage_gap')),
        'gap_reason':   ea.get('gap_reason'),
        'error':       ea.get('error'),
        'load_note':   load_note,
        'notes':       slot.get('notes'),
        # Links an amrap_movement component to the amrap slot it belongs to.
        # Without it these render as separate sequential exercises instead of
        # as the movements of one AMRAP.
        'parent_slot_role': slot.get('parent_slot_role'),
        'skip_exercise':    bool(slot.get('skip_exercise')),
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
                    'provenance': session.get('provenance'),
                    'exercises': [
                        _clean_exercise_assignment(ea)
                        for ea in session.get('exercises', [])
                    ],
                    # Was computed by the generator and dropped here, so the
                    # SessionDetail view that renders it never received any.
                    'complementary_work': session.get('complementary_work', []),
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
        'compromises':    raw.get('compromises', []),
        'coverage_report': raw.get('coverage_report'),
    }


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.get('/api/exercises')
def get_exercises():
    return jsonify(_all_exercises())


@app.get('/api/exercises/<ex_id>/media')
def get_exercise_media(ex_id: str):
    entry = loader.load_exercise_media().get(ex_id)
    return jsonify(entry or {}), 200


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
    path = os.path.join(_DATA_DIR, 'commons', 'modalities', f"{body['id']}.yaml")
    with open(path, 'w', encoding='utf-8') as f:
        yaml.dump(body, f, allow_unicode=True, default_flow_style=False, sort_keys=False)
    return jsonify(body), 201


@app.get('/api/equipment')
def get_equipment():
    return jsonify(loader.load_equipment())


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
    fw_dict = loader.load_all_frameworks()
    return jsonify(sorted(fw_dict.values(), key=lambda fw: fw.get('id', '')))


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
    for p in loader.load_philosophies():
        philosophies.append({'id': p['id'], 'name': p.get('name', p['id'])})

    # Frameworks (with source_philosophy + modality links)
    frameworks = []
    for fw in sorted(loader.load_all_frameworks().values(), key=lambda f: f.get('id', '')):
        frameworks.append({
            'id': fw['id'],
            'name': fw.get('name', fw['id']),
            'source_philosophy': fw.get('source_philosophy'),
            'sessions_per_week_keys': list(fw.get('sessions_per_week', {}).keys()),
        })

    # Modalities
    modalities = []
    for m in sorted(loader.load_all_modalities().values(), key=lambda m: m.get('id', '')):
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
    all_ex_index, _ = loader.load_all_exercises()
    for ex in sorted(all_ex_index.values(), key=lambda e: e['id']):
        mod = ex.get('modality', [])
        if isinstance(mod, str):
            mod = [mod]
        exercises.append({
            'id': ex['id'],
            'name': ex.get('name', ex['id']),
            'category': ex.get('category'),
            'modality': mod,
            'movement_patterns': ex.get('movement_patterns', []),
            '_package': ex.get('_package'),
            '_packages': ex.get('_packages', []),
        })

    return jsonify({
        'philosophies': philosophies,
        'frameworks': frameworks,
        'modalities': modalities,
        'archetypes': archetypes,
        'exercises': exercises,
    })


@app.get('/api/similarity')
def get_similarity():
    """Pairwise likeness scores for all ontology categories.

    Returns {category: {id_a: {id_b: {score, primary, secondary}}}}
    Scores are symmetric and pre-computed on first call.
    """
    return jsonify(_get_similarity())


@app.post('/api/exercises')
def create_exercise():
    body = request.get_json(silent=True) or {}
    if not body.get('id') or not body.get('name'):
        return jsonify({'detail': 'id and name are required'}), 400
    existing_ids = {ex['id'] for ex in _all_exercises()}
    if body['id'] in existing_ids:
        return jsonify({'detail': f"Exercise id '{body['id']}' already exists"}), 409
    custom_pkg_dir = os.path.join(_DATA_DIR, 'packages', 'custom')
    os.makedirs(custom_pkg_dir, exist_ok=True)
    custom_path = os.path.join(custom_pkg_dir, 'exercises.yaml')
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
    for path in sorted(glob.glob(os.path.join(_DATA_DIR, 'packages', '*', 'exercises.yaml'))):
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
    for path in glob.glob(
        os.path.join(_DATA_DIR, 'packages', '*', 'archetypes', '**', '*.yaml'),
        recursive=True,
    ):
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
    matches = glob.glob(os.path.join(_DATA_DIR, 'packages', '*', 'frameworks', f'{fw_id}.yaml'))
    if not matches:
        return jsonify({'detail': f"Framework '{fw_id}' not found"}), 404
    path = matches[0]
    data = _load_yaml(path)
    allowed = {'name', 'source_philosophy', 'sessions_per_week', 'cadence_options',
               'deload_protocol', 'applicable_when', 'notes'}
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
    custom_dir = os.path.join(_DATA_DIR, 'packages', 'custom', 'archetypes')
    os.makedirs(custom_dir, exist_ok=True)
    out_path = os.path.join(custom_dir, f"{arch_id}.yaml")
    with open(out_path, 'w', encoding='utf-8') as f:
        yaml.dump(body, f, allow_unicode=True, default_flow_style=False, sort_keys=False)
    return jsonify(body), 201


def _goal_ids_from_body(body: dict, generated: dict) -> tuple[list, dict]:
    """Source philosophy ids + weights for an envelope, from the request if it
    carried them, else recovered from the generated goal's own id."""
    ids = body.get('philosophy_ids') or body.get('goal_ids') or []
    if not ids and body.get('philosophy_id'):
        ids = [body['philosophy_id']]
    if not ids:
        # A synthetic goal's id is '_phil_<philosophy_id>' (see
        # _philosophy_to_goal), so it can be read back when the caller did not
        # say which philosophy it asked for.
        goal_id = ((generated.get('goal') or {}).get('id') or '')
        if goal_id.startswith('_phil_'):
            ids = [goal_id[len('_phil_'):]]
    weights = body.get('philosophy_weights') or body.get('goal_weights') or {}
    return list(ids), dict(weights)


def _wrap_generated_program(generated: dict, body: dict, existing) -> dict:
    """Put a freshly generated program into the stored envelope.

    Keeps the existing start date when there is one, so regenerating does not
    silently restart the athlete's calendar.
    """
    existing = _normalize_program_keys(existing) if isinstance(existing, dict) else {}
    ids, weights = _goal_ids_from_body(body, generated)
    return {
        'currentProgram':    generated,
        'programStartDate':  existing.get('programStartDate') or _date.today().isoformat(),
        'eventDate':         body.get('event_date') or existing.get('eventDate'),
        'sourceGoalIds':     ids or existing.get('sourceGoalIds') or [],
        'sourceGoalWeights': weights or existing.get('sourceGoalWeights') or {},
    }


@app.post('/api/programs/generate')
@require_auth
def generate_program():
    import traceback as _tb
    body = request.get_json(silent=True) or {}
    try:
        resp = _generate_program_inner(body)
        # Auto-save the generated program to the DB so Garmin/Watch can fetch it.
        #
        # This MUST write the envelope, not the bare GeneratedProgram. Saving
        # `resp_data` directly (as this did) left program_data with the
        # generator's own top-level keys — no `currentProgram`, no
        # `programStartDate` — and every client reads `.currentProgram`, so the
        # program silently vanished from web and iOS while the weeks sat intact
        # in the database.
        try:
            from src.db import get_user_program, save_user_program
            import json as _json
            resp_data = _json.loads(resp.get_data(as_text=True))
            if isinstance(resp_data, dict) and resp_data.get('weeks') is not None:
                save_user_program(g.user_id,
                                  _wrap_generated_program(resp_data, body,
                                                          get_user_program(g.user_id)))
        except Exception as _save_err:
            app.logger.warning('generate: auto-save failed: %s', _save_err)
        return resp
    except Exception as e:
        msg = _tb.format_exc()
        with open(os.path.join(tempfile.gettempdir(), 'api_errors.txt'), 'a') as _f:
            import json as _json
            _f.write(f'body: {_json.dumps(body)}\n{msg}\n---\n')
        raise


def _philosophy_to_goal(phil_id: str, all_frameworks: list) -> dict:
    """Build a synthetic goal dict from a philosophy. See src/goals.py."""
    return goals.philosophy_to_goal(phil_id, all_frameworks)


def _blend_philosophy_goals(phil_ids: list, phil_weights: dict, all_frameworks: list) -> dict:
    """Weighted-average a set of philosophy synthetic goals into one."""
    return goals.blend_philosophy_goals(phil_ids, phil_weights, all_frameworks)


def _normalize_schedule_constraints(constraints: dict) -> dict:
    """
    Convert weekly_schedule into scheduler-compatible constraints.

    Maps session types to time allocations:
    - short: 40 minutes
    - long: 75 minutes
    - mobility: 20 minutes
    - rest: 0 minutes

    Extracts:
    - days_per_week: count of days with non-rest sessions
    - preferred_days: list of day indices (1=Mon, 7=Sun) with training
    - forced_rest_days: days marked as all rest
    - day_configs: per-day {minutes, has_secondary, session_types}
    - weekday_session_minutes, weekend_session_minutes: computed averages
    - allow_split_sessions: true if any day has multiple sessions
    """
    schedule = constraints.get('weekly_schedule')
    if not schedule:
        return constraints  # No schedule provided, use existing constraints

    DAY_INDICES = {
        'Monday': 1, 'Tuesday': 2, 'Wednesday': 3, 'Thursday': 4,
        'Friday': 5, 'Saturday': 6, 'Sunday': 7
    }
    TIME_MAP = {'short': 40, 'long': 75, 'mobility': 20, 'rest': 0}

    preferred_days = []
    forced_rest_days = []
    day_configs = {}
    weekday_times = []
    weekend_times = []

    for day_name, day_schedule in schedule.items():
        day_idx = DAY_INDICES[day_name]
        sessions = [
            day_schedule['session1'],
            day_schedule['session2'],
            day_schedule['session3'],
            day_schedule['session4']
        ]

        non_rest = [s for s in sessions if s != 'rest']

        if non_rest:
            preferred_days.append(day_idx)
            total_time = sum(TIME_MAP[s] for s in non_rest)

            # Classify session types by duration for smart matching
            duration_buckets = {
                'long': [s for s in non_rest if s == 'long'],       # 75min
                'short': [s for s in non_rest if s == 'short'],     # 40min
                'mobility': [s for s in non_rest if s == 'mobility']  # 20min
            }

            day_configs[day_idx] = {
                'minutes': total_time,
                'has_secondary': len(non_rest) > 1,
                'session_types': non_rest,  # For smart pairing
                'duration_buckets': duration_buckets,  # For duration matching
            }

            # Track weekday/weekend averages
            if day_idx <= 5:
                weekday_times.append(total_time)
            else:
                weekend_times.append(total_time)
        else:
            forced_rest_days.append(day_idx)

    # Build normalized constraints
    normalized = dict(constraints)
    normalized['days_per_week'] = len(preferred_days)
    normalized['preferred_days'] = preferred_days
    normalized['forced_rest_days'] = forced_rest_days
    normalized['day_configs'] = day_configs

    if weekday_times:
        normalized['weekday_session_minutes'] = int(sum(weekday_times) / len(weekday_times))
    if weekend_times:
        normalized['weekend_session_minutes'] = int(sum(weekend_times) / len(weekend_times))

    # Enable split sessions if any day has multiple sessions
    normalized['allow_split_sessions'] = any(
        cfg.get('has_secondary') for cfg in day_configs.values()
    )

    return normalized


def _generate_program_inner(body):
    philosophy_id = body.get('philosophy_id')
    philosophy_ids = body.get('philosophy_ids', [])
    philosophy_weights = body.get('philosophy_weights', {})

    if not philosophy_id and not philosophy_ids:
        return jsonify({'detail': 'philosophy_id or philosophy_ids is required'}), 400

    constraints = body.get('constraints', {})

    # Normalize weekly_schedule into scheduler-compatible constraints (BEFORE defaults)
    constraints = _normalize_schedule_constraints(constraints)

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

    blend_warnings: list[str] = []

    # ── Philosophy path: build synthetic goal from philosophy data ──────────
    all_frameworks = list(loader.load_all_frameworks().values())
    try:
        if philosophy_id:
            goal = _philosophy_to_goal(philosophy_id, all_frameworks)
        else:
            goal = _blend_philosophy_goals(philosophy_ids, philosophy_weights, all_frameworks)
    except FileNotFoundError as e:
        return jsonify({'detail': str(e)}), 404
    goal_dict_for_generate = goal
    goal_ids = [goal['id']]

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

    # One policy, used for BOTH validation and generation. These used to be two
    # separate filters — a strict one here and a fuzzy one inside generate() — so
    # validation was checking a different library than the one actually used.
    policy = provenance.resolve_source_policy(goal)
    lib = provenance.scope(data, policy)
    archetypes_filtered = lib['archetypes']

    validation = validate(goal, constraints, archetypes_filtered, data['modalities'],
                          merged_injury_flags, policy=policy)

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
            policy=policy,
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

    Accepts optional primary_sources (philosophy IDs) to prefer archetypes from those philosophies.
    Accepts optional archetype_id to force a specific archetype (Browse tab);
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
    primary_sources = body.get('primary_sources', [])  # Philosophy IDs
    modality = body.get('modality')
    phase    = body.get('phase')
    week_in_phase = body.get('week_in_phase', 1)
    is_deload = bool(body.get('is_deload', False))

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

    # Build minimal goal-like dict for populate_session (only needs primary_sources)
    goal = {'primary_sources': primary_sources}

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

    policy = provenance.resolve_source_policy(goal)
    lib = provenance.scope(data, policy)
    archetypes_filtered = lib['archetypes']

    # Resolve forced archetype if archetype_id provided (Browse tab)
    archetype_id = body.get('archetype_id')
    forced_arch: dict | None = None
    if archetype_id:
        forced_arch = next((a for a in data['archetypes'] if a.get('id') == archetype_id), None)
        if forced_arch is None:
            return jsonify({'detail': f'Archetype {archetype_id!r} not found'}), 404
        # A hand-picked archetype was never checked against the policy.
        if policy.strict and not provenance.allows_archetype(forced_arch, policy):
            return jsonify({
                'detail': (
                    f"Archetype {archetype_id!r} belongs to "
                    f"{forced_arch.get('_package')!r}, which "
                    f"{policy.describe()} does not draw from."
                )
            }), 422
        # Use the archetype's own modality — the request modality is the session being replaced
        modality = forced_arch.get('modality', modality)

    session_stub = {'modality': modality, 'is_deload': is_deload}
    populated = populate_session(
        session_stub, goal, constraints,
        lib['exercises'], archetypes_filtered,
        merged_injury_flags, phase, week_in_phase,
        forced_archetype=forced_arch,
        exercises_by_package=lib.get('exercises_by_package'),
        policy=policy,
        level_seeds=lib.get('level_seeds'),
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
    # Lands on the Connections tab, where StravaConnect actually renders. This
    # used to redirect to /import, a page that reads none of these parameters —
    # so the round-trip silently went nowhere.
    error = request.args.get('error')
    if error:
        return redirect(_integrations_redirect('strava', 'error', error))
    code = request.args.get('code', '')
    state = request.args.get('state', '')
    try:
        _oauth.handle_callback(code, state)
        return redirect(_integrations_redirect('strava', 'connected'))
    except Exception as e:
        return redirect(_integrations_redirect('strava', 'error', str(e)))


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


# ---------------------------------------------------------------------------
# Garmin Connect
# ---------------------------------------------------------------------------
# Mirrors the Strava block above. Everything is inert until GARMIN_CLIENT_ID /
# GARMIN_CLIENT_SECRET are set, so this ships safely before the Garmin
# Developer Program application is approved.

def _integrations_redirect(provider: str, outcome: str, reason: str = '') -> str:
    frontend_url = os.environ.get('FRONTEND_URL', 'http://localhost:5173')
    url = f'{frontend_url}/profile?tab=connections&{provider}={outcome}'
    if reason:
        url += f'&reason={reason}'
    return url


@app.get('/api/oauth/garmin/status')
@require_auth
def garmin_status():
    from src import garmin_connect
    return jsonify(garmin_connect.get_status(g.user_id))


@app.get('/api/oauth/garmin/authorize')
@require_auth
def garmin_authorize():
    from src import garmin_connect
    if not garmin_connect.is_configured():
        return jsonify({
            'detail': 'GARMIN_CLIENT_ID / GARMIN_CLIENT_SECRET not set in environment'
        }), 503
    return jsonify({'auth_url': garmin_connect.generate_auth_url(g.user_id)})


@app.get('/api/oauth/garmin/callback')
def garmin_callback():
    """Garmin redirects the athlete's browser here — no JWT available."""
    from src import garmin_connect
    error = request.args.get('error')
    if error:
        return redirect(_integrations_redirect('garmin', 'error', error))
    try:
        user_id = garmin_connect.handle_callback(
            request.args.get('code', ''), request.args.get('state', ''))
        # Pull recent history immediately; Garmin delivers it through the same
        # webhook, so there is nothing to poll.
        try:
            garmin_connect.request_backfill(user_id)
        except Exception as e:
            app.logger.warning('garmin backfill on connect failed: %s', e)
        return redirect(_integrations_redirect('garmin', 'connected'))
    except Exception as e:
        app.logger.warning('garmin callback failed: %s', e)
        return redirect(_integrations_redirect('garmin', 'error', str(e)))


@app.delete('/api/oauth/garmin/disconnect')
@require_auth
def garmin_disconnect():
    from src import garmin_connect
    garmin_connect.disconnect(g.user_id)
    return jsonify({'disconnected': True})


@app.post('/api/oauth/garmin/backfill')
@require_auth
def garmin_backfill():
    from src import garmin_connect
    if not garmin_connect.get_status(g.user_id).get('connected'):
        return jsonify({'detail': 'Garmin not connected'}), 401
    body = request.get_json(silent=True) or {}
    days = int(body.get('days') or 90)
    return jsonify(garmin_connect.request_backfill(g.user_id, days=days))


@app.post('/api/oauth/garmin/drain')
@require_auth
def garmin_drain():
    """Manual safety valve: retry queued webhook events.

    The worker thread normally handles these, but a machine restart mid-batch
    leaves rows pending until the next webhook arrives.
    """
    from src import garmin_worker
    return jsonify(garmin_worker.drain())


# ---------------------------------------------------------------------------
# Garmin webhooks
# ---------------------------------------------------------------------------
# Unauthenticated by necessity: Garmin holds no user JWT. The defences are
#   1. a shared secret in the URL, compared in constant time;
#   2. the body is never trusted for identity — only `userId` is used, and only
#      to look up an existing registration;
#   3. the activity itself is FETCHED from Garmin with our own token rather
#      than read out of the request body, and the callback host is checked
#      against GARMIN_API_BASE first (otherwise this endpoint is an SSRF
#      primitive for anyone who learns its URL).
#
# Always 200 except on a bad secret. Garmin retries non-2xx responses and
# eventually disables endpoints that keep failing, so a malformed or unknown
# payload is acknowledged and dropped, not errored.

def _webhook_authorized() -> bool:
    import hmac
    from src import garmin_connect
    expected = garmin_connect.webhook_secret()
    if not expected:
        return False
    supplied = request.args.get('t') or request.headers.get('X-Webhook-Token', '')
    return hmac.compare_digest(str(supplied), expected)


def _receive_garmin_webhook(event_type: str):
    from src import garmin_worker
    if not _webhook_authorized():
        return jsonify({'detail': 'Unauthorized'}), 401

    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        # Acknowledge and drop: retrying will not make it parse.
        app.logger.warning('garmin webhook (%s) had no JSON body', event_type)
        return jsonify({'received': 0}), 200

    try:
        garmin_worker.enqueue(event_type, payload)
        garmin_worker.kick()
    except Exception as e:
        # A 500 here would make Garmin retry, which is right — but only if the
        # failure is ours to fix. Log loudly and let it retry.
        app.logger.exception('could not queue garmin webhook: %s', e)
        return jsonify({'detail': 'Queue unavailable'}), 503

    return jsonify({'received': 1}), 200


@app.post('/api/webhooks/garmin/activities')
def garmin_webhook_activities():
    return _receive_garmin_webhook('activities')


@app.post('/api/webhooks/garmin/deregistration')
def garmin_webhook_deregistration():
    return _receive_garmin_webhook('deregistration')


@app.post('/api/webhooks/garmin/permission-change')
def garmin_webhook_permission_change():
    return _receive_garmin_webhook('permission_change')


# Both helpers now live in src/fit_import.py (the FIT parser needs them too).
# Aliased under their old private names so the existing call sites are unchanged
# — note _calc_elevation is also passed as a *callback* into
# health_store.recalculate_workouts_elevation, so its signature is load-bearing.
_calc_elevation = _fit_import.calc_elevation
_clean_hr_samples = _fit_import.clean_hr_samples


@app.post('/api/workouts/parse')
@require_auth
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

    # One formula, shared with the FIT path and the iOS/web parsers —
    # see src/workout_ids.py before changing anything about it.
    _deterministic_id = _workout_ids.deterministic_id

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
                'elevation': {'gain': round(float(a['total_elevation_gain'])), 'loss': 0}
                             if a.get('total_elevation_gain') else None,
                'rawData': {},
            })
        return jsonify(results)

    elif filename.endswith('.fit'):
        try:
            results = _fit_import.parse_fit(f.stream)
        except _fit_import.FitNotAvailable as e:
            return jsonify({'detail': str(e)}), 503
        except Exception as e:
            return jsonify({'detail': f'FIT parse error: {e}'}), 422

        if results:
            _health.upsert_workouts(g.user_id, results)
        return jsonify(results)

    return jsonify({'detail': 'Unsupported file type — use .xml, .json, or .fit'}), 415


# ---------------------------------------------------------------------------
# Async parse endpoints (for large Apple Health XML exports > 50 MB)
# ---------------------------------------------------------------------------

import threading as _threading
import time as _time

_parse_jobs: dict[str, dict] = {}
_parse_jobs_lock = _threading.Lock()

_JOB_TTL_SECONDS = 3600  # prune jobs older than 1 hour


def _prune_parse_jobs():
    now = _time.time()
    with _parse_jobs_lock:
        expired = [jid for jid, j in _parse_jobs.items() if now - j['created_at'] > _JOB_TTL_SECONDS]
        for jid in expired:
            del _parse_jobs[jid]


def _set_job(job_id: str, **kwargs):
    with _parse_jobs_lock:
        _parse_jobs[job_id].update(kwargs)


@app.post('/api/workouts/parse/async')
@require_auth
def parse_workout_file_async():
    """Submit a large workout file for background parsing.
    Returns {jobId} immediately; poll /api/workouts/parse/status/<jobId> for progress.
    NOTE: _parse_jobs is per-process. On multi-worker deployments a poll may hit a
    different worker. Acceptable trade-off for large-file imports.
    """
    import uuid as _uuid

    _prune_parse_jobs()

    f = request.files.get('workout_file')
    if not f:
        return jsonify({'detail': 'workout_file field required'}), 400

    # Read file bytes and metadata in the request thread (not safe after request ends)
    file_bytes = f.read()
    filename = (f.filename or '').lower()
    user_id = g.user_id   # capture — g is not available in the background thread

    job_id = str(_uuid.uuid4())
    with _parse_jobs_lock:
        _parse_jobs[job_id] = {
            'status': 'queued',
            'progress': 0.0,
            'stage': 'Queued',
            'result': None,
            'error': None,
            'created_at': _time.time(),
        }

    def _run():
        import xml.etree.ElementTree as ET
        try:
            _set_job(job_id, status='parsing', stage='Reading file…', progress=0.02)

            if filename.endswith('.xml'):
                # ── Apple Health XML parse ────────────────────────────────────
                _set_job(job_id, stage='Parsing XML…', progress=0.05)
                root = ET.fromstring(file_bytes.decode('utf-8', errors='replace'))
                workouts_xml = root.findall('Workout')
                total = len(workouts_xml)

                results = []
                for idx, wo in enumerate(workouts_xml):
                    if idx % 500 == 0 and total > 0:
                        pct = 0.10 + (idx / total) * 0.65
                        _set_job(job_id, progress=round(pct, 3),
                                 stage=f'Parsing workouts… ({idx}/{total})')

                    # Minimal re-use of the sync parser logic (inline to avoid import complexity)
                    import re as _re
                    act_type = wo.get('workoutActivityType', '')
                    start_str = wo.get('startDate', '')
                    end_str = wo.get('endDate', '')
                    if not start_str or not end_str:
                        continue
                    from datetime import datetime, timezone as _tz
                    try:
                        start_dt = datetime.fromisoformat(start_str.replace('Z', '+00:00'))
                        end_dt = datetime.fromisoformat(end_str.replace('Z', '+00:00'))
                    except Exception:
                        continue
                    duration_min = round((end_dt - start_dt).total_seconds() / 60, 1)
                    import hashlib as _hashlib
                    wo_id = 'ah_' + _hashlib.md5(f'{start_str}{act_type}'.encode()).hexdigest()[:12]

                    # HR stats
                    hr_avg = hr_max = hr_min = None
                    hr_samples_raw = []
                    for stat in wo.findall('WorkoutStatistics'):
                        if stat.get('type') == 'HKQuantityTypeIdentifierHeartRate':
                            try:
                                hr_avg  = float(stat.get('average', 0)) or None
                                hr_max  = float(stat.get('maximum', 0)) or None
                                hr_min  = float(stat.get('minimum', 0)) or None
                            except Exception:
                                pass
                    for rec in wo.findall('WorkoutEvent'):
                        pass  # events don't carry HR samples; HR samples live in root records

                    calories = None
                    distance_m = None
                    for stat in wo.findall('WorkoutStatistics'):
                        t = stat.get('type', '')
                        try:
                            if 'ActiveEnergyBurned' in t:
                                calories = float(stat.get('sum', 0)) or None
                            elif 'DistanceWalkingRunning' in t or 'DistanceCycling' in t or 'DistanceSwimming' in t:
                                distance_m = (float(stat.get('sum', 0)) or 0) * 1000  # km → m
                        except Exception:
                            pass

                    results.append({
                        'id':                 wo_id,
                        'source':             'apple_health',
                        'date':               start_dt.strftime('%Y-%m-%d'),
                        'startTime':          start_dt.isoformat(),
                        'endTime':            end_dt.isoformat(),
                        'durationMinutes':    duration_min,
                        'activityType':       act_type,
                        'inferredModalityId': None,
                        'heartRate':          {'avg': hr_avg, 'max': hr_max, 'min': hr_min, 'samples': []},
                        'calories':           calories,
                        'distance':           {'value': round(distance_m / 1000, 3), 'unit': 'km'} if distance_m else None,
                        'gpsTrack':           None,
                        'elevation':          None,
                        'rawData':            {},
                    })

                _set_job(job_id, stage='Saving to database…', progress=0.90)
                if results:
                    _health.upsert_workouts(user_id, results)
                _set_job(job_id, status='done', progress=1.0, stage='Done', result=results)

            else:
                # Unsupported for async path — caller should use sync endpoint
                _set_job(job_id, status='error', error='Only .xml files support async parsing')

        except Exception as exc:
            _set_job(job_id, status='error', error=str(exc))

    t = _threading.Thread(target=_run, daemon=True)
    t.start()

    return jsonify({'jobId': job_id}), 202


@app.get('/api/workouts/parse/status/<job_id>')
@require_auth
def parse_status(job_id: str):
    with _parse_jobs_lock:
        job = _parse_jobs.get(job_id)
    if job is None:
        return jsonify({'detail': 'Job not found'}), 404
    return jsonify({
        'jobId':    job_id,
        'status':   job['status'],
        'progress': job['progress'],
        'stage':    job['stage'],
        'error':    job['error'],
        'result':   job['result'] if job['status'] == 'done' else None,
    })


@app.get('/api/health/workouts/<workout_id>')
@require_auth
def health_get_workout(workout_id: str):
    workout = _health.get_workout(g.user_id, workout_id)
    if workout is None:
        return jsonify({'detail': 'Not found'}), 404
    return jsonify(workout)


@app.post('/api/health/workouts/recalculate-elevation')
@require_auth
def health_recalculate_elevation():
    """Re-compute elevation_gain/loss from stored GPS tracks for all user workouts."""
    result = _health.recalculate_workouts_elevation(g.user_id, _calc_elevation)
    if result.get('error'):
        return jsonify(result), 500
    return jsonify(result)


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
        'weeklySchedule':    row.get('weekly_schedule'),
    }


# ---------------------------------------------------------------------------
# Profile
# ---------------------------------------------------------------------------
# The profile is one JSONB blob (profiles.profile_data). Clients do not all know
# the same keys — iOS's UserProfile struct has no activeGoalId, the web app has
# no performanceLogs — so a write must MERGE over what is stored rather than
# rebuild the blob from the request body. Rebuilding is how activeGoalId used to
# get silently nulled every time the phone saved a profile.

# Which sources may be auto-imported from, and the master switch over all of
# them. Read by every import path before it writes a workout.
INTEGRATION_SOURCES = ('garmin', 'strava', 'appleHealth')

# Keys a client is allowed to write. Anything else already in the stored blob is
# preserved untouched; anything else in the body is ignored.
_PROFILE_KEYS = (
    'trainingLevel', 'equipment', 'injuryFlags', 'customInjuryFlags',
    'activeGoalId', 'dateOfBirth', 'weeklySchedule', 'hrConfig', 'integrations',
)


def default_integrations() -> dict:
    """Auto-import defaults: on, for every source.

    Defaulting to on is safe because a source only imports when it is *also*
    connected — so this changes nothing until the athlete connects something.
    """
    return {
        'autoImport': True,
        'sources': {name: {'enabled': True} for name in INTEGRATION_SOURCES},
    }


def _merge_integrations(stored) -> dict:
    """Fill a stored (possibly partial, possibly absent) integrations object out
    to the full shape, so callers can index it without defensive gets."""
    merged = default_integrations()
    if not isinstance(stored, dict):
        return merged
    if isinstance(stored.get('autoImport'), bool):
        merged['autoImport'] = stored['autoImport']
    stored_sources = stored.get('sources')
    if isinstance(stored_sources, dict):
        for name in INTEGRATION_SOURCES:
            entry = stored_sources.get(name)
            if isinstance(entry, dict) and isinstance(entry.get('enabled'), bool):
                merged['sources'][name]['enabled'] = entry['enabled']
    return merged


def _default_profile() -> dict:
    return {
        'trainingLevel': 'intermediate',
        'equipment': [],
        'injuryFlags': [],
        'customInjuryFlags': [],
        'activeGoalId': None,
        'dateOfBirth': None,
        'weeklySchedule': None,
        'hrConfig': {},
        'integrations': default_integrations(),
    }


def _sanitize_profile(profile: dict) -> dict:
    """Coerce the nullable fields to their empty values — a client may have
    stored null where a list or object is expected."""
    profile['trainingLevel'] = profile.get('trainingLevel') or 'intermediate'
    profile['equipment'] = profile.get('equipment') or []
    profile['injuryFlags'] = profile.get('injuryFlags') or []
    profile['customInjuryFlags'] = profile.get('customInjuryFlags') or []
    profile['hrConfig'] = profile.get('hrConfig') or {}
    profile['integrations'] = _merge_integrations(profile.get('integrations'))
    return profile


def get_integration_settings(user_id: str) -> dict:
    """The athlete's auto-import settings, fully defaulted. Import paths call
    this before writing; see `integration_allows`."""
    try:
        from src.db import get_user_profile
        return _merge_integrations((get_user_profile(user_id) or {}).get('integrations'))
    except Exception as e:
        app.logger.warning('get_integration_settings error: %s', e)
        return default_integrations()


def integration_allows(user_id: str, source: str) -> bool:
    """True when the athlete has auto-import on, both overall and for `source`."""
    settings = get_integration_settings(user_id)
    if not settings.get('autoImport'):
        return False
    return bool(settings['sources'].get(source, {}).get('enabled'))


@app.get('/api/profile')
@require_auth
def get_profile():
    try:
        from src.db import get_user_profile
        profile = _default_profile()
        stored = get_user_profile(g.user_id)
        if stored:
            profile.update(stored)
        return jsonify(_sanitize_profile(profile))
    except Exception as e:
        app.logger.warning('get_profile error: %s', e)
        return jsonify(_default_profile())


@app.put('/api/profile')
@require_auth
def update_profile():
    try:
        from src.db import get_user_profile, save_user_profile
        user_id = g.user_id
        body = request.get_json(silent=True) or {}

        # Start from what is stored (keeping keys this client doesn't know about)
        # and overwrite only the keys the body actually carries.
        profile_data = _default_profile()
        profile_data.update(get_user_profile(user_id) or {})
        for key in _PROFILE_KEYS:
            if key in body:
                profile_data[key] = body[key]

        save_user_profile(user_id, _sanitize_profile(profile_data))
        return jsonify({'saved': True})
    except Exception as e:
        app.logger.warning('update_profile error: %s', e)
        return jsonify({'saved': False, 'detail': str(e)}), 503


@app.get('/api/userdata/profile')
@require_auth
def get_userdata_profile():
    return get_profile()


@app.put('/api/userdata/profile')
@require_auth
def update_userdata_profile():
    return update_profile()


@app.get('/api/user/program')
@require_auth
def get_user_program_endpoint():
    try:
        from src.db import get_user_program, save_user_program
        user_id = g.user_id
        program = get_user_program(user_id)
        if isinstance(program, dict):
            program = _normalize_program_keys(program)

            # Heal a program stored WITHOUT its envelope — the generate
            # auto-save used to write the bare GeneratedProgram, leaving the
            # generator's own keys at the top level and no `currentProgram`.
            # Every client reads `.currentProgram`, so such a row reads as "no
            # program" even though all the weeks are there. Wrap it and persist
            # the repair.
            #
            # programStartDate cannot be recovered from the payload — it only
            # ever lived in the envelope that was overwritten — so it stays
            # null and the athlete re-dates the program.
            if 'currentProgram' not in program and program.get('weeks') is not None:
                app.logger.warning('healing envelope-less program for %s', user_id)
                ids, weights = _goal_ids_from_body({}, program)
                program = {
                    'currentProgram':    program,
                    'programStartDate':  None,
                    'eventDate':         None,
                    'sourceGoalIds':     ids,
                    'sourceGoalWeights': weights,
                }
                try:
                    save_user_program(user_id, program)
                except Exception as wrap_err:
                    app.logger.warning('envelope heal save failed: %s', wrap_err)

            # Heal programs saved by iOS (missing goal/volume_summary) by
            # reconstructing goal from sourceGoalIds and recomputing volume.
            current = program.get('currentProgram') or {}
            if current and 'goal' not in current:
                source_ids = program.get('sourceGoalIds') or []
                try:
                    all_frameworks = list(loader.load_all_frameworks().values())
                    if len(source_ids) == 1:
                        goal = _philosophy_to_goal(source_ids[0], all_frameworks)
                    elif len(source_ids) > 1:
                        weights = program.get('sourceGoalWeights') or {}
                        goal = _blend_philosophy_goals(source_ids, weights, all_frameworks)
                    else:
                        goal = None
                    if goal:
                        current['goal'] = goal
                    if 'volume_summary' not in current:
                        current['volume_summary'] = [
                            _week_volume(w) for w in current.get('weeks', [])
                        ]
                    program['currentProgram'] = current
                    # Persist the healed copy so next load is instant
                    try:
                        save_user_program(user_id, program)
                    except Exception:
                        pass
                except Exception as heal_err:
                    app.logger.warning('program heal error: %s', heal_err)
        if isinstance(program, dict):
            from src.db import get_program_revision
            program['revision'] = get_program_revision(user_id)
        return jsonify(program)
    except Exception as e:
        app.logger.warning('get_user_program error: %s', e)
        return jsonify(None)


def _normalize_program_keys(program: dict) -> dict:
    """Remap legacy snake_case top-level program keys to camelCase.

    Old iOS clients saved with snake_case CodingKeys, corrupting the stored
    payload. Both web (reads .currentProgram) and iOS (no CodingKeys on
    ServerProgram → expects camelCase) fail silently without this fix.
    """
    key_map = {
        'current_program':    'currentProgram',
        'program_start_date': 'programStartDate',
        'event_date':         'eventDate',
        'source_goal_ids':    'sourceGoalIds',
        'source_goal_weights': 'sourceGoalWeights',
    }
    return {key_map.get(k, k): v for k, v in program.items()}


@app.put('/api/user/program')
@require_auth
def save_user_program_endpoint():
    try:
        from src.db import get_user_program, save_user_program
        user_id = g.user_id
        body = request.get_json(silent=True) or {}

        # Optimistic concurrency.
        #
        # Every client previously blind-overwrote the whole program. iOS sends a
        # weeks-only payload (Swift Codable drops unknown keys), so a phone
        # holding a stale copy could replace a program generated on the web
        # minutes earlier, and the goal back-fill welded the new program's goal
        # onto the old program's weeks — exactly the state this account reached.
        #
        # A client that read revision R may only write while the stored revision
        # is still R. Anything else is rejected with 409 so the client re-pulls
        # instead of destroying newer work. `revision` is omitted by older
        # clients, which keep the previous (unchecked) behaviour.
        from src.db import get_program_revision
        base_rev = body.pop('baseRevision', None) or body.pop('revision', None)
        if base_rev is not None:
            current_rev = get_program_revision(user_id)
            if current_rev is not None and str(base_rev) != str(current_rev):
                app.logger.info('program save rejected: stale base %s != %s',
                                base_rev, current_rev)
                return jsonify({
                    'saved': False,
                    'detail': 'stale_revision',
                    'currentRevision': current_rev,
                }), 409

        # When the iOS app saves after move/replace, GeneratedProgram only contains
        # `weeks` (Swift Codable strips unknown fields on re-encode). Preserve the
        # goal, constraints, validation, and volume_summary from the existing stored
        # program so the web overview stays functional.
        #
        # But only when the program is still the SAME one. Copying the stored goal
        # forward unconditionally fossilised it: once iOS wrote back a program, the
        # old goal was carried across every later save, so a record could end up
        # with sourceGoalIds ['uphill_athlete'] and goal '_phil_horsemen_gpp'. When
        # the source goals change, the goal is re-derived instead of inherited.
        current = body.get('currentProgram') or {}
        if current and 'goal' not in current:
            existing = get_user_program(user_id) or {}
            existing = _normalize_program_keys(existing) if existing else {}
            existing_cp = existing.get('currentProgram') or {}

            new_ids = body.get('sourceGoalIds') or []
            old_ids = existing.get('sourceGoalIds') or []
            same_goal = (sorted(new_ids) == sorted(old_ids))

            for field in ('constraints', 'validation'):
                if field in existing_cp and field not in current:
                    current[field] = existing_cp[field]

            if same_goal and 'goal' in existing_cp:
                current['goal'] = existing_cp['goal']
            elif new_ids:
                # Source goals changed — rebuild rather than inherit a stale goal.
                try:
                    all_frameworks = list(loader.load_all_frameworks().values())
                    if len(new_ids) == 1:
                        current['goal'] = _philosophy_to_goal(new_ids[0], all_frameworks)
                    else:
                        weights = body.get('sourceGoalWeights') or {}
                        current['goal'] = _blend_philosophy_goals(new_ids, weights, all_frameworks)
                except Exception as goal_err:
                    app.logger.warning('goal rebuild error: %s', goal_err)

            # volume_summary describes THESE weeks, so recompute it rather than
            # inheriting a summary of a different program.
            if 'volume_summary' not in current:
                try:
                    current['volume_summary'] = [
                        _week_volume(w) for w in current.get('weeks', [])
                    ]
                except Exception:
                    if 'volume_summary' in existing_cp:
                        current['volume_summary'] = existing_cp['volume_summary']

            body['currentProgram'] = current

        save_user_program(user_id, body)
        return jsonify({'saved': True, 'revision': get_program_revision(user_id)})
    except Exception as e:
        app.logger.warning('save_user_program error: %s', e)
        return jsonify({'saved': False, 'detail': str(e)}), 503


# ---------------------------------------------------------------------------
# Watch device pairing (Garmin / future companions)
# ---------------------------------------------------------------------------
# A watch mints a pending pairing with no auth, shows the code (QR/text), then
# polls status until a signed-in user claims the code and binds the token.

@app.post('/api/devices/pair')
def devices_pair():
    """Unauthenticated: a watch requests a pairing code + device token."""
    from src import device_store
    body = request.get_json(silent=True) or {}
    result = device_store.create_pairing(device_name=body.get('deviceName'))
    return jsonify(result)


@app.post('/api/devices/claim')
@require_auth
def devices_claim():
    """Authenticated: the signed-in user binds a pairing code to their account."""
    from src import device_store
    body = request.get_json(silent=True) or {}
    code = body.get('code', '')
    ok = device_store.claim_pairing(code, g.user_id)
    if not ok:
        return jsonify({'claimed': False, 'detail': 'Invalid or expired code'}), 404
    return jsonify({'claimed': True})


@app.get('/api/devices/status')
def devices_status():
    """Unauthenticated poll target: the watch checks whether its token is claimed.

    The device token is supplied via `Authorization: Bearer <token>` or ?deviceToken=.
    """
    from src import device_store
    header = request.headers.get('Authorization', '')
    token = header.split(' ', 1)[1] if header.startswith('Bearer ') else request.args.get('deviceToken', '')
    if not token:
        return jsonify({'detail': 'Missing device token'}), 400
    status = device_store.pairing_status(token)
    if status is None:
        return jsonify({'detail': 'Unknown device token'}), 404
    return jsonify(status)


@app.get('/api/devices')
@require_auth
def devices_list():
    """List the signed-in user's claimed devices (token secrets are truncated)."""
    from src import device_store
    return jsonify(device_store.list_devices(g.user_id))


@app.delete('/api/devices/<path:device_token>')
@require_auth
def devices_revoke(device_token: str):
    from src import device_store
    ok = device_store.revoke_token(device_token, g.user_id)
    return jsonify({'revoked': ok}), (200 if ok else 404)


# ---------------------------------------------------------------------------
# Today's session (compact, watch-sized projection of the stored program)
# ---------------------------------------------------------------------------

# Fallback rest seconds by modality when a slot's rest_sec is null.
# Mirrors ios/.../WatchSessionManager.swift modalityRestDefaults.
_MODALITY_REST_DEFAULTS = {
    'max_strength': 240, 'relative_strength': 180, 'strength_endurance': 90,
    'power': 240, 'aerobic_base': 0, 'anaerobic_intervals': 120,
    'mixed_modal_conditioning': 60, 'mobility': 30, 'movement_skill': 30,
    'durability': 0, 'combat_sport': 0, 'rehab': 30,
}

_ZONE_RE = re.compile(r'[Zz]one\s*(\d)(?:\s*[-–]\s*(\d))?')


def _pick(d: dict, *keys):
    """First present value among snake_case / camelCase spellings."""
    for k in keys:
        if isinstance(d, dict) and d.get(k) is not None:
            return d[k]
    return None


def _infer_slot_type(load: dict, explicit) -> str:
    """Port of WatchSessionManager.inferSlotType for legacy programs missing slot_type."""
    if explicit:
        return explicit
    if _pick(load, 'distance_km', 'distanceKm') is not None:
        return 'distance'
    # Sub-500m carries (40m farmer carry, 20m bear crawl) keep distance_m rather
    # than distance_km. Without this they fell through to sets_reps and rendered
    # as "?x?" on the watch.
    if _pick(load, 'distance_m', 'distanceM') is not None:
        return 'distance'
    if _pick(load, 'hold_seconds', 'holdSeconds') is not None:
        return 'static_hold'
    if _pick(load, 'format') is not None:
        return 'emom'
    if _pick(load, 'duration_minutes', 'durationMinutes') is not None:
        return 'time_domain'
    if _pick(load, 'time_minutes', 'timeMinutes') is not None and \
       _pick(load, 'target_rounds', 'targetRounds') is not None:
        return 'amrap'
    if _pick(load, 'target_rounds', 'targetRounds') is not None:
        return 'for_time'
    return 'sets_reps'


def _parse_zone_range(zone_target):
    if not isinstance(zone_target, str):
        return None, None
    m = _ZONE_RE.search(zone_target)
    if not m:
        return None, None
    lower = int(m.group(1))
    upper = int(m.group(2)) if m.group(2) else lower
    return lower, upper


def _fmt_watch_load(slot_type: str, load: dict) -> str:
    sets = _pick(load, 'sets')
    reps = _pick(load, 'reps')
    reps_s = str(reps) if reps is not None else '?'
    if slot_type == 'sets_reps':
        s = str(sets) if sets is not None else '?'
        kg = _pick(load, 'weight_kg', 'weightKg', 'suggested_weight_kg', 'suggestedWeightKg')
        rpe = _pick(load, 'target_rpe', 'targetRpe')
        if kg is not None:
            return f'{s}×{reps_s} @ {kg} kg'
        if rpe is not None:
            return f'{s}×{reps_s} @ RPE {rpe}'
        return f'{s}×{reps_s}'
    if slot_type in ('time_domain', 'skill_practice'):
        mins = _pick(load, 'duration_minutes', 'durationMinutes')
        zt = _pick(load, 'zone_target', 'zoneTarget')
        if mins is not None:
            return f'{mins} min' + (f' — {zt}' if zt else '')
        return 'Duration TBD'
    if slot_type == 'emom':
        mins = _pick(load, 'time_minutes', 'timeMinutes')
        rounds = _pick(load, 'target_rounds', 'targetRounds')
        work = _pick(load, 'work_sec', 'workSec')
        rest = _pick(load, 'rest_sec', 'restSec')
        if rounds is not None and work:
            # e.g. "8 x 20s/10s" (Tabata) or "10 x 60s" (EMOM strength)
            span = f'{work}s/{rest}s' if rest else f'{work}s'
            return f'{rounds} x {span}'
        if mins is not None and rounds is not None:
            return f'{mins} min / {rounds} rounds'
        return _pick(load, 'format') or 'EMOM'
    if slot_type == 'amrap':
        mins = _pick(load, 'time_minutes', 'timeMinutes')
        return f'AMRAP {mins} min' if mins is not None else 'AMRAP'
    if slot_type == 'for_time':
        rounds = _pick(load, 'target_rounds', 'targetRounds')
        return f'{rounds} rounds for time' if rounds is not None else 'For time'
    if slot_type == 'distance':
        km = _pick(load, 'distance_km', 'distanceKm')
        if km is not None:
            pack = _pick(load, 'pack_load_kg', 'packLoadKg')
            return f'{km} km' + (f' @ {pack} kg' if pack is not None else '')
        m = _pick(load, 'distance_m', 'distanceM')
        if m is not None:
            sets = _pick(load, 'sets')
            return (f'{sets}x{m} m' if sets is not None else f'{m} m')
        return 'Distance'
    if slot_type == 'amrap_movement':
        rpr = _pick(load, 'reps_per_round', 'repsPerRound')
        return f'{rpr} reps / round' if rpr is not None else 'Per round'
    if slot_type == 'static_hold':
        secs = _pick(load, 'hold_seconds', 'holdSeconds')
        prefix = f'{sets}×' if sets is not None else ''
        return f'{prefix}{secs}s hold' if secs is not None else f'{prefix}hold'
    return ''


def _humanize_role(role: str) -> str:
    """'positional_sparring' -> 'Positional Sparring'. Names exercise-less blocks."""
    return (role or 'Block').replace('_', ' ').title()


def _encode_watch_exercise(ea: dict, modality: str) -> dict | None:
    """Project one exercise assignment into the compact watch shape.

    Slots flagged `skip_exercise` (BJJ drilling/rolling rounds, circuit round
    wrappers) resolve to no exercise at all. Returning None for those meant a
    whole bjj_class session arrived at the watch as an empty exercise list, so
    they are projected as named meta blocks instead.
    """
    ex = ea.get('exercise')
    if ea.get('injury_skip') or ea.get('injurySkip'):
        return None
    is_meta = bool(ea.get('meta')) or bool(_pick(ea, 'skip_exercise', 'skipExercise'))
    if not ex and not is_meta:
        return None
    ex = ex or {}

    load = ea.get('load') or {}
    slot_type = _infer_slot_type(load, _pick(ea, 'slot_type', 'slotType'))
    zone_target = _pick(load, 'zone_target', 'zoneTarget')
    # Prefer the structured bounds the engine now emits; fall back to parsing the
    # label for programs generated before that change.
    zlo = _pick(load, 'zone_lower', 'zoneLower')
    zhi = _pick(load, 'zone_upper', 'zoneUpper')
    if zlo is None:
        zlo, zhi = _parse_zone_range(zone_target)
    rest = _pick(ea, 'rest_sec', 'restSec')
    if rest is None:
        rest = _MODALITY_REST_DEFAULTS.get(modality)
    reps = _pick(load, 'reps')
    slot_role = _pick(ea, 'slot_role', 'slotRole') or ''
    patterns = ex.get('movement_patterns') or []

    return {
        'exerciseId': ex.get('id'),
        'name': ex.get('name') or _humanize_role(slot_role),
        'slotType': slot_type,
        'slotRole': slot_role,
        'isMeta': is_meta,
        'loadDescription': _fmt_watch_load(slot_type, load),
        'loadNote': _pick(ea, 'load_note', 'loadNote'),
        'coachingCue': _pick(ea, 'notes') or ex.get('notes'),
        # Identity — drives the movement-pattern icon and side alternation.
        'category': ex.get('category'),
        'movementPattern': patterns[0] if patterns else None,
        'bilateral': ex.get('bilateral'),
        'sets': _pick(load, 'sets'),
        'reps': str(reps) if reps is not None else None,
        'weightKg': _pick(load, 'weight_kg', 'weightKg', 'suggested_weight_kg', 'suggestedWeightKg'),
        'targetRpe': _pick(load, 'target_rpe', 'targetRpe'),
        'rir': _pick(load, 'rir'),
        'durationMinutes': _pick(load, 'duration_minutes', 'durationMinutes'),
        'zoneTarget': zone_target,
        'timeMinutes': _pick(load, 'time_minutes', 'timeMinutes'),
        'targetRounds': _pick(load, 'target_rounds', 'targetRounds'),
        'emomFormat': _pick(load, 'format'),
        # Real interval structure — Tabata's 20s/10s, EMOM's 60s window.
        'workSec': _pick(load, 'work_sec', 'workSec'),
        'intervalRestSec': _pick(load, 'rest_sec', 'restSec'),
        'holdSeconds': _pick(load, 'hold_seconds', 'holdSeconds'),
        'distanceKm': _pick(load, 'distance_km', 'distanceKm'),
        'distanceM': _pick(load, 'distance_m', 'distanceM'),
        'repsPerRound': _pick(load, 'reps_per_round', 'repsPerRound'),
        'packLoadKg': _pick(load, 'pack_load_kg', 'packLoadKg'),
        'focus': _pick(load, 'focus'),
        'parentSlotRole': _pick(ea, 'parent_slot_role', 'parentSlotRole'),
        'restSeconds': rest,
        'prescribedZoneLower': zlo,
        'prescribedZoneUpper': zhi,
    }


@app.get('/api/user/today-session')
@require_auth
def get_today_session():
    """Compact projection of today's scheduled session(s) for the watch companion.

    Server-side port of ios/.../WatchSessionManager.syncProgram(): derives the
    current week + weekday from programStartDate and returns only the fields the
    slot-type views need. Accepts optional ?date=YYYY-MM-DD for testing.
    """
    from src.db import get_user_program
    program = get_user_program(g.user_id)
    if not isinstance(program, dict):
        return jsonify({'status': 'no_program'})
    program = _normalize_program_keys(program)
    current = program.get('currentProgram') or {}
    start_str = program.get('programStartDate')
    weeks = current.get('weeks') or []
    if not start_str or not weeks:
        return jsonify({'status': 'no_program'})

    date_str = request.args.get('date')
    try:
        today = _date.fromisoformat(date_str) if date_str else _date.today()
        start = _date.fromisoformat(str(start_str)[:10])
    except ValueError:
        return jsonify({'status': 'no_program'})

    days_since = (today - start).days
    if days_since < 0:
        return jsonify({'status': 'not_started', 'startsOn': str(start)})
    week_index = days_since // 7
    day_name = _DAY_NAMES[today.weekday()]
    if week_index >= len(weeks):
        return jsonify({'status': 'program_expired'})

    week = weeks[week_index]
    schedule = week.get('schedule') or {}
    sessions = schedule.get(day_name) or []

    out_sessions = []
    for i, s in enumerate(sessions):
        modality = s.get('modality') or ''
        archetype = s.get('archetype') or {}
        exercises = [
            e for e in (
                _encode_watch_exercise(ea, modality) for ea in (s.get('exercises') or [])
            ) if e is not None
        ]
        out_sessions.append({
            'sessionId': f"{_pick(week, 'week_number', 'weekNumber')}-{day_name}-{i}",
            'modalityId': modality,
            # Archetype identity drives the client's per-archetype behavior table
            # (TGU side alternation, Tabata work/rest, BJJ round names, ...) and
            # the category icon. Previously only the display name was sent.
            'archetypeId': archetype.get('id'),
            'archetypeName': archetype.get('name') or modality,
            'archetypeCategory': archetype.get('category'),
            'estimatedMinutes': _pick(archetype, 'duration_estimate_minutes', 'durationEstimateMinutes') or 45,
            'isDeload': bool(_pick(s, 'is_deload', 'isDeload')),
            'exercises': exercises,
        })

    try:
        readiness = _compute_readiness(
            _health.get_recent_bio_logs(g.user_id, days=14),
            _health.get_session_logs(g.user_id),
            user_id=g.user_id,
        )
    except Exception:
        readiness = None

    return jsonify({
        'status': 'ok',
        'date': str(today),
        # Position in the program, not the stored absolute week_number.
        # programStartDate anchors weeks[0] as week 1, so a program whose weeks
        # are numbered 16..31 (the tail of an earlier plan) was reporting
        # "week 16" on its first day. absoluteWeekNumber keeps the stored value
        # for anything that genuinely wants it.
        'weekNumber': week_index + 1,
        'totalWeeks': len(weeks),
        'absoluteWeekNumber': _pick(week, 'week_number', 'weekNumber'),
        'phase': week.get('phase'),
        'dayName': day_name,
        'isRestDay': len(out_sessions) == 0,
        'readiness': readiness,
        'sessions': out_sessions,
    })


# ---------------------------------------------------------------------------
# Health data storage
# ---------------------------------------------------------------------------

from src import health_store as _health


@app.get('/api/health/snapshot')
@require_auth
def health_snapshot():
    return jsonify({
        'workouts':        _health.get_workouts(g.user_id, summary_only=True),
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

    # `autoMatch` marks an automatic import (the iOS Apple Health relay) rather
    # than an interactive one. Those need the server-side matcher, because the
    # client doing the importing has no matcher of its own and there may be no
    # browser open at all.
    auto_match = bool(body.get('autoMatch'))

    # An automatic import also respects the athlete's settings — enforcing this
    # only in the UI would leave the toggle decorative.
    if auto_match:
        sources = {w.get('source') for w in workouts if isinstance(w, dict)}
        # Apple Health is the relay's own channel; a Garmin-written workout
        # arriving through it is gated on the Garmin toggle, as the athlete
        # would expect from the label.
        allowed = {
            s for s in sources
            if integration_allows(g.user_id, 'garmin' if s == 'garmin' else 'appleHealth')
        }
        workouts = [w for w in workouts if w.get('source') in allowed]
        if not workouts:
            return jsonify({'saved': 0, 'skipped': 'auto-import disabled'})

    # Enrich elevation from GPS track altitude when the client only sent gain (loss=0).
    # Apple Watch live workouts always arrive with loss=0; recalculate from track altitude.
    for workout in workouts:
        gps = workout.get('gpsTrack') or []
        elev = workout.get('elevation') or {}
        if any(p.get('altitude') is not None for p in gps) and elev.get('loss', 0) == 0:
            gain, loss = _calc_elevation(gps)
            if gain or loss:
                workout['elevation'] = {'gain': round(gain), 'loss': round(loss)}

    _health.upsert_workouts(g.user_id, workouts)

    result = {'saved': len(workouts)}
    if auto_match:
        from src import workout_matcher
        result['matched'] = workout_matcher.match_and_store(g.user_id, workouts)
    return jsonify(result)


@app.delete('/api/health/workouts/<workout_id>')
@require_auth
def health_delete_workout(workout_id: str):
    _health.delete_workout(g.user_id, workout_id)
    return jsonify({'deleted': workout_id})


@app.get('/api/health/sessions/recent')
@require_auth
def health_recent_sessions():
    return jsonify(_health.get_recent_session_logs(g.user_id))


@app.get('/api/health/bio/recent')
@require_auth
def health_recent_bio():
    return jsonify(_health.get_recent_bio_logs(g.user_id))


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
    workout_id = match.get('importedWorkoutId')
    _health.upsert_match(g.user_id, match)
    # Deciding a workout — either way — answers any outstanding suggestion.
    if workout_id:
        _health.delete_match_suggestion(g.user_id, workout_id)
    return jsonify({'saved': workout_id})


@app.get('/api/health/matches/suggestions')
@require_auth
def health_match_suggestions():
    """Workouts the server matched too weakly to confirm on its own.

    Populated by the automatic import paths (Garmin webhook, iOS Apple Health),
    which run server-side where there is no browser to ask. The web app merges
    these into its existing pending-match flow so the athlete confirms or
    rejects them the same way as an upload made in the browser.
    """
    return jsonify(_health.get_match_suggestions(g.user_id))


@app.delete('/api/health/matches/suggestions/<path:workout_id>')
@require_auth
def health_dismiss_suggestion(workout_id: str):
    _health.delete_match_suggestion(g.user_id, workout_id)
    return jsonify({'dismissed': workout_id})


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


# ---------------------------------------------------------------------------
# Readiness computation
# ---------------------------------------------------------------------------

def _recent_bio(bio_list: list[dict], days: int) -> list[dict]:
    cutoff = _date.today() - _timedelta(days=days)
    return [b for b in bio_list if _date.fromisoformat(b['date']) > cutoff]


def _rolling_mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else 0.0


def _score_rhr(bio_list: list[dict], flags: list[str]) -> int:
    logs = [b for b in _recent_bio(bio_list, 14) if b.get('resting_hr') is not None]
    if len(logs) < 3:
        flags.append('insufficient_data')
        return 17
    logs = sorted(logs, key=lambda b: b['date'])
    baseline = _rolling_mean([b['resting_hr'] for b in logs[:-1]])
    today_val = logs[-1]['resting_hr']
    delta = today_val - baseline
    last5 = logs[-5:]
    if sum(1 for b in last5 if b['resting_hr'] - baseline > 5) >= 3:
        flags.append('elevated_rhr_3d')
    if delta <= 0: return 35
    if delta <= 3: return round(35 - (delta / 3) * 9)
    if delta <= 7: return round(26 - ((delta - 3) / 4) * 13)
    return max(0, round(13 - (delta - 7) * 2))


def _score_hrv(bio_list: list[dict], flags: list[str]) -> int:
    logs = [b for b in _recent_bio(bio_list, 14) if b.get('hrv') is not None]
    if len(logs) < 3:
        if 'insufficient_data' not in flags:
            flags.append('insufficient_data')
        return 17
    logs = sorted(logs, key=lambda b: b['date'])
    baseline = _rolling_mean([b['hrv'] for b in logs[:-1]])
    today_val = logs[-1]['hrv']
    pct = ((today_val - baseline) / baseline * 100) if baseline > 0 else 0
    last5 = logs[-5:]
    if sum(1 for b in last5 if b['hrv'] < baseline * 0.85) >= 3:
        flags.append('suppressed_hrv_3d')
    if pct >= 5:  return 35
    if pct >= -5: return 30
    if pct >= -10: return 21
    if pct >= -20: return 13
    return 4


def _score_sleep(bio_list: list[dict], flags: list[str]) -> int:
    logs = [b for b in _recent_bio(bio_list, 7) if b.get('sleep_duration_min') is not None]
    if not logs:
        return 8
    logs = sorted(logs, key=lambda b: b['date'])
    hours = logs[-1]['sleep_duration_min'] / 60
    if sum(1 for b in logs[-3:] if b['sleep_duration_min'] / 60 < 6) >= 3:
        flags.append('poor_sleep_3d')
    if hours < 5:
        flags.append('insufficient_sleep')
        return 0
    if hours < 6: return 5
    if hours < 7: return 10
    if hours <= 9: return 15
    return 12


def _score_fatigue(session_dict: dict, flags: list[str]) -> int:
    logs = sorted(
        [v for v in session_dict.values()
         if v.get('completedAt') and v.get('fatigueRating') is not None],
        key=lambda l: l['completedAt'],
    )[-3:]
    if not logs:
        return 8
    avg = _rolling_mean([l['fatigueRating'] for l in logs])
    if avg > 4.5:
        flags.append('high_accumulated_fatigue')
        return 1
    if avg > 3.5: return 4
    if avg > 2.5: return 8
    if avg > 1.5: return 12
    return 15


def _compute_readiness(bio_list: list[dict], session_dict: dict, user_id: str | None = None) -> dict:
    flags: list[str] = []
    rhr     = _score_rhr(bio_list, flags)
    hrv     = _score_hrv(bio_list, flags)
    sleep   = _score_sleep(bio_list, flags)      # capped at 10 (was 15)
    fatigue = _score_fatigue(session_dict, flags)  # capped at 10 (was 15)
    tsb     = _score_tsb(user_id, flags) if user_id else 5
    # Rebalance sleep and fatigue to cap at 10 each (original scoring goes to 15/15;
    # clamp here so total remains 100: rhr(35) + hrv(35) + sleep(10) + fatigue(10) + tsb(10)
    sleep   = min(sleep, 10)
    fatigue = min(fatigue, 10)
    score = min(100, max(0, rhr + hrv + sleep + fatigue + tsb))
    status = 'green' if score >= 70 else 'yellow' if score >= 45 else 'red'
    return {
        'score':      score,
        'status':     status,
        'flags':      flags,
        'components': {'rhr': rhr, 'hrv': hrv, 'sleep': sleep, 'fatigue': fatigue, 'tsb': tsb},
    }


@app.get('/api/health/readiness')
@require_auth
def health_readiness():
    bio_list     = _health.get_recent_bio_logs(g.user_id, days=14)
    session_dict = _health.get_session_logs(g.user_id)
    return jsonify(_compute_readiness(bio_list, session_dict, user_id=g.user_id))


# ---------------------------------------------------------------------------
# Training Load helpers (shared by /load/weekly and /load/pmc)
# ---------------------------------------------------------------------------

_BANISTER_WEIGHTS = [1.0, 1.5, 2.0, 3.0, 4.5]
_DEFAULT_ZONE_BOUNDARIES = [0.60, 0.70, 0.80, 0.90]


def _get_user_max_hr(user_id: str) -> int:
    """Return user's max HR from hrConfig override, or 190 as default."""
    try:
        from src.db import get_user_profile
        profile = get_user_profile(user_id) or {}
        hr_config = profile.get('hrConfig') or {}
        override = hr_config.get('maxHROverride')
        if override and int(override) > 0:
            return int(override)
    except Exception:
        pass
    return 190


def _calc_workout_trimp(workout: dict, max_hr: int = 190) -> float:
    """Compute TRIMP for a single workout using Banister zone-minute weights."""
    from statistics import median as _median

    duration_min = workout.get('durationMinutes') or 0
    if duration_min <= 0:
        return 0.0

    hr_data = workout.get('heartRate') or {}
    samples = hr_data.get('samples') or []
    boundaries = _DEFAULT_ZONE_BOUNDARIES

    def _assign_zone(bpm: float) -> int:
        pct = bpm / max_hr
        for i, b in enumerate(boundaries):
            if pct < b:
                return i
        return 4

    if len(samples) >= 2:
        try:
            sorted_samples = sorted(samples, key=lambda s: s['timestamp'])
            zone_times = [0.0] * 5
            total = 0.0
            for i in range(len(sorted_samples) - 1):
                from datetime import datetime, timezone as _tz
                tA = datetime.fromisoformat(sorted_samples[i]['timestamp'].replace('Z', '+00:00')).timestamp()
                tB = datetime.fromisoformat(sorted_samples[i + 1]['timestamp'].replace('Z', '+00:00')).timestamp()
                interval = min((tB - tA), 60.0)
                if interval <= 0:
                    continue
                z = _assign_zone(sorted_samples[i]['bpm'])
                zone_times[z] += interval
                total += interval
            if total > 0:
                zone_pcts = [t / total for t in zone_times]
                return sum(pct * duration_min * _BANISTER_WEIGHTS[i] for i, pct in enumerate(zone_pcts))
        except Exception:
            pass

    # Fallback: normal distribution estimate from avg/max HR
    avg_hr = hr_data.get('avg')
    max_hr_sample = hr_data.get('max')
    if avg_hr:
        import math as _math
        std = max((max_hr_sample or max_hr) - avg_hr, 1) / 2.5

        def _norm_cdf(x: float, mean: float, sigma: float) -> float:
            return 0.5 * (1.0 + _math.erf((x - mean) / (sigma * _math.sqrt(2))))

        bpm_bounds = [0.0] + [b * max_hr for b in boundaries] + [float('inf')]
        zone_pcts = []
        for i in range(5):
            lo, hi = bpm_bounds[i], bpm_bounds[i + 1]
            p_lo = 0.0 if lo == 0 else _norm_cdf(lo, avg_hr, std)
            p_hi = 1.0 if hi == float('inf') else _norm_cdf(hi, avg_hr, std)
            zone_pcts.append(max(0.0, p_hi - p_lo))
        total = sum(zone_pcts) or 1.0
        zone_pcts = [p / total for p in zone_pcts]
        return sum(pct * duration_min * _BANISTER_WEIGHTS[i] for i, pct in enumerate(zone_pcts))

    return 0.0


def _compute_pmc(workouts: list, max_hr: int, days: int = 90) -> list[dict]:
    """Compute CTL/ATL/TSB Performance Management Chart data."""
    import math as _math
    from datetime import date as _date, timedelta as _td

    k_atl = 1 - _math.exp(-1 / 7)
    k_ctl = 1 - _math.exp(-1 / 42)

    # Build daily TRIMP totals
    daily_trimp: dict[str, float] = {}
    for w in workouts:
        d = str(w.get('date', ''))[:10]
        if d:
            daily_trimp[d] = daily_trimp.get(d, 0.0) + _calc_workout_trimp(w, max_hr)

    today = _date.today()
    start = today - _td(days=days - 1)

    ctl = 0.0
    atl = 0.0
    result = []
    for i in range(days):
        d = start + _td(days=i)
        d_str = d.isoformat()
        tsb = round(ctl - atl, 1)  # form entering today = yesterday's CTL - ATL
        trimp = daily_trimp.get(d_str, 0.0)
        atl = atl + (trimp - atl) * k_atl
        ctl = ctl + (trimp - ctl) * k_ctl
        result.append({
            'date':  d_str,
            'ctl':   round(ctl, 1),
            'atl':   round(atl, 1),
            'tsb':   tsb,
            'trimp': round(trimp, 1),
        })
    return result


# ---------------------------------------------------------------------------
# Training Load endpoints
# ---------------------------------------------------------------------------

@app.get('/api/health/load/weekly')
@require_auth
def health_load_weekly():
    from collections import defaultdict
    from datetime import date as _date, timedelta as _td

    workouts = _health.get_workouts(g.user_id)
    max_hr = _get_user_max_hr(g.user_id)
    cutoff = _date.today() - _td(weeks=12)

    weeks: dict = defaultdict(lambda: {'trimp': 0.0, 'sessions': 0})
    for w in workouts:
        try:
            wo_date = _date.fromisoformat(str(w['date'])[:10])
        except Exception:
            continue
        if wo_date < cutoff:
            continue
        iso_cal = wo_date.isocalendar()
        week_key = f'{iso_cal[0]}-W{iso_cal[1]:02d}'
        weeks[week_key]['trimp'] += _calc_workout_trimp(w, max_hr)
        weeks[week_key]['sessions'] += 1

    result = [
        {'week': k, 'trimp': round(v['trimp']), 'sessions': v['sessions']}
        for k, v in sorted(weeks.items())
    ]
    return jsonify(result)


@app.get('/api/health/load/pmc')
@require_auth
def health_load_pmc():
    workouts = _health.get_workouts(g.user_id)
    max_hr = _get_user_max_hr(g.user_id)
    return jsonify(_compute_pmc(workouts, max_hr, days=90))


# ---------------------------------------------------------------------------
# TSB component for readiness score
# ---------------------------------------------------------------------------

def _score_tsb(user_id: str, flags: list[str]) -> int:
    """Score Training Stress Balance (form) as a readiness component (0–10 pts)."""
    try:
        workouts = _health.get_workouts(user_id)
        max_hr = _get_user_max_hr(user_id)
        pmc = _compute_pmc(workouts, max_hr, days=14)
        if not pmc:
            return 5
        latest = pmc[-1]
        tsb = latest['tsb']
        if tsb < -20:
            flags.append('overreached')
            return 0
        if tsb < -10: return 4
        if tsb < 0:   return 7
        if tsb <= 10: return 10
        return 8  # very positive TSB → fresh but possibly detrained
    except Exception:
        return 5


@app.errorhandler(Exception)
def handle_error(e):
    import traceback as _tb
    msg = _tb.format_exc()
    err_path = os.path.join(os.path.dirname(__file__), 'data', 'api_errors.txt')
    with open(err_path, 'a') as _f:
        _f.write(msg + '\n---\n')
    app.logger.exception(e)
    return jsonify({'detail': str(e)}), 500


# ---------------------------------------------------------------------------
# Progression endpoints
# ---------------------------------------------------------------------------

from src import progression_tracker as _pt
from src import db as _db


@app.get('/api/progression/review')
@require_auth
def progression_review():
    period = request.args.get('period', 'weekly')
    if period not in ('weekly', 'biweekly'):
        period = 'weekly'

    session_logs = _health.get_session_logs(g.user_id)
    bio_logs     = _health.get_recent_bio_logs(g.user_id, days=42)
    program_data = _db.get_user_program(g.user_id)

    if not program_data:
        return jsonify({
            'period_key':        _pt._current_period_key(period),
            'period_type':       period,
            'generated_at':      None,
            'overall_score':     None,
            'readiness_trend':   'stable',
            'avg_readiness':     None,
            'compliance_pct':    0,
            'exercise_findings': [],
            'flags':             ['no_program'],
            'recommendations':   ['Generate a training program first.'],
            'adjustments':       [],
        })

    # Check snapshot cache
    period_key   = _pt._current_period_key(period)
    session_hash = _pt.compute_session_hash(session_logs)
    cached = _health.get_progression_snapshot(g.user_id, period_key, period)
    if cached and cached.get('session_hash') == session_hash:
        return jsonify(cached['data'])

    # Compute fresh
    # program_data may be the full GeneratedProgram or wrapped {currentProgram: ...}
    program = program_data.get('currentProgram') or program_data
    review = _pt.compute_progression_review(
        user_id=g.user_id,
        program=program,
        bio_logs=bio_logs,
        session_logs=session_logs,
        period=period,
    )

    _health.save_progression_snapshot(g.user_id, period_key, period, session_hash, review)
    return jsonify(review)


@app.get('/api/progression/exercises')
@require_auth
def progression_exercises():
    program_data = _db.get_user_program(g.user_id)
    if not program_data:
        return jsonify({'exercises': []})

    program      = program_data.get('currentProgram') or program_data
    session_logs = _health.get_session_logs(g.user_id)
    ex_filter    = request.args.get('exercise_id')

    constraints = program.get('constraints', {})
    level       = constraints.get('training_level', 'intermediate')
    prog_model  = _pt._infer_progression_model(program)
    weeks       = program.get('weeks', [])

    # Build matched-workout list for endurance exercise auto-population
    matches    = _health.get_matches(g.user_id)
    workouts   = _health.get_workouts(g.user_id)
    wo_map     = {wo['id']: wo for wo in workouts}
    matched_wos = [
        {'sessionKey': m['sessionKey'], 'workout': wo_map[m['importedWorkoutId']]}
        for m in matches
        if m['matchConfidence'] != 'rejected' and m['importedWorkoutId'] in wo_map
    ]

    history = _pt.compute_exercise_history(session_logs, program, matched_workouts=matched_wos)

    # Build index: exerciseId → (exercise dict, slot dict)
    ex_index: dict = {}
    for w in weeks:
        for day_sessions in w.get('schedule', {}).values():
            for session in day_sessions:
                for ea in session.get('exercises', []):
                    if ea.get('meta') or ea.get('injury_skip'):
                        continue
                    ex = ea.get('exercise') or {}
                    ex_id = ex.get('id', '')
                    if ex_id and ex_id not in ex_index:
                        ex_index[ex_id] = (ex, ea.get('slot') or {})

    result = []
    for ex_id, (ex, slot) in ex_index.items():
        if ex_filter and ex_id != ex_filter:
            continue
        trajectory = _pt.compute_expected_trajectory(
            exercise=ex, slot=slot, progression_model=prog_model,
            philosophy_weights=program.get('philosophy_weights') or {},
            weeks=weeks, level=level,
        )
        result.append({
            'exerciseId': ex_id,
            'name':       ex.get('name', ex_id),
            'history':    history.get(ex_id, []),
            'expected':   trajectory,
        })

    return jsonify({'exercises': result})


@app.get('/api/progression/history')
@require_auth
def progression_history():
    snapshots = _health.list_progression_snapshots(g.user_id)
    return jsonify(snapshots)


@app.get('/api/progression/sessions')
@require_auth
def progression_sessions():
    program_data = _db.get_user_program(g.user_id)
    if not program_data:
        return jsonify([])
    program  = program_data.get('currentProgram') or program_data
    matches  = [m for m in _health.get_matches(g.user_id) if m['matchConfidence'] != 'rejected']
    workouts = _health.get_workouts(g.user_id)
    wo_map   = {wo['id']: wo for wo in workouts}
    return jsonify(_pt.compute_matched_sessions(matches, wo_map, program))


if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8000))
    print(f'Training API running on http://localhost:{port}/api')
    app.run(host='0.0.0.0', port=port, debug=True)
