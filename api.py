"""Flask REST API — bridges the frontend to the Python training engine."""
from __future__ import annotations

import glob
import json
import os
import re
import sys
import tempfile
import threading
from datetime import date as _date, datetime as _datetime, timedelta as _timedelta, timezone as _timezone

import yaml
from dotenv import load_dotenv
load_dotenv()
# .env holds the production-shaped config (op inject < .env.template);
# .env.local, when present, layers local-dev values over it — local
# Postgres, no Supabase (auth bypass), FRONTEND_URL=localhost:5173.
# Same convention as Vite's frontend/.env.local. Neither is committed.
load_dotenv('.env.local', override=True)
from flask import Flask, jsonify, redirect, request

# Ensure src/ is importable when running from repo root
sys.path.insert(0, os.path.dirname(__file__))

from src import fit_import as _fit_import
from src import workout_ids as _workout_ids
from src import watch_spec as _watch_spec
from src import standards as _standards_mod
from src.analytics import benchmarks_data as _bd
from src import goals, loader, provenance
from src import blockers as _blockers
from src import phases
from src.phases import PhaseResolutionError
from src.similarity import compute_all_similarities
from src.generator import generate
from src.phase_calendar import compute_phase_from_date
from src.progression import calculate_load
from src.training_contract import ContractError
from src.selector import populate_session
from src.validator import check_level_coverage, validate
from src.auth import require_auth
from flask import g

app = Flask(__name__)
app.json.sort_keys = False   # preserve insertion order (days Mon→Sun)


def _authoring_enabled() -> bool:
    """Whether the six ontology authoring routes may write.

    They append to and patch the YAML under data/ in the running process. They
    are on when AUTHORING_ENABLED is set, and in local development — no
    SUPABASE_URL means src.auth bypasses JWTs and every request is
    'local-dev-user', which is the only place in-app authoring (Dev Lab) is
    meant to run. Production leaves both unset and answers 403.
    """
    if os.environ.get('AUTHORING_ENABLED', '').strip().lower() in ('1', 'true', 'yes', 'on'):
        return True
    return not os.environ.get('SUPABASE_URL')


_SCHEMA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'docs', 'schemas')


def _schema_errors(kind: str, obj: dict) -> list[str]:
    """Validate an authored entity against docs/schemas/<kind>.schema.json —
    the contract tools/validate_entities.py enforces on the YAML, applied to
    the API before it writes. Returns human-readable error lines."""
    import jsonschema
    with open(os.path.join(_SCHEMA_DIR, f'{kind}.schema.json'), encoding='utf-8') as fh:
        schema = json.load(fh)
    validator = jsonschema.validators.validator_for(schema)(schema)
    errors = sorted(validator.iter_errors(obj), key=lambda e: list(e.absolute_path))
    return [f"{'/'.join(str(p) for p in e.absolute_path) or '<root>'}: {e.message}" for e in errors]


def _invalid(kind: str, errors: list[str]):
    return jsonify({'detail': f'{kind} does not match docs/schemas/{kind}.schema.json',
                    'errors': errors}), 422


def _is_custom_package_path(path: str) -> bool:
    """Only the `custom` package is the API's to delete from; authored packages
    are edited as YAML and validated with the CLI."""
    return os.path.join('packages', 'custom') in os.path.normpath(path)


def require_authoring(f):
    """Gate for the authoring routes. Stack it under require_auth so an
    unauthenticated caller gets 401 before a disabled server gets 403."""
    from functools import wraps

    @wraps(f)
    def wrapper(*args, **kwargs):
        if not _authoring_enabled():
            return jsonify({'detail': 'authoring is disabled on this server'}), 403
        return f(*args, **kwargs)
    return wrapper

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


# A client that stops reading (a phone suspended mid-download) used to hold the
# only worker in sendall until gunicorn killed it at --timeout, 120 s later,
# with every other request — the watch's sync included — queued behind it. A
# send that makes no progress for this long now fails and frees the thread.
_SEND_TIMEOUT_S = 30


@app.before_request
def _bound_send():
    sock = request.environ.get('gunicorn.socket')
    if sock is None:
        return None
    try:
        import socket as _socket
        import struct as _struct
        sock.setsockopt(_socket.SOL_SOCKET, _socket.SO_SNDTIMEO,
                        _struct.pack('ll', _SEND_TIMEOUT_S, 0))
    except (OSError, AttributeError):
        pass
    return None


# The program envelope and the health snapshot run to megabytes of JSON; gzip
# shrinks them about tenfold, so they leave the socket before a stalling client
# can hold the thread. Never for a watch: whether Garmin's phone bridge
# decodes gzip for a Connect IQ request is not documented, and its payloads
# are small.
_GZIP_MIN_BYTES = 2048


@app.after_request
def _gzip(response):
    if (response.direct_passthrough or response.is_streamed
            or response.status_code < 200 or response.status_code >= 300
            or response.mimetype != 'application/json'
            or 'Content-Encoding' in response.headers
            or 'gzip' not in request.headers.get('Accept-Encoding', '').lower()
            or request.headers.get('Authorization', '').startswith('Bearer ciqdev_')):
        return response
    body = response.get_data()
    if len(body) < _GZIP_MIN_BYTES:
        return response
    import gzip as _gzip_mod
    response.set_data(_gzip_mod.compress(body, compresslevel=5))
    response.headers['Content-Encoding'] = 'gzip'
    response.headers['Content-Length'] = str(len(response.get_data()))
    response.vary.add('Accept-Encoding')
    return response

_DAY_NAMES = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
_DATA_DIR = os.path.join(os.path.dirname(__file__), 'data')


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _load_yaml(path: str) -> dict:
    with open(path, encoding='utf-8') as f:
        return yaml.safe_load(f)


_EXERCISE_LIST_KEYS = ('modality', 'equipment', 'movement_patterns', 'requires', 'unlocks',
                       'contraindicated_with', 'sources')


def _all_exercises() -> list[dict]:
    global_index, _ = loader.load_all_exercises()
    media = loader.load_exercise_media()
    result = []
    for ex in global_index.values():
        ex = dict(ex)
        if isinstance(ex.get('sources'), str):
            ex['sources'] = [ex['sources']]
        # The clients read these as always present; 155 exercises (most of
        # Horsemen's named-workout movements) declare no progressions, and the
        # web's Explore crashed on Object.keys(null).
        for key in _EXERCISE_LIST_KEYS:
            if ex.get(key) is None:
                ex[key] = []
        if ex.get('progressions') is None:
            ex['progressions'] = {}
        if ex['id'] in media:
            ex.update(media[ex['id']])
        result.append(ex)
    return sorted(result, key=lambda e: e.get('id', ''))


def _all_modalities() -> list[dict]:
    return sorted(loader.load_all_modalities().values(), key=lambda m: m.get('id', ''))


def _equipment_profiles() -> list[dict]:
    return loader.load_equipment_profiles()


# Similarity cache — computed once at first request (lazy, not blocking startup),
# by one thread: the four serving threads would otherwise each build it.
_similarity_cache: dict | None = None
_similarity_lock = threading.Lock()

def _get_similarity() -> dict:
    global _similarity_cache
    with _similarity_lock:
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


# Bumped when a cached analytics document's *shape* changes, so a snapshot
# written by the previous code (missing the new keys) is recomputed once
# instead of being served until its inputs happen to change.
_ANALYTICS_SHAPE = 'card-details-1'


def _standards_digest_key(performance: dict) -> list:
    from src.standards import digest_key
    return digest_key(performance)


def _all_benchmarks(sex: str = 'male') -> list[dict]:
    """Every standard in the client shape — now with the fields it never got.

    Delegates to src/analytics/benchmarks_data.py, which keeps `sources`,
    `goal_relevance`, `domain`, `metric_type` and the female values that this
    used to drop. `sources` is the only authored link from a standard to a
    philosophy, and program analytics is built on it.
    """
    from src.analytics import benchmarks_data as _bd
    return [_bd.to_client(b, sex) for b in _bd.load_benchmarks()]


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
        'equipment_gap': bool(ea.get('equipment_gap')),
        'gap_reason':   ea.get('gap_reason'),
        # What emptied the slot, named: {cause, exercise, needs | flags |
        # requires} (selector._explain_unfilled); absent on a filled slot.
        **({'blocked_by': ea['blocked_by']} if ea.get('blocked_by') else {}),
        'substituted_for': ea.get('substituted_for'),
        # The injury flag whose `modified_exercises` gave the substitute.
        **({'substituted_by_flag': ea['substituted_by_flag']} if ea.get('substituted_by_flag') else {}),
        'error':       ea.get('error'),
        'load_note':   load_note,
        'notes':       slot.get('notes'),
        # Links an amrap_movement component to the amrap slot it belongs to.
        # Without it these render as separate sequential exercises instead of
        # as the movements of one AMRAP.
        'parent_slot_role': slot.get('parent_slot_role'),
        'skip_exercise':    bool(slot.get('skip_exercise')),
        # The standard this slot measures ({id, result}), when it is a test's
        # scored slot (src/standard_tests.py); absent otherwise.
        **({'standard': ea['standard']} if ea.get('standard') else {}),
    }


def _phase_summary(weeks: list, goal: dict | None) -> list:
    """How sessions and exercises change phase to phase (src/phase_summary.py).

    Derived from the weeks, never stored (db.save_user_program strips it),
    and never allowed to fail a response.
    """
    from src import phase_summary
    try:
        return phase_summary.build(weeks, goal)
    except Exception as err:  # a malformed legacy program must still load
        app.logger.warning('phase_summary failed: %s', err)
        return []


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
                    **({'modules': session['modules']} if session.get('modules') else {}),
                    'provenance': session.get('provenance'),
                    # The modality this session was scheduled in place of,
                    # when the package had no archetype for it in this phase
                    # at this level (generator._resolve_session); absent
                    # otherwise.
                    **({'substituted_for': session['substituted_for']}
                       if session.get('substituted_for') else {}),
                    # Level or phase: why no archetype of `substituted_for` fit.
                    **({'substitution_cause': session['substitution_cause']}
                       if session.get('substitution_cause') else {}),
                    # The equipment its archetype asks for that the athlete
                    # lacks; it runs scaled (generator._resolve_session pass 2).
                    **({'equipment_scaled': session['equipment_scaled']}
                       if session.get('equipment_scaled') else {}),
                    # A session no archetype could fill says why.
                    **({'error': session['error']}
                       if session.get('error') and not session.get('archetype') else {}),
                    # A test of the phase's standards, put in place of a
                    # session of `in_place_of` (src/generator._plan_week_tests).
                    **({'test': session['test']} if session.get('test') else {}),
                    # A templated day (src/week_template.py): its category, the
                    # named workouts it does and the warm-up that opens it.
                    **{k: session[k] for k in ('category', 'category_name', 'pieces', 'warm_up', 'light')
                       if session.get(k)},
                    'exercises': [
                        _clean_exercise_assignment(ea)
                        for ea in session.get('exercises', [])
                    ],
                    # Was computed by the generator and dropped here, so the
                    # SessionDetail view that renders it never received any.
                    'complementary_work': session.get('complementary_work', []),
                })
            named_schedule[day_name] = named_sessions

        week_out = {
            'week_number':   wk['week_number'],
            'week_in_phase': wk['week_in_phase'],
            'phase':         wk['phase'],          # the phase kind
            'is_deload':     wk.get('is_deload', False),
            'framework':     wk.get('framework'),
            'schedule':      named_schedule,
        }
        # The philosophy's own phase: id and display name, and the track.
        for key in ('phase_id', 'phase_name', 'track_id', 'tests_skipped'):
            if wk.get(key):
                week_out[key] = wk[key]
        weeks.append(week_out)

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
        'phase_summary':  _phase_summary(weeks, goal),
        # What the constraints held back, counted once for both clients
        # (src/blockers.held_back); derived from the weeks, never stored.
        'held_back':      _blockers.held_back(weeks),
        'compromises':    raw.get('compromises', []),
        'coverage_report': raw.get('coverage_report'),
        **{k: raw[k] for k in ('training_contract', 'module_state') if k in raw},
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
@require_auth
@require_authoring
def create_modality():
    body = request.get_json(silent=True) or {}
    if not body.get('id') or not body.get('name'):
        return jsonify({'detail': 'id and name are required'}), 400
    if body.get('recovery_cost') not in ('high', 'medium', 'low'):
        return jsonify({'detail': 'recovery_cost must be high, medium, or low'}), 400
    errors = _schema_errors('modality', body)
    if errors:
        return _invalid('modality', errors)
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


@app.get('/api/standards')
@app.get('/api/benchmarks')
def get_benchmarks():
    """The standards. `?sex=female|male` picks the tables; the default is the
    male set, which is what every client got before the profile could say.
    `/api/benchmarks` is the old name, kept for installed builds."""
    sex = (request.args.get('sex') or '').lower()
    return jsonify(_all_benchmarks(sex if sex in ('male', 'female') else 'male'))


@app.get('/api/frameworks')
def get_frameworks():
    fw_dict = loader.load_all_frameworks()
    return jsonify(sorted(fw_dict.values(), key=lambda fw: fw.get('id', '')))


@app.get('/api/philosophies')
def get_philosophies():
    philosophies = loader.load_philosophies()
    from src.training_contract import load_contract
    exercises, _ = loader.load_all_exercises()
    for philosophy in philosophies:
        for track in philosophy.get('tracks', []):
            contract = load_contract(philosophy['id'], track['id'])
            if contract:
                track['entry_requirements'] = {
                    'training_levels': contract['training_levels'],
                    # A module that waits for its movements (`when_mastered`:
                    # Wildman's snatch) is no entry requirement.
                    'mastered_exercises': sorted({eid for m in contract['modules'] if not m.get('when_mastered')
                                                  for eid in m.get('requires_mastery', [])}),
                    # Less what the contract seeds for the level: General Practice
                    # counts an intermediate's clean and press as known, and both
                    # builders asked for them anyway.
                    'mastered_exercises_by_level': {level: sorted({eid for m in contract['modules']
                        if level in m['training_levels'] and not m.get('when_mastered')
                        for eid in m.get('requires_mastery', [])}
                        - set((contract.get('level_seeds') or {}).get(level) or []))
                        for level in contract['training_levels']},
                    # Each required movement's name, for the builders' "I can
                    # perform …" (they once stripped one package's id prefix).
                    'exercise_names': {eid: (exercises.get(eid) or {}).get('name', eid)
                                       for m in contract['modules'] for eid in m.get('requires_mastery', [])},
                    'kettlebell_count': 2 if contract.get('requires_kettlebell_pair') else 1,
                    # Lifts the athlete may start from a weight they last made
                    # (`starting_loads_kg`); left empty, the first session
                    # works up to one. Optional — never a requirement.
                    'starting_loads': [{'id': lift, 'name': (exercises.get(lift) or {}).get('name', lift)}
                                       for m in contract['modules']
                                       if m['progression']['model'] == 'load_per_exposure'
                                       for lift in m['progression'].get('lifts') or {}],
                }
    return jsonify(philosophies)


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

    Returns {category: {ids, scores, top}}: every pair's score once (the upper
    triangle, ``similarity._category``) and each item's nearest peers with
    {score, primary, secondary}. Pre-computed on first call.
    """
    return jsonify(_get_similarity())


@app.post('/api/exercises')
@require_auth
@require_authoring
def create_exercise():
    body = request.get_json(silent=True) or {}
    if not body.get('id') or not body.get('name'):
        return jsonify({'detail': 'id and name are required'}), 400
    errors = _schema_errors('exercise', body)
    if errors:
        return _invalid('exercise', errors)
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
@require_auth
@require_authoring
def update_exercise(ex_id: str):
    body = request.get_json(silent=True) or {}
    path, idx, data = _find_exercise_file_and_index(ex_id)
    if path is None:
        return jsonify({'detail': f"Exercise '{ex_id}' not found"}), 404
    merged = {**data['exercises'][idx], **{k: v for k, v in body.items() if k != 'id'}}
    errors = _schema_errors('exercise', merged)
    if errors:
        return _invalid('exercise', errors)
    data['exercises'][idx] = merged
    with open(path, 'w', encoding='utf-8') as f:
        yaml.dump(data, f, allow_unicode=True, default_flow_style=False, sort_keys=False)
    return jsonify(data['exercises'][idx]), 200


@app.delete('/api/exercises/<ex_id>')
@require_auth
@require_authoring
def delete_exercise(ex_id: str):
    """Removes an exercise the API created (the `custom` package only)."""
    path, idx, data = _find_exercise_file_and_index(ex_id)
    if path is None:
        return jsonify({'detail': f"Exercise '{ex_id}' not found"}), 404
    if not _is_custom_package_path(path):
        return jsonify({'detail': 'only exercises in the custom package can be deleted through the API; '
                                  'authored packages are edited as YAML'}), 403
    del data['exercises'][idx]
    with open(path, 'w', encoding='utf-8') as f:
        yaml.dump(data, f, allow_unicode=True, default_flow_style=False, sort_keys=False)
    return jsonify({'deleted': ex_id}), 200


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
@require_auth
@require_authoring
def update_archetype(arch_id: str):
    body = request.get_json(silent=True) or {}
    path = _find_archetype_file(arch_id)
    if not path:
        return jsonify({'detail': f"Archetype '{arch_id}' not found"}), 404
    data = _load_yaml(path)
    merged = {**data, **{k: v for k, v in body.items() if v is not None}}
    errors = _schema_errors('archetype', merged)
    if errors:
        return _invalid('archetype', errors)
    with open(path, 'w', encoding='utf-8') as f:
        yaml.dump(merged, f, allow_unicode=True, default_flow_style=False, sort_keys=False)
    _watch_spec.clear_cache()
    return jsonify(merged), 200


@app.delete('/api/archetypes/<arch_id>')
@require_auth
@require_authoring
def delete_archetype(arch_id: str):
    """Removes an archetype the API created (the `custom` package only)."""
    path = _find_archetype_file(arch_id)
    if not path:
        return jsonify({'detail': f"Archetype '{arch_id}' not found"}), 404
    if not _is_custom_package_path(path):
        return jsonify({'detail': 'only archetypes in the custom package can be deleted through the API; '
                                  'authored packages are edited as YAML'}), 403
    os.remove(path)
    _watch_spec.clear_cache()
    return jsonify({'deleted': arch_id}), 200


@app.put('/api/frameworks/<fw_id>')
@require_auth
@require_authoring
def update_framework(fw_id: str):
    body = request.get_json(silent=True) or {}
    matches = glob.glob(os.path.join(_DATA_DIR, 'packages', '*', 'frameworks', f'{fw_id}.yaml'))
    if not matches:
        return jsonify({'detail': f"Framework '{fw_id}' not found"}), 404
    path = matches[0]
    data = _load_yaml(path)
    allowed = {'name', 'source_philosophy', 'sessions_per_week', 'cadence_options',
               'deload_protocol', 'applicable_when', 'notes', 'recovery'}
    for k, v in body.items():
        if k in allowed and v is not None:
            data[k] = v
    errors = _schema_errors('framework', data)
    if errors:
        return _invalid('framework', errors)
    with open(path, 'w', encoding='utf-8') as f:
        yaml.dump(data, f, allow_unicode=True, default_flow_style=False, sort_keys=False)
    return jsonify(data), 200


@app.post('/api/archetypes')
@require_auth
@require_authoring
def create_archetype():
    body = request.get_json(silent=True) or {}
    if not body.get('id') or not body.get('name'):
        return jsonify({'detail': 'id and name are required'}), 400
    arch_id = body['id']
    if not re.fullmatch(r'[A-Za-z0-9_-]+', arch_id):
        return jsonify({'detail': 'id must contain only letters, digits, underscores, and hyphens'}), 400
    errors = _schema_errors('archetype', body)
    if errors:
        return _invalid('archetype', errors)
    existing_ids = {a.get('id') for a in loader.load_all_archetypes()}
    if arch_id in existing_ids:
        return jsonify({'detail': f"Archetype id '{arch_id}' already exists"}), 409
    custom_dir = os.path.join(_DATA_DIR, 'packages', 'custom', 'archetypes')
    os.makedirs(custom_dir, exist_ok=True)
    out_path = os.path.join(custom_dir, f"{arch_id}.yaml")
    with open(out_path, 'w', encoding='utf-8') as f:
        yaml.dump(body, f, allow_unicode=True, default_flow_style=False, sort_keys=False)
    # The watch's archetype -> package index is cached; the new archetype's
    # sessions must name their package without a server restart.
    _watch_spec.clear_cache()
    return jsonify(body), 201


def _goal_ids_from_body(body: dict, generated: dict) -> tuple[list, dict]:
    """Source philosophy ids + weights for an envelope, from the request if it
    carried them, else recovered from the generated goal's own id."""
    ids = body.get('philosophy_ids') or body.get('goal_ids') or []
    if not ids and (body.get('philosophy_id') or body.get('goal_id')):
        ids = [body.get('philosophy_id') or body['goal_id']]
    if not ids:
        # A synthetic goal's id is '_phil_<philosophy_id>' (see
        # _philosophy_to_goal), so it can be read back when the caller did not
        # say which philosophy it asked for.
        # A blend's id is '_phil_blend', so its sources come from the goal's
        # primary_sources, which every synthetic goal carries.
        goal = generated.get('goal') or {}
        goal_id = goal.get('id') or ''
        ids = [i for i in (goal.get('primary_sources') or []) if i]
        if not ids and goal_id.startswith('_phil_') and goal_id != '_phil_blend':
            ids = [goal_id[len('_phil_'):]]
    weights = body.get('philosophy_weights') or body.get('goal_weights') or {}
    return list(ids), dict(weights)


def _monday_of(day: _date) -> _date:
    """Programs are anchored to a Monday.

    Week position is computed as `(today - start).days // 7` (see
    /api/user/today-session), so a mid-week anchor puts the athlete on the
    wrong week for the rest of every week.
    """
    return day - _timedelta(days=day.weekday())


def _wrap_generated_program(generated: dict, body: dict, existing) -> dict:
    """Put a freshly generated program into the stored envelope.

    Start date precedence, most authoritative first:

    1. what the generator resolved — `program_start_date`, already
       Monday-aligned, present whenever the caller asked for a start date;
    2. what the caller asked for, if the generator did not echo it back;
    3. the existing program's start date, so a regenerate that specifies
       nothing does not silently restart the athlete's calendar;
    4. this Monday.

    Taking (3) before (1) — as this did — meant a regenerate from the phone's
    Program Settings sheet kept the old start date while telling the athlete
    the program had been replaced, and a first-ever generate anchored to
    *today* rather than the Monday the athlete chose.
    """
    existing = _normalize_program_keys(existing) if isinstance(existing, dict) else {}
    ids, weights = _goal_ids_from_body(body, generated)
    start = (generated.get('program_start_date')
             or body.get('start_date')
             or existing.get('programStartDate')
             or _monday_of(_date.today()).isoformat())
    return {
        'currentProgram':    generated,
        'programStartDate':  start,
        'eventDate':         body.get('event_date') or existing.get('eventDate'),
        'sourceGoalIds':     ids or existing.get('sourceGoalIds') or [],
        'sourceGoalWeights': weights or existing.get('sourceGoalWeights') or {},
    }


def _record_program_history(user_id: str, envelope: dict, source: str,
                            revision: str | None = None) -> dict:
    """Archive a stored program into the history, never failing the save.

    Idempotent on the plan's skeleton, so the three self-healing re-saves below
    and every iOS round-trip are no-ops rather than new history entries. A
    failure here must not fail the program save that triggered it — an
    unarchived program is recoverable (the next GET archives it), a 503 on a
    program save is not.
    """
    try:
        from src import program_history
        return program_history.record_version(user_id, envelope, source=source,
                                              source_revision=revision)
    except Exception as e:
        app.logger.warning('program history record failed: %s', e)
        return {'recorded': False, 'versionId': None, 'reason': str(e)}


@app.post('/api/programs/generate')
@require_auth
def generate_program():
    import traceback as _tb
    body = request.get_json(silent=True) or {}
    try:
        resp = app.make_response(_generate_program_inner(body))
        if resp.status_code >= 400:
            return resp
        # An infeasible answer (the validator's, or a training contract that
        # cannot run as written) is shown to the athlete, never saved: it used
        # to persist as an empty program when a client asked to save.
        if not (resp.get_json(silent=True) or {}).get('weeks'):
            return resp
        # Persist only when the caller says this generate is a commit.
        #
        # This used to save unconditionally, and it saved `resp_data` — the bare
        # GeneratedProgram — leaving program_data with the generator's own
        # top-level keys, no `currentProgram` and no `programStartDate`. Every
        # client reads `.currentProgram`, so a real account's program silently
        # read as "no program" while all its weeks sat intact in the database.
        #
        # Now: the web app saves the program itself through
        # PUT /api/user/program after a successful generate, so it passes
        # nothing here; iOS has no such step (it generates, then re-fetches) so
        # it sends persist=true. Defaulting to off means an exploratory or
        # failed generate can no longer replace a stored program.
        if not body.get('persist'):
            return resp
        # The PUT's optimistic concurrency, for a caller that sends the
        # revision it read: a commit may not replace newer work.
        if body.get('baseRevision') is not None:
            from src.db import get_program_revision as _current_rev
            current_rev = _current_rev(g.user_id)
            if current_rev is not None and str(body['baseRevision']) != str(current_rev):
                return jsonify({'saved': False, 'detail': 'stale_revision',
                                'currentRevision': current_rev}), 409
        try:
            from src.db import get_user_program, save_user_program
            import json as _json
            resp_data = _json.loads(resp.get_data(as_text=True))
            if isinstance(resp_data, dict) and resp_data.get('weeks') is not None:
                existing = get_user_program(g.user_id)
                envelope = _wrap_generated_program(resp_data, body, existing)
                envelope = _keep_days_behind(g.user_id, existing, envelope)
                save_user_program(g.user_id, envelope)
                # Archive what we just made the active plan. This is the richest
                # copy that will ever exist — iOS strips `goal` and every `slot`
                # when it saves — so capturing it here matters.
                from src.db import get_program_revision as _rev
                _record_program_history(g.user_id, envelope, 'generate', _rev(g.user_id))
        except Exception as _save_err:
            # The caller asked for this program to become theirs; answering
            # 200 here told the phone it had, and its builder sat there with
            # nothing saved and nothing said (the local DB had lost its
            # user_programs table). History never raises, so this is the save.
            app.logger.warning('generate: auto-save failed: %s', _save_err)
            return jsonify({'saved': False,
                            'detail': 'The program was generated but could not be saved.'}), 503
        return resp
    except Exception as e:
        msg = _tb.format_exc()
        with open(os.path.join(tempfile.gettempdir(), 'api_errors.txt'), 'a') as _f:
            import json as _json
            _f.write(f'body: {_json.dumps(body)}\n{msg}\n---\n')
        raise


def _track_of_weeks(current: dict) -> str | None:
    """The track a stored program's weeks were generated on, if they say."""
    for w in current.get('weeks') or []:
        if isinstance(w, dict) and w.get('track_id'):
            return w['track_id']
    return None


def _philosophy_to_goal(phil_id: str, all_frameworks: list, track_id: str | None = None,
                        level: str | None = None) -> dict:
    """Build a synthetic goal dict from a philosophy. See src/goals.py."""
    return goals.philosophy_to_goal(phil_id, all_frameworks, track_id, level)


def _blend_philosophy_goals(phil_ids: list, phil_weights: dict, all_frameworks: list,
                            track_id: str | None = None, level: str | None = None) -> dict:
    """Weighted-average a set of philosophy synthetic goals into one."""
    return goals.blend_philosophy_goals(phil_ids, phil_weights, all_frameworks, track_id, level)


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
    # No training_phase default: the start is the track's first phase unless
    # the request names one (start_phase, or the legacy training_phase kind).
    # A 'base' default here is what kept Uphill from ever running Transition.
    constraints.setdefault('periodization_week', 1)
    constraints.setdefault('fatigue_state', 'normal')

    blend_warnings: list[str] = []

    # ── Philosophy path: build synthetic goal from one track ─────────────────
    all_frameworks = list(loader.load_all_frameworks().values())
    member_ids = [philosophy_id] if philosophy_id else list(philosophy_ids)
    track_id = body.get('track_id') or constraints.get('track_id')
    start_phase = body.get('start_phase') or constraints.get('start_phase')

    # Legacy framework pick ("build with this framework", older clients): the
    # track and phase that run it. It used to sit in constraints as
    # forced_framework, where the phase's own framework overrode it — Uphill
    # ignored every explicit pick.
    framework_id = body.get('framework_id')
    if framework_id and not track_id:
        try:
            hit = goals.owner_track_for_framework(member_ids, philosophy_weights, framework_id)
        except FileNotFoundError as e:
            return jsonify({'detail': str(e)}), 404
        if hit is None:
            return jsonify({'detail': f"Framework '{framework_id}' is not used by any "
                                      f"track of {member_ids}."}), 422
        _, track, phase = hit
        track_id = track['id']
        if not start_phase and not body.get('event_date') \
                and not constraints.get('training_phase'):
            start_phase = phase['id']
    constraints.pop('forced_framework', None)

    try:
        # With no track named, the one written for the athlete's level
        # (`track_for_level`: an intermediate on Starting Strength gets the
        # Texas Method, not the novice progression).
        level = constraints.get('training_level')
        if philosophy_id:
            goal = _philosophy_to_goal(philosophy_id, all_frameworks, track_id, level)
        else:
            goal = _blend_philosophy_goals(philosophy_ids, philosophy_weights, all_frameworks,
                                           track_id, level)
    except FileNotFoundError as e:
        return jsonify({'detail': str(e)}), 404
    except PhaseResolutionError as e:
        return jsonify({'detail': str(e)}), 422
    except ContractError as e:
        return jsonify({'detail': str(e)}), 422
    constraints['track_id'] = goal.get('track', {}).get('id')
    if start_phase:
        constraints['start_phase'] = start_phase
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
            constraints['start_phase'] = cal['phase_id']
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
    # A partial regenerate numbers its tail from the kept head's length + 1;
    # without this every tail restarted at 1 and week numbers repeated.
    try:
        start_week_number = max(1, int(body.get('week_in_program') or 1))
    except (TypeError, ValueError):
        start_week_number = 1

    include_trace = bool(body.get('include_trace')) or request.args.get('trace') == '1'

    if not validation.feasible:
        raw = {'weeks': [], 'validation_errors': list(validation.errors)}
    else:
        if goal.get('training_contract'):
            from src import training_contract, health_store
            from src.db import get_user_program
            existing = get_user_program(g.user_id) or {}
            current = existing.get('currentProgram') or {}
            identity = f"{goal['training_contract']['package']}/{goal['training_contract']['track_id']}@{goal['training_contract']['version']}"
            supplied_state = constraints.get('module_progression_state')
            if ((current.get('training_contract') or {}).get('id') == identity
                    and (supplied_state is None or supplied_state == current.get('module_state'))):
                constraints['module_progression_state'] = training_contract.confirmed_state(
                    current, health_store.get_session_logs(g.user_id), goal['training_contract'])
            elif (supplied_state is None and current.get('weeks')
                  and goal['training_contract']['package'] in ((current.get('goal') or {}).get('primary_sources') or [])):
                # A program of this package the contract did not write
                # (Starting Strength before 2026-10-20, or the novice track
                # ahead of the Texas Method): each lift starts from what its
                # logged sets made. Never another method's program — its heavy
                # single is no 3×5 — and a weight the athlete typed wins.
                loaded = [m for m in goal['training_contract']['modules']
                          if m['progression']['model'] == 'load_per_exposure']
                if loaded:
                    logs = health_store.get_session_logs(g.user_id)
                    typed = set(constraints.get('starting_loads_kg') or {})
                    constraints['module_progression_state'] = {
                        m['id']: {'completed': 0, 'lifts': {
                            lift: rec for lift, rec in training_contract.seed_lifts(current, logs, m).items()
                            if lift not in typed}}
                        for m in loaded}
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
            start_week_number=start_week_number,
        )

    if raw.get('validation_errors'):
        for error in raw['validation_errors']:
            if error not in validation.errors:
                validation.add_error(error['code'], error['message'])
        result = _transform_program(raw, goal, constraints, validation)
        result['detail'] = '; '.join(error['message'] for error in raw['validation_errors'])
        # 200 with `validation.feasible: false`, as every infeasible request
        # has always been answered: the web builder shows the ValidationAlert
        # from it and the phone its errors. The save path refuses it above.
        return jsonify(result)

    # A modality the generator had to schedule as another one because nothing
    # in the package is written for this athlete's level.
    substituted: dict = {}
    for s in (raw.get('coverage_report') or {}).get('substituted_sessions') or []:
        if s.get('substituted_for'):
            substituted.setdefault(s['substituted_for'], set()).add(s.get('modality'))
    check_level_coverage(substituted, constraints, archetypes_filtered, policy, validation)

    result = _transform_program(raw, goal, constraints, validation)
    if include_trace and 'generation_trace' in raw:
        result['generation_trace'] = raw['generation_trace']
    if program_start_monday:
        result['program_start_date'] = program_start_monday.isoformat()
    return jsonify(result)


def _stored_contract() -> str | None:
    """The training contract the athlete's active program was built by, if any.

    A single-session regenerate or an exercise swap would bypass its modules,
    so both refuse for such a program. Asked of the stored program, not of the
    request's packages: the phone sends no philosophy ids for a regenerate, and
    a blend that includes a contract package is built by the general generator.
    """
    try:
        from src.db import get_user_program
        current = (get_user_program(g.user_id) or {}).get('currentProgram') or {}
    except Exception:
        return None
    return (current.get('training_contract') or {}).get('id')


def _generated_json(resp) -> tuple[dict, int]:
    """_generate_program_inner answers a response or a (response, status)."""
    if isinstance(resp, tuple):
        return resp[0].get_json(), resp[1]
    return resp.get_json(), resp.status_code


@app.post('/api/dev/constraint-impact')
@require_auth
@require_authoring
def dev_constraint_impact():
    """What the athlete's equipment, injuries, level and proficiency change in a program,
    and which one changes it (for the Dev Lab; src/constraint_impact.py)."""
    out, status = _constraint_impact(request.get_json(silent=True) or {})
    return jsonify(out), status


# The impact and constraint-change routes run several generations each (up to
# seven, a few seconds apiece) on a 256 MB machine serving four threads. One
# runs at a time in the process and one per athlete; a request that finds the
# gate taken answers 429 at once, never waiting on it — four threads parked on
# a 20 s wait were the whole pool, and the watch's sync queued behind them
# (test_worker_stalls.py). The clients retry a 429.
#
# Only impact answers are cached, small ones, for ten minutes, keyed on the
# body and the athlete's day: a constraint-change answer carries a whole
# generated program (~1 MB, several as dicts), and the clients already keep
# theirs per program revision. The generator reads state the body does not
# carry (a contract's confirmed sessions), so nothing is kept long.
_HEAVY_GATE = threading.BoundedSemaphore(1)
_HEAVY_USERS: set = set()
_HEAVY_LOCK = threading.Lock()   # guards _HEAVY_USERS and _HEAVY_CACHE
_HEAVY_CACHE: 'dict[str, tuple[float, tuple[dict, int]]]' = {}
_HEAVY_CACHE_MAX = 8
_HEAVY_CACHE_TTL = 600
_HEAVY_CACHE_MAX_BYTES = 512 * 1024


def _heavy_run(kind: str, body: dict, run, cache: bool = False):
    """`run(body)` → (dict, status), one at a time; busy answers 429
    `{busy: true}`. `cache` keeps a small 200 answer for ten minutes."""
    import hashlib
    import time
    user = getattr(g, 'user_id', None)
    key = hashlib.sha256(json.dumps([kind, user, _date.today().isoformat(), body],
                                    sort_keys=True, default=str).encode()).hexdigest()
    now = time.monotonic()
    with _HEAVY_LOCK:
        hit = _HEAVY_CACHE.get(key) if cache else None
        if hit and now - hit[0] < _HEAVY_CACHE_TTL:
            return hit[1]
        if user in _HEAVY_USERS:
            return {'busy': True, 'detail': 'Still working on your last request.'}, 429
        _HEAVY_USERS.add(user)
    try:
        if not _HEAVY_GATE.acquire(blocking=False):
            return {'busy': True, 'detail': 'The server is busy; trying again.'}, 429
        try:
            out = run(body)
        finally:
            _HEAVY_GATE.release()
    finally:
        with _HEAVY_LOCK:
            _HEAVY_USERS.discard(user)
    if cache and out[1] == 200 and len(json.dumps(out[0], default=str)) <= _HEAVY_CACHE_MAX_BYTES:
        with _HEAVY_LOCK:
            for stale in [k for k, (at, _) in _HEAVY_CACHE.items() if now - at >= _HEAVY_CACHE_TTL]:
                _HEAVY_CACHE.pop(stale, None)
            while len(_HEAVY_CACHE) >= _HEAVY_CACHE_MAX:
                _HEAVY_CACHE.pop(next(iter(_HEAVY_CACHE)), None)
            _HEAVY_CACHE[key] = (now, out)
    return out


@app.post('/api/programs/impact')
@require_auth
def program_impact():
    """The program preview's "Held back": what the athlete's equipment, injuries,
    level and proficiency change against a reference with nothing in the way,
    and what would restore it (src/constraint_impact.py). Generate's body."""
    body = request.get_json(silent=True) or {}
    out, status = _heavy_run('impact', body, _constraint_impact, cache=True)
    return jsonify(out), status


def _constraint_impact(body: dict) -> tuple[dict, int]:
    """The constraint-impact runs for generate's `body`.

    Takes generate's body (plus an optional `reference: {equipment,
    training_level}`) and generates the athlete's program, a reference with
    nothing in the way, and one run per constraint with only that one lifted —
    up to seven generations, on at most 12 weeks. An event date would size the
    program to the event, so it is dropped: the start phase is the request's.
    A request the generator refuses (no weeks: a training contract that cannot
    run as written, or an infeasible schedule) is answered with what alone
    would let it generate.
    """
    import copy as _copy
    from src import constraint_impact
    from src.selector import _get_unlocked

    body = _copy.deepcopy(body)
    body.pop('event_date', None)
    body.pop('persist', None)
    try:
        body['num_weeks'] = max(1, min(int(body.get('num_weeks') or 4), 12))
    except (TypeError, ValueError):
        body['num_weeks'] = 4
    override = body.pop('reference', None) or {}

    actual, status = _generated_json(_generate_program_inner(_copy.deepcopy(body)))
    if status != 200 or not actual.get('goal'):
        return actual, status
    refused = not actual.get('weeks')

    athlete = actual['constraints']
    goal = actual['goal']
    data = loader.load_all_data()
    lib = provenance.scope(data, provenance.resolve_source_policy(goal))
    # The start phase's framework: the first week's, or for a refusal the
    # phase the request starts at.
    framework_id = (actual.get('weeks') or [{}])[0].get('framework') or next(
        (p.get('framework_id') for p in goal.get('phase_sequence') or []
         if p.get('phase_id') == athlete.get('start_phase')),
        ((goal.get('phase_sequence') or [{}])[0]).get('framework_id'))
    try:
        framework = loader.load_framework(framework_id)
    except (FileNotFoundError, TypeError):
        framework = None
    # The reference's level first, then what a contract asks of that level.
    level = constraint_impact.reference_constraints(athlete, lib, framework, override)['training_level']
    reference = constraint_impact.reference_constraints(
        athlete, lib, framework, override, constraint_impact.contract_requirements(goal, level))
    runs = {'reference': reference, **constraint_impact.relaxations(athlete, reference)}
    if refused:
        probe = constraint_impact.schedule_probe(athlete, framework)
        if probe:
            runs['schedule'] = probe

    programs: dict = {}
    for name, cons in runs.items():
        variant = _copy.deepcopy(body)
        variant['constraints'] = _copy.deepcopy(cons)
        if not cons.get('injury_flags'):
            variant['custom_injury_flags'] = []
        program, st = _generated_json(_generate_program_inner(variant))
        programs[name] = program if st == 200 else {'weeks': []}

    exercises = {**data['exercises'], **lib['exercises']}
    # The request's own flags, as the generator merges them.
    flags = {**data['injury_flags'], **{f['id']: f for f in body.get('custom_injury_flags') or [] if f.get('id')}}
    lifts = constraint_impact.describe_lifts(
        athlete, {k: v for k, v in runs.items() if k != 'reference'}, exercises, flags)
    if refused:
        return constraint_impact.explain_refusal(
            actual, {name: bool(p.get('weeks')) for name, p in programs.items()}, lifts, reference), 200

    if not programs['reference'].get('weeks'):
        # Nothing to compare against: every session would read as "added".
        return {'feasible': True, 'reference_generates': False, 'lifts': lifts,
                'reference': {k: reference.get(k) for k in ('equipment', 'training_level',
                                                             'mastered_exercises', 'kettlebell_count')
                              if k in reference},
                'detail': 'The reference with nothing in the way does not generate, so there is '
                          'nothing to compare the program with.'}, 200
    level_now = athlete.get('training_level', 'intermediate')
    # Per package, as the selector unlocks for an archetype's own package.
    unlocked = {pkg: _get_unlocked(level_now, lib['exercises'], {pkg: (lib['level_seeds'] or {}).get(pkg, {})})
                for pkg in {ex.get('_package') for ex in lib['exercises'].values() if ex.get('_package')}}
    result = constraint_impact.analyse(
        actual, programs.pop('reference'), programs,
        constraints=athlete, reference_constraints=reference,
        exercises=exercises,
        archetypes={a['id']: a for a in data['archetypes'] if a.get('id')},
        injury_flags=flags,
        unlocked=unlocked,
    )
    return {'feasible': True, 'validation': actual.get('validation'), 'lifts': lifts, **result}, 200


@app.post('/api/programs/constraint-change')
@require_auth
def program_constraint_change():
    """Does a profile change change the program? Generate's body for the
    remaining weeks with the profile's constraints, plus `baseline_constraints`:
    the same request with the program's own. Both are generated and lined up
    session by session (constraint_impact.diff_programs), so the answer is the
    change's own effect — not the athlete's swaps on the stored plan, nor what
    the generator does differently since it was built. `program` (the tail with
    the new constraints) comes back only when something changed, for the
    preview and the apply.
    """
    body = request.get_json(silent=True) or {}
    if not isinstance(body.get('baseline_constraints'), dict) or not isinstance(body.get('constraints'), dict):
        return jsonify({'error': 'constraints and baseline_constraints are required'}), 422
    out, status = _heavy_run('constraint-change', body, _constraint_change)
    return jsonify(out), status


def _constraint_change(body: dict) -> tuple[dict, int]:
    import copy as _copy
    from src import constraint_impact

    after_body = _copy.deepcopy(body)
    after_body.pop('persist', None)
    before_body = _copy.deepcopy(after_body)
    before_body['constraints'] = before_body.pop('baseline_constraints')
    after_body.pop('baseline_constraints', None)
    if 'baseline_custom_injury_flags' in before_body:
        before_body['custom_injury_flags'] = before_body.pop('baseline_custom_injury_flags')
    after_body.pop('baseline_custom_injury_flags', None)

    before, st_before = _generated_json(_generate_program_inner(before_body))
    after, st_after = _generated_json(_generate_program_inner(after_body))
    if st_after != 200:
        return after, st_after
    if st_before != 200 or not before.get('weeks'):
        # Nothing to compare with: the program as it stands could not be
        # rebuilt. Never "unaffected" — that would record the new settings
        # on a program nobody checked — so the profile's version, built or
        # refused, is what the client offers.
        return {'affected': True, 'comparable': False,
                'sessions': {'total': 0, 'changed': 0}, 'first_week_number': None, 'changes': [],
                'program': after, 'validation': after.get('validation')}, 200
    diff = constraint_impact.diff_programs(before, after)
    return {**diff, 'comparable': True, 'validation': after.get('validation'),
            **({'program': after} if diff['affected'] else {})}, 200


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


def _prog_model_for(modality: str, body: dict, data: dict) -> str:
    """The progression model that writes a single session's loads: the week's
    framework's `progression_overrides` (Filly prescribes RPE), else the
    modality's — as the generator decides, so a swapped or regenerated
    session matches the rest of its week."""
    fw = loader.load_all_frameworks().get(body.get('framework_id')) if body.get('framework_id') else None
    from src.training_contract import resolve_model
    return resolve_model(fw or {}, modality, data['modalities'])


def _week_phase_rules(body: dict, philosophy_ids) -> tuple[frozenset, float | None]:
    """(exclude_exercises, deload share) for the week a single-session route edits.

    The client sends the week's `phase_id` and `framework_id`; without them
    (an older client) nothing is excluded and the model defaults apply, as
    before. The phone sends no philosophy ids for a session regenerate, so the
    phase is looked up across every package, narrowed by the framework.
    """
    phase_id, framework_id = body.get('phase_id'), body.get('framework_id')
    phils = loader.load_philosophies()
    wanted = [p for p in phils if p.get('id') in set(philosophy_ids or [])] or phils
    rules = phases.phase_rules(wanted, phase_id, framework_id)
    fw = loader.load_all_frameworks().get(framework_id) if framework_id else None
    keep = ((fw or {}).get('deload_protocol') or {}).get('volume_reduction_pct')
    return frozenset(rules['exclude_exercises']), keep


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

    if _stored_contract():
        return jsonify({'detail': 'Regenerate this contract program to replace a module while preserving its progression.'}), 422
    phase_excluded, deload_keep = _week_phase_rules(body, primary_sources)
    session_stub = {'modality': modality, 'is_deload': is_deload}
    framework = loader.load_all_frameworks().get(body.get('framework_id')) or {}
    if forced_arch is None and framework.get('categories'):
        # A templated day (Horsemen's): another named workout of its category,
        # as written, never a generic session of the modality.
        import random
        from src import week_template
        from src.generator import _fits_as_written
        def _probe(a):
            return populate_session({'modality': a.get('modality')}, goal, constraints, lib['exercises'],
                                    archetypes_filtered, merged_injury_flags, phase, week_in_phase,
                                    forced_archetype=a, exercises_by_package=lib.get('exercises_by_package'),
                                    policy=policy, level_seeds=lib.get('level_seeds'),
                                    exclude_exercise_ids=phase_excluded, pinned_lifts=None, unfilled_cache={})
        day = week_template.regenerate_day(
            framework, body.get('category'), modality, constraints,
            {a['id']: a for a in archetypes_filtered},
            lambda a, minutes: (a.get('duration_estimate_minutes') or 0) <= minutes
                and _fits_as_written(a, constraints, phase, _probe),
            random.choice, exclude={body.get('current_archetype_id')} - {None})
        if day is None:
            return jsonify({'detail': 'No workout of this day fits as written (equipment, injuries, time).'}), 422
        forced_arch = day.pop('_forced_archetype')
        session_stub.update(day)
        modality = day['modality']
    populated = populate_session(
        session_stub, goal, constraints,
        lib['exercises'], archetypes_filtered,
        merged_injury_flags, phase, week_in_phase,
        forced_archetype=forced_arch,
        exercises_by_package=lib.get('exercises_by_package'),
        policy=policy,
        level_seeds=lib.get('level_seeds'),
        exclude_exercise_ids=phase_excluded,
        deload_keep=deload_keep,
    )

    if populated.get('archetype') is None:
        return jsonify({'detail': f'No archetype found for {modality!r} in phase {phase!r}'}), 422

    # Apply progression loads
    prog_model = _prog_model_for(modality, body, data)
    if prog_model == 'as_written' and not (populated.get('archetype') or {}).get('pool_only'):
        # As written means the source's own workouts; any other archetype
        # keeps its modality's model (it has no load text to show).
        prog_model = (data['modalities'].get(modality) or {}).get('progression_model', 'linear_load')
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
            deload_keep=deload_keep,
        )

    arch = populated.get('archetype', {})
    return jsonify({
        'modality':  modality,
        'archetype': arch,
        'is_deload': is_deload,
        **{k: populated[k] for k in ('category', 'category_name', 'pieces', 'warm_up') if populated.get(k)},
        'duration_min': arch.get('duration_estimate_minutes') if arch else None,
        'exercises': [_clean_exercise_assignment(ea) for ea in populated.get('exercises', [])],
    })


@app.post('/api/exercises/substitute')
@require_auth
def substitute_exercise():
    """Ranked alternatives for one exercise in one archetype slot.

    The smallest regenerable unit used to be a session, so swapping one
    exercise meant regenerating all of them. This runs the selector's own
    candidate filter and score for the slot — the same unlock, equipment,
    injury and package rules a generate applies — and returns each
    alternative as a complete assignment with its load for the week, so a
    client replaces the entry in place and saves through the revision-checked
    PUT. Nothing is persisted here.
    """
    from src import selector as _selector
    body = request.get_json(silent=True) or {}
    archetype_id = body.get('archetype_id')
    slot_role = body.get('slot_role')
    if not archetype_id or not slot_role:
        return jsonify({'detail': 'archetype_id and slot_role are required'}), 400

    constraints = dict(body.get('constraints') or {})
    constraints.setdefault('session_time_minutes', 75)
    constraints.setdefault('training_level', 'intermediate')
    constraints.setdefault('equipment', ['barbell', 'rack', 'plates', 'kettlebell',
                                          'pull_up_bar', 'ruck_pack', 'open_space'])
    constraints.setdefault('injury_flags', [])
    goal = {'primary_sources': list(body.get('philosophy_ids') or [])}

    data = loader.load_all_data()
    policy = provenance.resolve_source_policy(goal)
    lib = provenance.scope(data, policy)

    # A templated day's warm-up or second workout: its slot lives in its own
    # archetype (src/week_template.compose names it in the role).
    from src.week_template import source_slot
    session_role = slot_role
    archetype_id, slot_role = source_slot(archetype_id, slot_role)
    arch = next((a for a in data['archetypes'] if a.get('id') == archetype_id), None)
    if arch is None:
        return jsonify({'detail': f'Archetype {archetype_id!r} not found'}), 404
    if _stored_contract():
        return jsonify({'detail': 'This exercise belongs to a fixed training module; regenerate the contract program to change it.'}), 422
    slot_index, slot = next(((i, sl) for i, sl in enumerate(arch.get('slots') or [])
                             if sl.get('role') == slot_role), (None, None))
    if slot is None:
        return jsonify({'detail': f'Slot {slot_role!r} not in archetype {archetype_id!r}'}), 404

    modality = body.get('modality') or arch.get('modality')
    phase = body.get('phase') or 'base'
    week_in_phase = int(body.get('week_in_phase') or 1)
    is_deload = bool(body.get('is_deload'))
    level = constraints['training_level']
    exclude = set(body.get('exclude') or [])
    if body.get('exercise_id'):
        exclude.add(body['exercise_id'])
    limit = max(1, min(int(body.get('limit') or 8), 10))

    excl_patterns, excl_ids = _selector._injury_exclusions(constraints, data['injury_flags'])
    phase_excluded, deload_keep = _week_phase_rules(body, goal['primary_sources'])
    unlocked = (_selector._get_unlocked(level, lib['exercises'], lib.get('level_seeds'))
                - excl_ids - phase_excluded)
    _selected, trace = _selector.select_exercise(
        slot, constraints, lib['exercises'], unlocked, excl_patterns, excl_ids,
        recent_ex_ids=None, phase=phase, session_used_ids=list(exclude),
        return_trace=True, primary_sources=set(goal['primary_sources']),
        policy=policy, modality=modality,
    )
    prog_model = _prog_model_for(modality, body, data)
    pattern = (slot.get('exercise_filter') or {}).get('movement_pattern')
    alternatives = []
    for cand in (trace or {}).get('candidates') or []:
        if cand['id'] in exclude:
            continue
        ex = lib['exercises'].get(cand['id']) or data['exercises'].get(cand['id'])
        if ex is None:
            continue
        load = calculate_load(ex, slot, prog_model, week_in_phase, phase, level, is_deload,
                              session_time_minutes=constraints.get('session_time_minutes', 75),
                              deload_keep=deload_keep)
        ea = {'slot_index': slot_index, 'slot_role': session_role,
              'slot_type': slot.get('slot_type', 'sets_reps'),
              'exercise': ex, 'slot': slot, 'load': load}
        breakdown = cand.get('breakdown') or {}
        reasons = []
        if pattern:
            reasons.append(f'fits the {str(pattern).replace("_", " ")} pattern')
        if cand.get('package'):
            reasons.append(f"from the {str(cand['package']).replace('_', ' ')} package")
        if breakdown.get('unlocks_bonus'):
            reasons.append('unlocks further movements')
        if breakdown.get('recency_penalty'):
            reasons.append('used recently')
        alternatives.append({
            'assignment': _clean_exercise_assignment(ea),
            'score': cand.get('score', 0),
            'reasons': reasons,
        })
        if len(alternatives) >= limit:
            break
    if not alternatives:
        return jsonify({'detail': "No alternative fits this slot under the program's packages, "
                                  'your equipment and injury flags', 'alternatives': []}), 422
    return jsonify({'alternatives': alternatives})


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
    # The landing is Profile ▸ Connections, which every frontend deployment
    # knows: the current build forwards it to Settings ▸ Connections with the
    # query intact (pages/ProfileBenchmarks.tsx), and a deployment that
    # predates Settings — FRONTEND_URL may pin one — still shows the tab.
    # Naming /settings here sent a fresh OAuth connect to a 404 on such a
    # deployment.
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
                # start_date_local is the athlete's wall clock (its 'Z' is a lie).
                'date': (a.get('start_date_local') or '')[:10] or start_dt.strftime('%Y-%m-%d'),
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
            # The profile's zone dates a file whose activity message carries no
            # local timestamp; the file's own offset wins when it has one. A
            # profile lookup that fails must not fail the import.
            try:
                athlete_tz = (_db.get_user_profile(g.user_id) or {}).get('timezone')
            except Exception:
                athlete_tz = None
            results = _fit_import.parse_fit(f.stream, tz=athlete_tz)
        except _fit_import.FitNotAvailable as e:
            return jsonify({'detail': str(e)}), 503
        except Exception as e:
            return jsonify({'detail': f'FIT parse error: {e}'}), 422

        if results:
            _health.upsert_workouts(g.user_id, results)
            # A run's fastest mile can be a result on a run standard: the FIT
            # track has the speed to read it from (src/standard_results.py).
            from src import standard_results
            standard_results.after_workouts_import(g.user_id, results)
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
    # Zones, TRIMP, training effect, recovery, decoupling and best efforts,
    # computed once here for both clients (src/analytics/workout_analysis.py).
    # A failure leaves the workout readable without them.
    try:
        from src.analytics.workout_analysis import analyse
        from src.db import get_user_profile
        workout['analysis'] = analyse(workout, get_user_profile(g.user_id) or {})
    except Exception as exc:
        app.logger.warning('workout analysis failed for %s: %s', workout_id, exc)
    # What the program planned for it, beside what it recorded.
    if isinstance(workout.get('analysis'), dict):
        try:
            workout['analysis']['planned'] = _planned_for_workout(g.user_id, workout)
        except Exception as exc:  # noqa: BLE001 — the recorded side still shows
            app.logger.warning('workout planned zones failed for %s: %s', workout_id, exc)
    return jsonify(workout)


def _planned_for_workout(user_id: str, workout: dict) -> dict | None:
    """What the matched session's programming makes of this recording
    (src/analytics/hr_plan.attribute): exercise by exercise, what each
    prescribes, the minutes it planned and — where the watch timed it — what
    it recorded, and the zone minutes that count, on the same max HR and
    edges as the workout's own zones. None when the workout is linked to no
    session."""
    from src import program_history
    from src.analytics import hr_plan
    match = next((m for m in _health.get_matches(user_id)
                  if m.get('importedWorkoutId') == workout.get('id')
                  and m.get('matchConfidence') != 'rejected'), None)
    if match is None:
        return None
    uid = match.get('sessionUid')
    if not uid and match.get('sessionKey'):
        planned_row = program_history.resolve_session(user_id, legacy_key=match['sessionKey'],
                                                      date_str=workout.get('date'))
        uid = (planned_row or {}).get('session_uid')
    found = program_history.session_lookup(user_id, [uid]) if uid else []
    if not found:
        return None
    session = found[0]['session']
    analysis = workout.get('analysis') or {}
    log = _health.get_session_log(user_id, uid, match.get('sessionKey'), workout.get('date'))
    out = hr_plan.attribute(session, log, workout, analysis.get('maxHr') or 190,
                            analysis.get('zoneBoundaries'))
    out.update({'sessionUid': uid, 'sessionName': found[0].get('archetype_name'),
                'modality': session.get('modality'), 'date': found[0].get('date')})
    return out


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
    # 'male' | 'female' | None. The analytics engine has always read it for the
    # benchmark standards (and hashed it into the cache key); until it was
    # writable every athlete was scored against the male tables.
    'sex',
    # IANA zone, e.g. 'Europe/Zurich'. The fallback for dating a FIT file whose
    # activity message carries no local timestamp; the other sources carry
    # their own offsets. iOS fills it from the device when it is unset.
    'timezone',
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
        'sex': None,
        'timezone': None,
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


@app.delete('/api/account')
@require_auth
def delete_account():
    """Delete the signed-in account and every row it owns (`src/account.py`).

    The phone can create accounts, so it must be able to delete them (App
    Store 5.1.1(v)). Never for `local-dev-user`: that is the developer's own
    local data, not an account.
    """
    from src import account as _account
    if g.user_id == 'local-dev-user':
        return jsonify({'detail': 'Local dev has no account to delete.'}), 409
    try:
        counts = _account.delete_account(g.user_id)
    except _account.AccountDeletionError as e:
        app.logger.warning('delete_account %s: %s', g.user_id, e)
        return jsonify({'detail': str(e)}), e.status
    except Exception as e:
        app.logger.warning('delete_account %s failed: %s', g.user_id, e)
        return jsonify({'detail': 'Could not delete the account. Try again.'}), 503
    app.logger.info('deleted account %s: %s', g.user_id, counts)
    return jsonify({'deleted': True, 'rows': counts})


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
            # The generator echoes `program_start_date` into its result whenever
            # the caller asked for one, and _normalize_program_keys above has
            # already renamed it, so a bare row often still carries the start
            # date even though the envelope holding it was overwritten. Recover
            # it rather than writing null over a value that is sitting right
            # there; it is only genuinely unrecoverable when the generate did
            # not specify a start date at all.
            if 'currentProgram' not in program and program.get('weeks') is not None:
                app.logger.warning('healing envelope-less program for %s', user_id)
                ids, weights = _goal_ids_from_body({}, program)
                recovered_start = (program.get('programStartDate')
                                   or program.get('program_start_date'))
                program = {
                    'currentProgram':    program,
                    'programStartDate':  recovered_start,
                    'eventDate':         program.get('eventDate'),
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
                    track_id = _track_of_weeks(current)
                    if len(source_ids) == 1:
                        goal = _philosophy_to_goal(source_ids[0], all_frameworks, track_id)
                    elif len(source_ids) > 1:
                        weights = program.get('sourceGoalWeights') or {}
                        goal = _blend_philosophy_goals(source_ids, weights, all_frameworks,
                                                       track_id)
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
            revision = get_program_revision(user_id)
            program['revision'] = revision

            # Bootstrap the history for a program that predates it, and for one
            # generated before this endpoint last ran. Guarded by the revision
            # the response already carries, so the common case is one indexed
            # lookup rather than hashing a ~1 MB envelope on every app open.
            #
            # Archiving on READ, not only on write, is what preserves the full
            # copy: an iOS save strips `goal` and every exercise's `slot`, both
            # of which the progression endpoints read.
            from src import program_history
            try:
                if not program_history.is_archived(user_id, revision):
                    _record_program_history(user_id, program, 'heal', revision)
                program['programVersionId'] = program_history.active_version_id(user_id)
            except Exception as hist_err:
                app.logger.warning('program history bootstrap failed: %s', hist_err)
            current = program.get('currentProgram')
            if isinstance(current, dict) and current.get('weeks'):
                program['currentProgram'] = {
                    **current, 'phase_summary': _phase_summary(current['weeks'], current.get('goal'))}
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
        # A previewed program being started (both clients' Start): a rebuild of
        # the same block keeps the days already behind the athlete, as
        # generate's persist branch does. Only on request — an ordinary save
        # (a move into yesterday, a swap) must not be undone.
        keep_days_behind = bool(body.pop('keepDaysBehind', False))
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

            for field in ('constraints', 'validation', 'coverage_report'):
                if field in existing_cp and field not in current:
                    current[field] = existing_cp[field]

            if same_goal and 'goal' in existing_cp:
                current['goal'] = existing_cp['goal']
            elif new_ids:
                # Source goals changed — rebuild rather than inherit a stale goal.
                try:
                    all_frameworks = list(loader.load_all_frameworks().values())
                    if len(new_ids) == 1:
                        current['goal'] = _philosophy_to_goal(
                            new_ids[0], all_frameworks, _track_of_weeks(current))
                    else:
                        weights = body.get('sourceGoalWeights') or {}
                        current['goal'] = _blend_philosophy_goals(
                            new_ids, weights, all_frameworks, _track_of_weeks(current))
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

        kept_days = 0
        if keep_days_behind:
            stored = get_user_program(user_id)
            body, kept_days = _keep_days_behind_counted(
                user_id, _normalize_program_keys(stored) if stored else None, body)

        save_user_program(user_id, body)
        revision = get_program_revision(user_id)
        # After the save and after the 409 check: history must never claim a
        # plan the stale-revision guard rejected.
        history = _record_program_history(user_id, body, 'put', revision)
        saved = body.get('currentProgram') or {}
        return jsonify({
            'saved':            True,
            'revision':         revision,
            'historyRecorded':  bool(history.get('recorded')),
            'programVersionId': history.get('versionId'),
            # The saved weeks' summary: a client that moved, swapped or
            # spliced weeks shows phase changes for what it just saved.
            'phaseSummary':     _phase_summary(saved.get('weeks') or [], saved.get('goal')),
            # Elapsed days put back (keepDaysBehind): the saved weeks differ
            # from what the client sent, so it reads the program again.
            'keptDays':         kept_days,
        })
    except Exception as e:
        app.logger.warning('save_user_program error: %s', e)
        return jsonify({'saved': False, 'detail': str(e)}), 503


# The constraints a program records that a profile change can move.
_ADOPTABLE_CONSTRAINTS = ('equipment', 'training_level', 'injury_flags', 'days_per_week')


@app.patch('/api/user/program/constraints')
@require_auth
def adopt_program_constraints():
    """Record that the active program holds for the profile's new constraints.

    After POST /programs/constraint-change answered `affected: false`, the
    program is what the new constraints would build, so it now says it was
    built for them and the profile stops offering a regenerate. Merges only
    `equipment`, `training_level`, `injury_flags` and `days_per_week` (and
    `custom_injury_flags`); under the PUT's revision check. Constraints are
    outside the skeleton hash, so no program version is minted.
    """
    from src.db import get_program_revision, get_user_program, save_user_program
    body = request.get_json(silent=True) or {}
    patch = {k: v for k, v in (body.get('constraints') or {}).items() if k in _ADOPTABLE_CONSTRAINTS}
    if not patch and 'custom_injury_flags' not in body:
        return jsonify({'saved': False, 'detail': 'nothing to adopt'}), 422
    try:
        user_id = g.user_id
        base_rev = body.get('baseRevision')
        current_rev = get_program_revision(user_id)
        if base_rev is not None and current_rev is not None and str(base_rev) != str(current_rev):
            return jsonify({'saved': False, 'detail': 'stale_revision', 'currentRevision': current_rev}), 409
        stored = get_user_program(user_id) or {}
        stored = _normalize_program_keys(stored) if stored else {}
        program = stored.get('currentProgram')
        if not program:
            return jsonify({'saved': False, 'detail': 'no active program'}), 404
        program['constraints'] = {**(program.get('constraints') or {}), **patch}
        if 'custom_injury_flags' in body:
            program['constraints']['custom_injury_flags'] = body.get('custom_injury_flags') or []
        save_user_program(user_id, stored)
        return jsonify({'saved': True, 'revision': get_program_revision(user_id),
                        'constraints': program['constraints']})
    except Exception as e:
        app.logger.warning('adopt constraints error: %s', e)
        return jsonify({'saved': False, 'detail': str(e)}), 503


# ---------------------------------------------------------------------------
# Applying a progression adjustment
# ---------------------------------------------------------------------------
# progression_tracker.suggest_adjustments has always emitted hold_load,
# reduce_volume_10pct, early_deload, increase_increment and rebuild_habit as
# advice, and nothing applied them. These edit the stored weeks in place, from a
# week onward, under the same revision check as PUT. rebuild_habit is about the
# athlete's consistency, not the plan, so it stays advice.

def _adjust_round_kg(kg: float, step: float = 2.5) -> float:
    return round(kg / step) * step


def _adjust_target_matcher(target):
    """The tracker names targets as 'all', 'schedule', or a display list of
    exercise names ('Back Squat, Deadlift'); match ids and names, case-insensitively."""
    if not target or str(target).strip().lower() in ('all', 'schedule'):
        return lambda ex: True
    wanted = {t.strip().lower() for t in str(target).split(',') if t.strip()}
    return lambda ex: (str(ex.get('id', '')).lower() in wanted
                       or str(ex.get('name', '')).lower() in wanted)


def _adjust_each(weeks: list, start: int, matches):
    for wi in range(start, len(weeks)):
        for sessions in (weeks[wi].get('schedule') or {}).values():
            for session in sessions or []:
                for ea in session.get('exercises') or []:
                    ex = ea.get('exercise')
                    # A test's scored slot is a protocol; no adjustment rescales it.
                    if ex and matches(ex) and not ea.get('standard'):
                        yield wi, session, ea


def _adjust_hold_load(weeks, start, adj, exercises):
    matches = _adjust_target_matcher(adj.get('target'))
    held: dict = {}
    touched_weeks, n = set(), 0
    for wi, _session, ea in _adjust_each(weeks, start, matches):
        load = ea.get('load') or {}
        if load.get('weight_kg') is None:
            continue
        ex_id = ea['exercise']['id']
        held.setdefault(ex_id, load['weight_kg'])     # the first week's load is the one held
        if load['weight_kg'] != held[ex_id] or wi == start:
            load['weight_kg'] = held[ex_id]
            ea['load'] = load
            ea['load_note'] = f"Load held at {held[ex_id]:g} kg — adjustment applied"
            touched_weeks.add(wi); n += 1
    return {'weeks': sorted(touched_weeks), 'exercises': n}


_CONTINUOUS_VOLUME_KEYS = ('duration_minutes', 'time_minutes', 'distance_km', 'hold_seconds')


def _week_assignments_ordered(week: dict):
    """(session, assignment) pairs of a week in calendar order, so a cut that
    trims 'the last session first' is the same on every client — iOS re-encodes
    the schedule dictionary in arbitrary order."""
    schedule = week.get('schedule') or {}
    days = sorted(schedule, key=lambda d: _DAY_NAMES.index(d) if d in _DAY_NAMES else 99)
    for day in days:
        for session in schedule.get(day) or []:
            for ea in session.get('exercises') or []:
                if not ea.get('standard'):          # a test's protocol stays as written
                    yield session, ea


def _adjust_reduce_volume(weeks, start, adj, exercises):
    """Ten percent off each exercise's weekly volume.

    Discrete quantities (sets, AMRAP rounds) are cut per week, not per session:
    10% of three sets rounds back to three and nothing would ever change, while
    one set off nine weekly sets is the cut a coach makes. The last session of
    the week loses it first. Continuous ones (minutes, km, hold seconds) take
    ×0.9 directly.
    """
    matches = _adjust_target_matcher(adj.get('target'))
    touched_weeks, touched = set(), set()

    def mark(wi, ea, note):
        ea['load_note'] = note
        touched_weeks.add(wi); touched.add(id(ea))

    for wi in range(start, len(weeks)):
        by_ex: dict = {}
        for _session, ea in _week_assignments_ordered(weeks[wi]):
            ex = ea.get('exercise')
            if ex and matches(ex) and ea.get('load'):
                by_ex.setdefault(ex['id'], []).append(ea)
        for eas in by_ex.values():
            for ea in eas:
                load = ea['load']
                for key in _CONTINUOUS_VOLUME_KEYS:
                    v = load.get(key)
                    if isinstance(v, (int, float)) and v > 0:
                        new = round(v * 0.9, 1) if key == 'distance_km' else max(1, int(round(v * 0.9)))
                        if new != v:
                            load[key] = new
                            mark(wi, ea, 'Volume −10% — adjustment applied')
            for key in ('sets', 'target_rounds'):
                have = [ea for ea in eas if isinstance(ea['load'].get(key), (int, float))]
                total = sum(ea['load'][key] for ea in have)
                cut = max(1, int(round(total * 0.1))) if total >= 3 else 0
                for ea in reversed(have):            # last session of the week first
                    if cut <= 0:
                        break
                    if ea['load'][key] > 1:
                        ea['load'][key] = int(ea['load'][key]) - 1
                        mark(wi, ea, 'Volume −10% — adjustment applied')
                        cut -= 1
    return {'weeks': sorted(touched_weeks), 'exercises': len(touched)}


def _adjust_early_deload(weeks, start, adj, exercises):
    week = weeks[start]
    week['is_deload'] = True
    n = 0
    for sessions in (week.get('schedule') or {}).values():
        for session in sessions or []:
            session['is_deload'] = True
            for ea in session.get('exercises') or []:
                load = ea.get('load') or {}
                if not ea.get('exercise') or not load or ea.get('standard'):
                    continue
                if isinstance(load.get('weight_kg'), (int, float)):
                    load['weight_kg'] = _adjust_round_kg(load['weight_kg'] * 0.9)
                if isinstance(load.get('sets'), (int, float)) and load['sets'] > 1:
                    load['sets'] = max(1, int(round(load['sets'] * 0.6)))
                for key in ('duration_minutes', 'time_minutes'):
                    if isinstance(load.get(key), (int, float)) and load[key] > 0:
                        load[key] = max(1, int(round(load[key] * 0.6)))
                ea['load'] = load
                ea['load_note'] = 'Deload — reduced intensity (adjustment applied)'
                n += 1
    return {'weeks': [start], 'exercises': n}


def _adjust_increase_increment(weeks, start, adj, exercises):
    """One extra increment step per week after the current one, cumulatively —
    the exercise's own weekly_increment_kg, else the generator's default."""
    from src.progression import _DEFAULT_INCREMENT_KG
    matches = _adjust_target_matcher(adj.get('target'))
    touched_weeks, n = set(), 0
    for wi, _session, ea in _adjust_each(weeks, start + 1, matches):
        load = ea.get('load') or {}
        if not isinstance(load.get('weight_kg'), (int, float)):
            continue
        ex_def = exercises.get(ea['exercise']['id']) or {}
        inc = ex_def.get('weekly_increment_kg') or _DEFAULT_INCREMENT_KG
        extra = inc * (wi - start)
        load['weight_kg'] = _adjust_round_kg(load['weight_kg'] + extra)
        ea['load'] = load
        ea['load_note'] = f'+{extra:g} kg over the plan — increment raised'
        touched_weeks.add(wi); n += 1
    return {'weeks': sorted(touched_weeks), 'exercises': n}


_ADJUSTERS = {
    'hold_load': _adjust_hold_load,
    'reduce_volume_10pct': _adjust_reduce_volume,
    'early_deload': _adjust_early_deload,
    'increase_increment': _adjust_increase_increment,
}


def _current_week_index(start_date: str | None, n_weeks: int) -> int:
    """Array index of the calendar week the athlete is in, clamped to the plan."""
    from datetime import date as _date
    if not start_date or n_weeks <= 0:
        return 0
    try:
        days = (_date.today() - _date.fromisoformat(str(start_date)[:10])).days
    except Exception:
        return 0
    return max(0, min(days // 7, n_weeks - 1))


def apply_adjustment_to_weeks(weeks: list, start: int, adjustment: dict, exercises: dict) -> dict:
    """Pure: mutates `weeks` from index `start` and reports what changed."""
    kind = (adjustment or {}).get('type')
    if kind not in _ADJUSTERS:
        raise ValueError(f'unsupported adjustment type {kind!r}')
    stats = _ADJUSTERS[kind](weeks, start, adjustment, exercises)
    return {'type': kind, 'from_week_index': start, **stats}


@app.post('/api/programs/adjust')
@require_auth
def adjust_program():
    """Apply one suggested adjustment to the stored program from a week onward.

    Body: {adjustment: {type, target, magnitude}, from_week_index?, baseRevision?}.
    Answers 409 stale_revision like PUT /api/user/program, 422 for an adjustment
    that is advice rather than a plan edit, and returns the saved envelope so
    the client can replace its copy without a second round trip.
    """
    from src.db import get_user_program, save_user_program, get_program_revision
    body = request.get_json(silent=True) or {}
    adjustment = body.get('adjustment') or {}
    kind = adjustment.get('type')
    if kind not in _ADJUSTERS:
        return jsonify({'detail': f'adjustment type {kind!r} is advice, not a plan edit',
                        'supported': sorted(_ADJUSTERS)}), 422
    user_id = g.user_id
    envelope = get_user_program(user_id)
    if not isinstance(envelope, dict):
        return jsonify({'detail': 'no program'}), 404
    envelope = _normalize_program_keys(envelope)
    current = envelope.get('currentProgram') or {}
    weeks = current.get('weeks') or []
    if not weeks:
        return jsonify({'detail': 'no program'}), 404

    base_rev = body.get('baseRevision')
    if base_rev is not None:
        current_rev = get_program_revision(user_id)
        if current_rev is not None and str(base_rev) != str(current_rev):
            return jsonify({'saved': False, 'detail': 'stale_revision',
                            'currentRevision': current_rev}), 409

    start = body.get('from_week_index')
    start = _current_week_index(envelope.get('programStartDate'), len(weeks)) if start is None \
        else max(0, min(int(start), len(weeks) - 1))
    exercises, _ = loader.load_all_exercises()
    applied = apply_adjustment_to_weeks(weeks, start, adjustment, exercises)
    current['weeks'] = weeks
    try:
        current['volume_summary'] = [_week_volume(w) for w in weeks]
    except Exception:
        pass
    envelope['currentProgram'] = current

    save_user_program(user_id, envelope)
    revision = get_program_revision(user_id)
    history = _record_program_history(user_id, envelope, 'adjust', revision)
    program = {**envelope, 'revision': revision, 'programVersionId': history.get('versionId'),
               'currentProgram': {**current, 'phase_summary': _phase_summary(weeks, current.get('goal'))}}
    return jsonify({'saved': True, 'revision': revision,
                    'programVersionId': history.get('versionId'),
                    'applied': applied, 'program': program})


# ---------------------------------------------------------------------------
# Watch device pairing (Garmin / future companions)
# ---------------------------------------------------------------------------
# A watch mints a pending pairing with no auth, shows the code (QR/text), then
# polls status until a signed-in user claims the code and binds the token.

# ---------------------------------------------------------------------------
# Program history
# ---------------------------------------------------------------------------
# Answers the two questions a single mutable user_programs row could not: which
# plan was in force when, and what did it plan for a given day. Both matter after
# a program has been replaced — see src/program_history.py.

@app.get('/api/programs/history')
@require_auth
def programs_history():
    """The athlete's program timeline, newest first."""
    from src import program_history
    return jsonify(program_history.list_activations(g.user_id))


@app.get('/api/programs/history/<version_id>')
@require_auth
def programs_history_version(version_id: str):
    """One archived program: its frozen envelope and its flattened sessions.

    The sessions are NOT filtered by the activation interval — browsing a
    finished block should show the whole plan, including the weeks it never got
    to run, with `wasEffective` saying which is which.
    """
    from src import program_history
    version = program_history.get_version(g.user_id, version_id)
    if not version:
        return jsonify({'error': 'not_found'}), 404

    activations = [a for a in program_history.list_activations(g.user_id)
                   if a['versionId'] == version_id]
    windows = [(a['effectiveFrom'], a['effectiveTo']) for a in activations]

    def was_effective(day: str) -> bool:
        return any(day >= start and (end is None or day < end) for start, end in windows)

    # Same join the planned-sessions endpoint does: the page shows what was
    # planned AND what came of it, and without these the detail view could never
    # render the logged/matched markers it draws.
    matches = {m['sessionUid']: m for m in _health.get_matches(g.user_id)
               if m.get('sessionUid') and m['matchConfidence'] != 'rejected'}
    logs = _health.get_session_logs_by_uid(g.user_id)

    sessions = []
    for row in program_history.sessions_for_version(g.user_id, version_id):
        day = str(row['date'])
        match = matches.get(row['session_uid'])
        sessions.append({
            'sessionUid':     row['session_uid'],
            'date':           day,
            'weekIndex':      row['week_index'],
            'weekNumber':     row['week_number'],
            'dayName':        row['day_name'],
            'sessionIndex':   row['session_index'],
            'sessionKey':     row['legacy_key'],
            'modality':       row['modality'],
            'archetypeId':    row['archetype_id'],
            'archetypeName':  row['archetype_name'],
            'durationMinutes': row['duration_min'],
            'phase':          row['phase'],
            'isDeload':       row['is_deload'],
            'wasEffective':   was_effective(day),
            'matchedWorkoutId': match['importedWorkoutId'] if match else None,
            'completedAt':    (logs.get(row['session_uid']) or {}).get('completedAt') or None,
        })

    version['activations'] = activations
    version['sessions'] = sessions
    return jsonify(version)


def _planned_sessions_json(user_id: str, from_date: str, to_date: str,
                           all_matches: list[dict] | None = None) -> list[dict]:
    """What was planned on each day in a range, across every program, each row
    with the match and the log attached (`GET /programs/planned-sessions`,
    `GET /health/linking`, which passes the matches it already read)."""
    from src import program_history
    rows = program_history.planned_sessions_between(user_id, from_date, to_date)

    if all_matches is None:
        all_matches = _health.get_matches(user_id)
    matches = {m['sessionUid']: m for m in all_matches
               if m.get('sessionUid') and m['matchConfidence'] != 'rejected'}
    logs = _health.get_session_logs_by_uid(user_id)

    out = []
    for row in rows:
        uid = row['session_uid']
        match = matches.get(uid)
        out.append({
            'sessionUid':      uid,
            'programVersionId': row['program_version_id'],
            'date':            str(row['date']),
            'weekIndex':       row['week_index'],
            'weekNumber':      row['week_number'],
            'dayName':         row['day_name'],
            'sessionIndex':    row['session_index'],
            'sessionKey':      row['legacy_key'],
            'modality':        row['modality'],
            'archetypeId':     row['archetype_id'],
            'archetypeName':   row['archetype_name'],
            'durationMinutes': row['duration_min'],
            'phase':           row['phase'],
            'isDeload':        row['is_deload'],
            'matchedWorkoutId': match['importedWorkoutId'] if match else None,
            'completedAt':     (logs.get(uid) or {}).get('completedAt') or None,
        })
    return out


@app.get('/api/programs/planned-sessions')
@require_auth
def programs_planned_sessions():
    """What was actually planned on each day in a range, across every program.

    `from` and `to` are inclusive ISO dates; the range defaults to the last 90
    days. Each session carries the match and the log attached to it, so a
    calendar or a confirm dialog can show planned against actual for a date that
    belongs to a block the athlete has long since replaced.
    """
    from src import program_history
    try:
        to_date = _date.fromisoformat(request.args.get('to') or str(_date.today()))
        from_date = _date.fromisoformat(
            request.args.get('from') or str(to_date - _timedelta(days=90)))
    except ValueError:
        return jsonify({'error': 'bad_date'}), 400
    if from_date > to_date:
        from_date, to_date = to_date, from_date

    out = _planned_sessions_json(g.user_id, str(from_date), str(to_date))
    return jsonify({'from': str(from_date), 'to': str(to_date), 'sessions': out})


@app.post('/api/devices/pair')
def devices_pair():
    """Unauthenticated: a watch requests a pairing code + device token."""
    from src import device_store
    body = request.get_json(silent=True) or {}
    part = body.get('partNumber') if isinstance(body.get('partNumber'), str) else None
    name = body.get('deviceName') if isinstance(body.get('deviceName'), str) else None
    result = device_store.create_pairing(device_name=device_store.device_label(part and part[:32], name and name[:64]))
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


def _watch_mmss(sec) -> str:
    return f'{int(sec) // 60}:{int(sec) % 60:02d}'


def _fmt_watch_load(slot_type: str, load: dict, rest_until_hr: int | None = None) -> str:
    sets = _pick(load, 'sets')
    sw = _pick(load, 'switch_at_sec', 'switchAtSec')
    switch = f', switch at {_watch_mmss(sw)}' if sw else ''
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
            return f'{mins} min{switch}' + (f' — {zt}' if zt else '')
        return 'Duration TBD'
    if slot_type == 'emom':
        mins = _pick(load, 'time_minutes', 'timeMinutes')
        rounds = _pick(load, 'target_rounds', 'targetRounds')
        work = _pick(load, 'work_sec', 'workSec')
        rest = _pick(load, 'rest_sec', 'restSec')
        if rounds is not None and work:
            # e.g. "8 x 20s/10s" (Tabata), "10 x 60s" (EMOM strength) or
            # "20 x 15s, rest to HR 129" (a rest that ends on heart rate)
            if rest and rest_until_hr:
                return f'{rounds} x {work}s, rest to HR {rest_until_hr}{switch}'
            span = f'{work}s/{rest}s' if rest else f'{work}s'
            reps = _pick(load, 'reps_per_round', 'repsPerRound')
            bell = _pick(load, 'weight_kg', 'weightKg')
            return (f'{rounds} x {span}' + (f' · {reps} reps/round' if reps is not None else '')
                    + (f' @ {bell:g} kg' if bell is not None else '') + switch)
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


_EXERCISE_BELLS: dict | None = None


def _exercise_bells() -> dict:
    """{exercise id: bells} for the double-bell exercises (exercises.yaml
    `bells`), read once. A program stored before the field keeps its own copy
    of each exercise, so the watch reads the library's."""
    global _EXERCISE_BELLS
    if _EXERCISE_BELLS is None:
        index, _ = loader.load_all_exercises()
        _EXERCISE_BELLS = {i: e['bells'] for i, e in index.items() if e.get('bells')}
    return _EXERCISE_BELLS


def _rest_until_hr(load: dict, max_hr: int | None) -> int | None:
    """An HR-gated rest's heart rate in bpm: the slot's share of the athlete's
    max HR (`rest_until_hr_pct`, progression.watch_cues), the shared default
    max HR when the athlete's is not known."""
    pct = _pick(load, 'rest_until_hr_pct', 'restUntilHrPct')
    if not pct:
        return None
    if not max_hr:
        from src.analytics import zones as _zones
        max_hr = _zones.default_max_hr()
    return int(round(max_hr * float(pct) / 100))


def _encode_watch_exercise(ea: dict, modality: str, max_hr: int | None = None) -> dict | None:
    """Project one exercise assignment into the compact watch shape.

    Slots flagged `skip_exercise` (BJJ drilling/rolling rounds, circuit round
    wrappers) resolve to no exercise at all. Returning None for those meant a
    whole bjj_class session arrived at the watch as an empty exercise list, so
    they are projected as named meta blocks instead.

    `bells`, `switchAtSec` and `restUntilHr` are sent only when they apply —
    the Garmin parses the whole day in a small heap.
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
    gate = _rest_until_hr(load, max_hr)

    out = {
        'exerciseId': ex.get('id'),
        'name': ex.get('name') or _humanize_role(slot_role),
        'slotType': slot_type,
        'slotRole': slot_role,
        'isMeta': is_meta,
        'loadDescription': _fmt_watch_load(slot_type, load, rest_until_hr=gate),
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
        # A paced slot's pace, from the exercise's competition cap
        # (progression.paced_rpm); absent otherwise, never a default.
        'targetRpm': _pick(load, 'target_rpm', 'targetRpm'),
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
        # A test's scored slot ({id, result}); encode_watch_session turns it
        # into the compact `standard` with `?spec=1` and drops it otherwise.
        '_standard': ea.get('standard'),
    }
    # Bells held at once (2 for a double; the weight is one bell's), a hand
    # switch so many seconds into the work, and an interval rest that ends
    # once heart rate is under this bpm (rest_sec is then its cap).
    bells = ex.get('bells') or (_exercise_bells().get(ex.get('id')) if ex.get('id') else None)
    if bells and bells != 1:
        out['bells'] = bells
    sw = _pick(load, 'switch_at_sec', 'switchAtSec')
    if sw:
        out['switchAtSec'] = sw
    if gate:
        out['restUntilHr'] = gate
    return out


def encode_watch_session(s: dict, session_key: str, *, completed: bool = False,
                         spec_level: int = 0, last: dict | None = None,
                         results: dict | None = None, sex: str = 'male',
                         max_hr: int | None = None) -> dict:
    """One stored session in the watch's shape.

    With spec_level >= 1 the session also says which package owns it and
    carries that package's resolved screens (src/watch_spec.py): `watch` holds
    the package-level settings, `screens` the deduplicated specs, and each
    exercise names its spec by `screen`. garmin/tools/gen_watch_demo.py encodes
    the demo programmes through this too, so demo and real sessions agree.

    A test's scored slot also carries `standard` — its short name, result
    kind, best and the number for the next level (`standards.watch_standard`,
    from `results`, summarise()'s standards; the entry level without one) —
    and its screen shows it (`standard_target`), whatever the package's spec
    says. Only with `?spec=1`, and only on test slots: the Garmin payload is
    small.
    """
    modality = s.get('modality') or ''
    archetype = s.get('archetype') or {}
    exercises = [e for e in (_encode_watch_exercise(ea, modality, max_hr)
                             for ea in (s.get('exercises') or [])) if e is not None]
    refs = [e.pop('_standard', None) for e in exercises]
    out = {
        'sessionId': session_key,
        'completed': completed,
        'modalityId': modality,
        # Archetype identity drives the category icon, and on builds before 1.4
        # the watch's per-archetype behaviour table.
        'archetypeId': archetype.get('id'),
        'archetypeName': archetype.get('name') or modality,
        'archetypeCategory': archetype.get('category'),
        'estimatedMinutes': _pick(archetype, 'duration_estimate_minutes', 'durationEstimateMinutes') or 45,
        'isDeload': bool(_pick(s, 'is_deload', 'isDeload')),
        'exercises': exercises,
    }
    if spec_level >= 1:
        package_id = _watch_spec.session_package(s)
        table, keys = _watch_spec.session_screens(
            package_id, archetype.get('id'),
            [(e['slotRole'] or None, e['slotType']) for e in exercises],
        )
        by_id = _bd.by_id() if any(refs) else {}
        for e, key, ref in zip(exercises, keys, refs):
            e['screen'] = key
            # What was done last time ("24kg × 10"), src/last_time.py.
            if last and e.get('exerciseId') in last:
                e['last'] = last[e['exerciseId']]
            sid = (ref.get('id') if isinstance(ref, dict) else ref) if ref else None
            if sid in by_id:
                e['standard'] = _standards_mod.watch_standard(
                    by_id[sid], (results or {}).get(sid), sex,
                    ref.get('result') if isinstance(ref, dict) else None)
                e['screen'] = _watch_spec.with_lines(table, key, 'standard_target')
        out['packageId'] = package_id
        out['watch'] = _watch_spec.session_identity(package_id)
        out['screens'] = table
    return out


def _today_match_sets(matches: list[dict]) -> tuple[set, set]:
    """(session uids, legacy keys) of the athlete's live matches. A match that
    carries a uid is known only by it, so another version's '3-Friday-0' never
    marks this version's session done, and an unscoped match whose workout
    does not fall on this program's date for its key is not live either."""
    uids, keys = set(), set()
    for m in matches:
        if m.get('matchConfidence') == 'rejected' or m.get('inCurrentProgram') is False:
            continue
        if m.get('sessionUid'):
            uids.add(m['sessionUid'])
        elif m.get('sessionKey'):
            keys.add(m['sessionKey'])
    return uids, keys


def _active_version_or_none(user_id: str) -> str | None:
    try:
        from src import program_history
        return program_history.active_version_id(user_id)
    except Exception:
        return None


def _program_history_uid(vid: str | None, week_index: int, day_name: str, i: int) -> str | None:
    if not vid:
        return None
    from src import program_history
    return program_history.session_uid(vid, week_index, day_name, i)


def _watch_progress(user_id: str, program: dict, weeks: list, start: _date, today: _date,
                    week_index: int, is_done) -> dict:
    """Progress for a watch: this program week's sessions done of those due
    and of all it holds, the program's so far, and the methodology's headline
    sentence (Today's Progress card).

    The counts are the same done test as each session's `completed` — a log
    with a completion time or a matched workout — over dates, never the
    analytics engine, so the morning sync stays a few dict lookups. The
    headline is the program analytics document's cached copy, which the
    phone and the web write when they open it; a watch never computes one.
    """
    def tally(w_index: int, until: _date | None):
        done = due = total = 0
        w = weeks[w_index]
        for offset in range(7):
            d = start + _timedelta(days=w_index * 7 + offset)
            d_name = _DAY_NAMES[d.weekday()]
            for i, _s in enumerate((w.get('schedule') or {}).get(d_name) or []):
                total += 1
                finished = is_done(w_index, d_name, i)
                done += int(finished)
                if until is None or d <= until or finished:
                    due += 1
        return done, due, total

    w_done, w_due, w_total = tally(week_index, today)
    p_done = p_due = 0
    for wi in range(week_index + 1):
        d, due, _ = tally(wi, today)
        p_done += d
        p_due += due
    out = {
        'week': {'number': week_index + 1, 'of': len(weeks), 'done': w_done, 'due': w_due, 'sessions': w_total},
        'program': {'done': p_done, 'due': p_due,
                    'pct': round(100 * p_done / p_due) if p_due else None},
    }
    try:
        key = f"{start.isoformat()}:{(program.get('sourceGoalIds') or ['-'])[0]}"
        cached = _health.get_progression_snapshot(user_id, key, 'program')
        method = (((cached or {}).get('data') or {}).get('methodologies') or [None])[0] or {}
        h = method.get('headlineSummary')
        if h:
            out['headline'] = {k: h.get(k) for k in ('label', 'text', 'trendText', 'status')}
    except Exception:
        pass
    return out


@app.get('/api/user/today-session')
@require_auth
def get_today_session():
    """Compact projection of today's scheduled session(s) for the watch companion.

    Server-side port of ios/.../WatchSessionManager.syncProgram(): derives the
    current week + weekday from programStartDate and returns only the fields the
    slot-type views need. ?date=YYYY-MM-DD names the day; the watch sends its own
    local date, because the server's is UTC. ?week=1 adds `days`, today and the
    six after it (within the program), for the watch's Week menu.
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

    # Which of today's sessions are already done, for the watch glance's ring:
    # a session log with a completion time, or a workout matched to the session
    # (so a workout recorded on the phone or another watch counts too).
    # The key ('3-Friday-0') repeats across program versions, so a match that
    # names a session uid counts only for this version's session; a legacy
    # match without one still counts by key.
    session_logs = _health.get_session_logs(g.user_id)
    matched_uids, matched_keys = _today_match_sets(_health.get_matches(g.user_id))
    vid = _active_version_or_none(g.user_id)

    # ?spec=1: the watch build reads package screen specs. Without it the
    # payload is what builds before 1.4 parse, key for key.
    try:
        spec_level = int(request.args.get('spec') or 0)
    except ValueError:
        spec_level = 0

    def is_done(w_index: int, d_name: str, i: int) -> bool:
        w = weeks[w_index]
        session_key = f"{_pick(w, 'week_number', 'weekNumber')}-{d_name}-{i}"
        log = session_logs.get(session_key) or {}
        uid = _program_history_uid(vid, w_index, d_name, i)
        matched = (uid in matched_uids) if uid else False
        return bool(log.get('completedAt')) or matched or session_key in matched_keys

    # What was done last time, per exercise: this program's logs and earlier
    # programs' (a regenerate mints a new version and would otherwise empty
    # it). Never fails the sync: without it the watch shows no "last".
    last = None
    if spec_level >= 1:
        try:
            from src import last_time as _last_time
            tz = (_db.get_user_profile(g.user_id) or {}).get('timezone')
            last = _last_time.last_by_exercise(
                list(session_logs.values()) + list(_health.get_session_logs_by_uid(g.user_id).values()),
                str(today), tz=tz)
        except Exception as e:
            app.logger.warning('today-session: last time failed: %s', e)

    # A test today: each scored slot says its standard's best and the number
    # for the next level. Read only when today has a test.
    std_results, std_sex = None, 'male'
    if spec_level >= 1 and any(ea.get('standard') for s in sessions for ea in (s.get('exercises') or [])):
        try:
            std_sex, std_tz = _standards_context(g.user_id)
            std_results = _standards_mod.summarise(
                _bd.load_benchmarks(), _health.get_performance_logs(g.user_id), std_sex, std_tz)['standards']
        except Exception as e:
            app.logger.warning('today-session: standards failed: %s', e)

    # The athlete's max HR (hrConfig, else 220 − age): an HR-gated rest's bpm
    # on both watches, and with ?spec=1 the Apple Watch's zone alerts.
    try:
        max_hr = _get_user_max_hr(g.user_id)
    except Exception as e:
        app.logger.warning('today-session: max HR failed: %s', e)
        max_hr = None

    def encode_day(w_index: int, d_name: str, level: int) -> list[dict]:
        w = weeks[w_index]
        out = []
        for i, s in enumerate((w.get('schedule') or {}).get(d_name) or []):
            session_key = f"{_pick(w, 'week_number', 'weekNumber')}-{d_name}-{i}"
            out.append(encode_watch_session(
                s, session_key, completed=is_done(w_index, d_name, i), spec_level=level,
                last=last if level >= 1 else None, results=std_results, sex=std_sex,
                max_hr=max_hr,
            ))
        return out

    out_sessions = encode_day(week_index, day_name, spec_level)

    try:
        bio, sources = _bio_for_scoring(g.user_id, days=14)
        readiness = _compute_readiness(
            bio, session_logs, user_id=g.user_id, sources=sources,
        )
    except Exception:
        readiness = None

    # Tomorrow's first session, for the glance's rest-day and evening preview.
    tomorrow = None
    t_index = (days_since + 1) // 7
    if t_index < len(weeks):
        t_day = _DAY_NAMES[(today.weekday() + 1) % 7]
        t_sessions = (weeks[t_index].get('schedule') or {}).get(t_day) or []
        if t_sessions:
            first = t_sessions[0]
            t_arch = first.get('archetype') or {}
            tomorrow = {
                'dayName': t_day,
                'sessionCount': len(t_sessions),
                'modalityId': first.get('modality') or '',
                'archetypeName': t_arch.get('name') or first.get('modality') or '',
                'estimatedMinutes': _pick(t_arch, 'duration_estimate_minutes', 'durationEstimateMinutes') or 45,
            }
        else:
            tomorrow = {'dayName': t_day, 'sessionCount': 0}

    body = {
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
        'tomorrow': tomorrow,
        'progress': _watch_progress(g.user_id, program, weeks, start, today, week_index, is_done),
    }
    if spec_level >= 1:
        body['specVersion'] = _watch_spec.spec_version()
        # For the zone alerts of a watch that cannot read zones off the
        # device: the Apple Watch, whose phone used to work it out from a date
        # of birth of its own. The Garmin reads its zones from the watch
        # (UserProfile).
        if max_hr is not None:
            body['maxHR'] = max_hr
    if request.args.get('week') == '1':
        # The demo's day shape ({offset, title, sessions}). No screen specs: the
        # Week menu lists sessions and their steps, it never runs them.
        days = []
        for offset in range(7):
            d_since = days_since + offset
            if d_since // 7 >= len(weeks):
                break
            d_name = _DAY_NAMES[(today.weekday() + offset) % 7]
            d_sessions = encode_day(d_since // 7, d_name, 0)
            title = d_sessions[0]['archetypeName'] if d_sessions else 'Rest'
            if len(d_sessions) > 1:
                title += f' +{len(d_sessions) - 1}'
            days.append({'offset': offset, 'date': str(today + _timedelta(days=offset)),
                         'title': title, 'sessions': d_sessions})
        body['days'] = days
    return jsonify(body)


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


@app.get('/api/health/linking')
@require_auth
def health_linking():
    """Log ▸ Linking for a client with no matcher of its own (the phone): one
    card per day, workouts beside the sessions planned that day, existing
    links, and same-day suggestions (`src/linking.py`, the server's copy of
    the web's `lib/linking.ts`).

    `today` is the athlete's date (the server's is UTC); `dismissed` repeats,
    each `<workoutId>|<session key>` the athlete waved away on that device.
    """
    from src import linking, program_history
    from src.db import get_user_program
    try:
        today = str(_date.fromisoformat(request.args.get('today') or str(_date.today())))
    except ValueError:
        return jsonify({'error': 'bad_date'}), 400
    dismissed = frozenset(d for d in request.args.getlist('dismissed') if '|' in d)

    workouts = _health.get_workouts(g.user_id, summary_only=True)
    all_matches = _health.get_matches(g.user_id)
    envelope = get_user_program(g.user_id)
    envelope = _normalize_program_keys(envelope) if isinstance(envelope, dict) else {}
    try:
        version_id = program_history.active_version_id(g.user_id)
        oldest = min((w['date'] for w in workouts if w.get('date')), default=today)
        history = _planned_sessions_json(g.user_id, min(oldest, today), today, all_matches)
        labels = {a['versionId']: a.get('goalName') or a['label']
                  for a in program_history.list_activations(g.user_id)}
    except Exception as hist_err:            # no history tables: current program only
        app.logger.warning('linking history unavailable: %s', hist_err)
        version_id, history, labels = None, [], {}

    days = linking.build_linking_days(
        workouts=workouts,
        matches=all_matches,
        pending=_health.get_match_suggestions(g.user_id),
        program=envelope.get('currentProgram'),
        program_start_date=envelope.get('programStartDate'),
        program_version_id=version_id,
        history=history,
        today=today,
        dismissed=dismissed,
    )
    return jsonify({'today': today, 'programVersionId': version_id,
                    'days': linking.to_wire(days, labels)})


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

    # raise_on_error: this is an automatic import path. Reporting success for a
    # write that failed loses the workout with nothing to retry from — the
    # client commits its HealthKit anchor on a 2xx and never offers it again.
    written = _health.upsert_workouts(g.user_id, workouts, raise_on_error=True)

    result = {'saved': written}
    if auto_match:
        from src import workout_matcher
        result['matched'] = workout_matcher.match_and_store(g.user_id, workouts)
    # After matching, so a run matched to a test session reads as that test.
    from src import standard_results
    standards = standard_results.after_workouts_import(g.user_id, workouts)
    if standards is not None:
        result['standards'] = standards
    return jsonify(result)


@app.delete('/api/health/workouts/<workout_id>')
@require_auth
def health_delete_workout(workout_id: str):
    _health.delete_workout(g.user_id, workout_id)
    return jsonify({'deleted': workout_id})


@app.get('/api/health/sessions/recent')
@require_auth
def health_recent_sessions():
    """Recent session logs, each naming the planned session it belongs to.

    A log's `session_key` is program-relative and stops resolving once the
    plan is replaced; its `session_uid` does not. The planned-sessions row
    for that uid gives the archetype name, modality, date and position, so a
    client can title a log from an earlier plan instead of showing its key.
    """
    from src import program_history
    logs = _health.get_recent_session_logs(g.user_id)
    try:
        planned = program_history.planned_rows_for_uids(
            g.user_id, [l.get('session_uid') for l in logs if l.get('session_uid')])
    except Exception as exc:
        app.logger.warning('recent sessions: planned lookup failed: %s', exc)
        planned = {}
    program_history.annotate_logs(logs, planned)
    return jsonify(logs)


@app.get('/api/health/bio/recent')
@require_auth
def health_recent_bio():
    return jsonify(_health.get_recent_bio_logs(g.user_id))


def _normalise_fatigue(log: dict) -> dict:
    """Fatigue is 1–5 on the web and in the type; the iOS slider sends 1–10.

    _score_fatigue assumes 1–5, so an iOS 7/10 read as "high accumulated
    fatigue". Anything above 5 is folded onto the 1–5 scale here, once, at the
    boundary, rather than in every reader.
    """
    import math
    for key in ('fatigueRating', 'fatigue_rating'):
        v = log.get(key)
        if isinstance(v, (int, float)) and v > 5:
            log[key] = int(math.ceil(v / 2))
    if 'fatigue_rating' in log and 'fatigueRating' not in log:
        log['fatigueRating'] = log.pop('fatigue_rating')
    return log


@app.put('/api/health/sessions/<path:session_key>/notes')
@require_auth
def health_upsert_session_notes(session_key: str):
    """Notes and fatigue only — the route the iOS app has been calling.

    It never existed: `<path:session_key>` on the route below swallowed the
    `/notes` suffix, so every note and fatigue rating the phone saved landed in
    a phantom row keyed "1-Monday-0/notes" and was invisible to analytics.
    Registered with a static suffix, which werkzeug ranks above the path
    catch-all; test_program_analytics.py asserts the routing.
    """
    body = _normalise_fatigue(request.get_json(silent=True) or {})
    log = {'sessionKey': session_key, 'notes': body.get('notes', ''),
           'exercises': {}, 'source': body.get('source') or 'ios'}
    if body.get('fatigueRating') is not None:
        log['fatigueRating'] = body['fatigueRating']
    if _health.upsert_session_log(g.user_id, log) is None:
        return jsonify({'detail': 'could not save the session log'}), 503
    return jsonify({'saved': session_key})


@app.delete('/api/health/sessions/<path:session_key>/completion')
@require_auth
def health_clear_session_completion(session_key: str):
    """Undo "mark complete" for one session.

    The upsert keeps the later of the stored and incoming `completed_at`
    (GREATEST), so a PUT can never clear it — which is why the iOS undo was
    client-only and the session came back completed on the next sync. Clears
    the timestamp and leaves sets, notes, fatigue and HR in place. Static
    suffix for the same reason as `/notes` above.
    """
    _health.clear_session_completion(g.user_id, session_key)
    return jsonify({'cleared': session_key})


@app.put('/api/health/sessions/by-uid/<path:session_uid>')
@require_auth
def health_upsert_session_by_uid(session_uid: str):
    """Write a session log against a planned session's durable identity.

    The route below takes the program-relative key ('3-Monday-0'), which names a
    different session in every plan the athlete has ever had; the server has to
    guess which program is meant. A client that knows the session_uid — which
    GET /api/programs/planned-sessions hands out — says it outright, and the log
    is unambiguous even for a session in a block that has since been replaced.

    The session key is still stored alongside, because plenty of readers speak
    only that; it is recovered from the uid when the body omits it.
    """
    log = _normalise_fatigue(request.get_json(silent=True) or {})
    log['sessionUid'] = session_uid
    if not log.get('sessionKey'):
        from src import program_history
        planned = program_history.resolve_session(g.user_id, session_uid=session_uid)
        log['sessionKey'] = planned['legacy_key'] if planned else session_uid
    return _save_session_log(log, {'saved': session_uid, 'sessionKey': log['sessionKey']})


@app.post('/api/health/sessions/<path:session_key>/confirm')
@require_auth
def health_confirm_session(session_key: str):
    """"Done as written": {clean: bool, rpe: 1-10} for a training-contract
    session (Wildman, BJJ). Writes each progressing exercise's prescribed
    rounds or seconds with the answer (src/training_contract
    .confirmation_outcomes), merged into its log, and completes the session if
    it was not. Only a clean session at or below the module's RPE advances it
    when the program is next regenerated (`confirmed_state`); a watch-recorded
    or linked workout logs no per-exercise outcome, so none ever did.

    A loaded lift (Starting Strength) is made or missed: `lifts` —
    {exercise id: {made: bool, weightKg?: number}} — says which and at what
    weight; `clean: true` alone means every lift was made as prescribed.
    `clean: false` without `lifts` is 422 there, so an older client's
    "not clean" cannot count every lift as missed and reset it.

    404 when the key names no session of the current program; 422 when the
    session has no modules or the answer is malformed."""
    from src import program_history, training_contract
    from src.db import get_user_program
    body = request.get_json(silent=True) or {}
    clean, rpe, lifts = body.get('clean'), body.get('rpe'), body.get('lifts')
    if not isinstance(clean, bool) or (rpe is not None and (isinstance(rpe, bool) or not isinstance(rpe, int)
                                                           or not 1 <= rpe <= 10)):
        return jsonify({'detail': 'clean (true/false) and rpe (1-10) are required'}), 422
    if lifts is not None and (not isinstance(lifts, dict) or any(
            not isinstance(v, dict) or not isinstance(v.get('made'), bool)
            or (v.get('weightKg') is not None and (isinstance(v['weightKg'], bool)
                                                  or not isinstance(v['weightKg'], (int, float))
                                                  or not v['weightKg'] > 0))
            for v in lifts.values())):
        return jsonify({'detail': 'lifts maps exercise ids to {made: true/false, weightKg?: kg}'}), 422
    uid = program_history.active_session_uid(g.user_id, session_key)
    planned = program_history.resolve_session(g.user_id, session_uid=uid) if uid else None
    program = program_history.unwrap(get_user_program(g.user_id) or {})
    try:
        session = program['weeks'][planned['week_index']]['schedule'][planned['day_name']][planned['session_index']]
    except (KeyError, IndexError, TypeError):
        return jsonify({'detail': f'{session_key!r} is no session of the current program'}), 404
    if not session.get('modules'):
        return jsonify({'detail': 'this session has no training-contract modules to confirm'}), 422
    if not clean and not lifts and any(m.get('lifts') for m in session['modules']):
        return jsonify({'detail': 'say which lifts were missed: lifts {exercise id: {made, weightKg}}'}), 422
    existing = _health.get_session_log(g.user_id, uid, session_key) or {}
    outcomes = training_contract.confirmation_outcomes(session, clean, rpe, existing.get('exercises'), lifts)
    # A work-up made with no weight would count the session and leave the
    # lift where it was: the next one would ask for another work-up.
    unweighed = sorted(eid for m in session['modules'] for eid in (m.get('lifts') or {})
                       if (outcomes.get(eid) or {}).get('made') and (outcomes.get(eid) or {}).get('weightKg') is None)
    if unweighed:
        return jsonify({'detail': f"enter the weight you worked up to: {', '.join(unweighed)}"}), 422
    log = {'sessionKey': session_key, 'sessionUid': uid, 'source': existing.get('source') or 'web',
           'notes': existing.get('notes') or '',
           'exercises': outcomes}
    if not existing.get('completedAt'):
        log['completedAt'] = _datetime.now(_timezone.utc).isoformat()
    # The answer carries what was written, so a client shows it without a reload.
    return _save_session_log(log, {'confirmed': session_key, 'clean': clean, 'rpe': rpe, 'lifts': lifts,
                                   'exercises': log['exercises'],
                                   'completedAt': log.get('completedAt') or existing.get('completedAt')})


@app.put('/api/health/sessions/<path:session_key>')
@require_auth
def health_upsert_session(session_key: str):
    """Write a session log under its program-relative key.

    `standardResults` — {standardId: {decision: save|dismiss, value?|text?}}
    — carries a watch's answer to "save this result?" for a test it ran; it
    is honoured only for standards that session tests, so a device token
    (auth.DEVICE_ROUTES) reaches no further than the session it logged.
    """
    log = _normalise_fatigue(request.get_json(silent=True) or {})
    log['sessionKey'] = session_key
    return _save_session_log(log, {'saved': session_key})


def _save_session_log(log: dict, answer: dict):
    """Store a log, then read it for the standards it bears on.

    503 when the write fails (it answered "saved" over a lost write for as
    long as the store swallowed errors). A test slot's logged outcome comes
    back as `standards.pending` — a suggestion, never yet a result — and
    whatever went wrong reading it as `standards.error`; the log is kept
    either way (src/standard_results.py).
    """
    from src import standard_results
    row = _health.upsert_session_log(g.user_id, log)
    if row is None:
        return jsonify({'detail': 'could not save the session log'}), 503
    standards = standard_results.after_session_log(g.user_id, log, row, session_uid=row.get('session_uid'))
    if standards is not None:
        answer['standards'] = standards
    return jsonify(answer)


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


@app.post('/api/health/wellness')
@require_auth
def health_post_wellness():
    """One day's wellness reading from the Connect IQ watch (src/wellness.py).

    422 with the error list for a reading that fails validation — the watch
    drops it, since resending cannot fix it. 503 when the write fails, so the
    watch keeps the reading and retries. Repeats of a day merge
    (src/wellness_store.py), so a retry after a lost response is harmless. A
    Garmin toggle that is off answers 200 with `stored: false`: the athlete
    chose that, and a retry would not change it.
    """
    from src import wellness, wellness_store
    row, errors = wellness.validate(request.get_json(silent=True))
    if errors:
        return jsonify({'detail': 'invalid wellness reading', 'errors': errors}), 422
    if not integration_allows(g.user_id, 'garmin'):
        return jsonify({'stored': False, 'skipped': 'garmin integration disabled', 'date': row['date']})
    try:
        wellness_store.upsert(g.user_id, row)
    except Exception as e:
        app.logger.warning('wellness write failed: %s', e)
        return jsonify({'detail': 'wellness write failed'}), 503
    return jsonify({'stored': True, 'date': row['date']})


@app.get('/api/health/wellness/latest')
@require_auth
def health_wellness_latest():
    """The newest watch reading and the watch's model name, for the Devices
    card and the readiness footnote. `latest` is null before the first one."""
    from src import device_store, wellness_store
    latest = wellness_store.latest(g.user_id)
    if latest:
        latest['model'] = device_store.model_name(latest.get('part_number'))
    return jsonify({'latest': latest})


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


def _keep_days_behind(user_id: str, existing: dict | None, envelope: dict) -> dict:
    """A regenerate of the same block (same start date) keeps the days behind
    the athlete: every date before today as it was planned, and today too once
    it is trained (a matched workout or a completed log). The clients splice
    "from tomorrow" themselves; the whole-program regenerate saved here did
    not, and rewrote a session trained that morning (2026-10-19). With the past
    kept, record_version sees the block continue and carries its matches."""
    return _keep_days_behind_counted(user_id, existing, envelope)[0]


def _keep_days_behind_counted(user_id: str, existing: dict | None, envelope: dict) -> tuple[dict, int]:
    """`_keep_days_behind`, and how many elapsed days it put back."""
    from src import program_history as ph
    try:
        start = ph.start_date_of(envelope)
        if not existing or not start or ph.start_date_of(existing) != start:
            return envelope, 0
        today = _today_for(_standards_context(user_id)[1])
        cutoff = today + _timedelta(days=1) if ph.trained_on(user_id, today) else today
        if _date.fromisoformat(start) >= cutoff:
            return envelope, 0
        restored, changed = ph.restore_elapsed(user_id, envelope, cutoff)
        if changed:
            app.logger.info('program save: kept %d elapsed day(s) of %s', len(changed), user_id)
        return restored, len(changed)
    except Exception as err:  # noqa: BLE001 — keeping the past must never fail the save
        app.logger.warning('program save: could not keep the elapsed days: %s', err)
        return envelope, 0


def _standards_context(user_id: str) -> tuple[str, str | None]:
    """(sex, timezone) from the profile: which tables, and the athlete's day."""
    from src.db import get_user_profile
    try:
        profile = get_user_profile(user_id) or {}
    except Exception:  # noqa: BLE001 — the male tables and UTC, as before the profile could say
        profile = {}
    sex = (profile.get('sex') or 'male').lower()
    return (sex if sex in ('male', 'female') else 'male'), profile.get('timezone') or None


def _today_for(tz: str | None) -> _date:
    from zoneinfo import ZoneInfo
    try:
        return _datetime.now(ZoneInfo(tz)).date() if tz else _datetime.now(_timezone.utc).date()
    except Exception:  # noqa: BLE001 — an unknown zone reads as UTC
        return _datetime.now(_timezone.utc).date()


@app.get('/api/standards/results')
@require_auth
def standards_results():
    """The athlete's results on the standards: per standard the current and the
    best result with their level and text, and every entry with its day,
    source, note and the block it fell in (`src/standards.py`). Levels are
    worked out here so no client computes one."""
    from src import program_history
    from src import standards as _standards
    from src.analytics import benchmarks_data as _bd
    sex, tz = _standards_context(g.user_id)
    try:
        activations = program_history.list_activations(g.user_id)
    except Exception:  # noqa: BLE001 — results without blocks rather than none
        activations = []
    names = {p['id']: p.get('name', p['id']) for p in loader.load_philosophies()}
    doc = _standards.summarise(
        _bd.load_benchmarks(), _health.get_performance_logs(g.user_id), sex, tz,
        _standards.blocks_from_activations(activations, names))
    # The current program's own standards, for Profile's "This program".
    own = _current_program_standards(g.user_id)
    doc['programStandards'] = [{'id': sid, 'why': why} for sid, why in own.items()]
    return jsonify(doc)


def _current_program_standards(user_id: str) -> dict:
    """{standard id: [why…]} for the athlete's current program
    (standard_results.current_program_standards), {} without one."""
    from src import standard_results
    try:
        return standard_results.current_program_standards(user_id)
    except Exception as exc:  # noqa: BLE001 — sections without a program rather than none
        app.logger.warning('standards: program standards failed: %s', exc)
        return {}


def _result_day(body: dict, tz: str | None) -> str:
    """The athlete's day for a result: `loggedOn` as sent, else today where
    they are. A day after tomorrow is a typo, not a result. Raises InputError."""
    from src.standards import InputError
    today = _today_for(tz)
    raw = body.get('loggedOn')
    if raw in (None, ''):
        return today.isoformat()
    try:
        day = _date.fromisoformat(str(raw))
    except ValueError:
        raise InputError('loggedOn must be a date (YYYY-MM-DD)') from None
    if day > today + _timedelta(days=1):
        raise InputError('a result cannot be dated in the future')
    return day.isoformat()


@app.post('/api/standards/results')
@app.post('/api/health/performance')
@require_auth
def health_add_performance():
    """One result on a standard (or a bodyweight): `text` as typed ("4:58"), a
    `value` in the standard's unit, or for a ×BW standard the `kg` and `reps`
    lifted; `loggedOn` the athlete's day (today by default) and an optional
    `note`. 422 when it cannot be a result, 503 when the write fails — a client
    never believes a result was kept that was not. `/api/health/performance`
    is the old name, kept for installed builds."""
    from src import standards as _standards
    from src.analytics import benchmarks_data as _bd
    body = request.get_json(silent=True) or {}
    benchmark_id = body.get('benchmarkId') or ''
    if not benchmark_id or all(body.get(k) is None for k in ('value', 'text', 'kg')):
        return jsonify({'detail': 'benchmarkId and value required'}), 400
    if benchmark_id not in _bd.known_ids():
        return jsonify({'detail': f'unknown standard {benchmark_id!r}'}), 422
    _sex, tz = _standards_context(g.user_id)
    logged_at = body.get('loggedAt') or _datetime.now(_timezone.utc).isoformat()
    try:
        _datetime.fromisoformat(str(logged_at).replace('Z', '+00:00'))
    except ValueError:
        return jsonify({'detail': 'loggedAt must be an ISO date or time'}), 422
    note = (str(body.get('note') or '').strip() or None)
    try:
        day = _result_day(body, tz)
        logs = _health.get_performance_logs(g.user_id) if body.get('kg') is not None else {}
        value, inp = _standards.resolve_input(_bd.by_id().get(benchmark_id), body, logs, day, tz)
    except _standards.InputError as exc:
        return jsonify({'detail': str(exc)}), 422
    try:
        entry_id = _health.add_performance_entry(g.user_id, benchmark_id, value, logged_at, day,
                                                 note=note, input_=inp or None)
    except Exception as exc:  # noqa: BLE001 — the client is told, and retries
        app.logger.warning('standards: result write failed for %s: %s', benchmark_id, exc)
        return jsonify({'detail': 'could not save the result'}), 503
    return jsonify({'saved': benchmark_id, 'id': entry_id, 'value': value,
                    'valueText': _bd.format_value(_bd.by_id().get(benchmark_id), value), 'loggedOn': day})


@app.patch('/api/standards/results/<int:entry_id>')
@require_auth
def standards_update_result(entry_id: int):
    """Correct one result: its value (as typed, or kg × reps), its day or its
    note. A ×BW result logged as a load is re-read against the bodyweight of
    its new day. 404 when it is not the athlete's."""
    from src import standards as _standards
    from src import standards_store as _store
    from src.analytics import benchmarks_data as _bd
    body = request.get_json(silent=True) or {}
    try:
        current = _store.get_result(g.user_id, entry_id)
    except Exception as exc:  # noqa: BLE001
        app.logger.warning('standards: read %s failed: %s', entry_id, exc)
        return jsonify({'detail': 'could not read the result'}), 503
    if current is None:
        return jsonify({'detail': 'no such result'}), 404
    _sex, tz = _standards_context(g.user_id)
    fields: dict = {}
    try:
        day = _result_day(body, tz) if 'loggedOn' in body else _standards.day_of(current, tz)
        if 'loggedOn' in body:
            fields['logged_on'] = day
        b = _bd.by_id().get(current['benchmarkId'])
        sent = {k: body[k] for k in ('value', 'text', 'kg', 'reps', 'bodyweightKg') if body.get(k) is not None}
        prior = current.get('input') or {}
        if not sent and 'loggedOn' in body and prior.get('kg') is not None:
            # A load re-read against the new day's bodyweight — unless the
            # athlete gave the bodyweight with it, which stays theirs.
            sent = {'kg': prior['kg'], 'reps': prior.get('reps', 1)}
            if prior.get('bodyweightGiven'):
                sent['bodyweightKg'] = prior.get('bodyweightKg')
        if sent:
            logs = _health.get_performance_logs(g.user_id) if sent.get('kg') is not None else {}
            fields['value'], inp = _standards.resolve_input(b, sent, logs, day, tz)
            fields['input'] = inp or None
    except _standards.InputError as exc:
        return jsonify({'detail': str(exc)}), 422
    if 'note' in body:
        fields['note'] = str(body.get('note') or '').strip() or None
    try:
        if not _store.update_result(g.user_id, entry_id, fields):
            return jsonify({'detail': 'no such result'}), 404
    except Exception as exc:  # noqa: BLE001
        app.logger.warning('standards: update %s failed: %s', entry_id, exc)
        return jsonify({'detail': 'could not save the change'}), 503
    return jsonify({'updated': entry_id})


@app.delete('/api/standards/results/<int:entry_id>')
@require_auth
def standards_delete_result(entry_id: int):
    """Delete one result. 404 when it is not the athlete's."""
    from src import standards_store as _store
    try:
        deleted = _store.delete_result(g.user_id, entry_id)
    except Exception as exc:  # noqa: BLE001
        app.logger.warning('standards: delete %s failed: %s', entry_id, exc)
        return jsonify({'detail': 'could not delete the result'}), 503
    if not deleted:
        return jsonify({'detail': 'no such result'}), 404
    return jsonify({'deleted': entry_id})


def _suggestions_doc(user_id: str, rows: list[dict]) -> list[dict]:
    """Suggestion rows in the server's words (standard_results.describe),
    each naming the session it came from."""
    from src import program_history, standard_results
    from src.analytics import benchmarks_data as _bd
    sex, tz = _standards_context(user_id)
    try:
        planned = program_history.planned_rows_for_uids(user_id, [r['sessionUid'] for r in rows if r['sessionUid']])
    except Exception:  # noqa: BLE001 — unnamed sessions rather than no suggestions
        planned = {}
    names = {uid: p.get('archetype_name') for uid, p in planned.items()}
    return standard_results.describe(rows, _bd.by_id(), _health.get_performance_logs(user_id), sex, tz, names)


@app.get('/api/standards/suggestions')
@require_auth
def standards_suggestions():
    """Results logged sessions suggest, waiting for the athlete: Profile ▸
    Standards' "To confirm" and Today. A pending suggestion is not a result
    and no reader of results sees it (src/standard_results.py)."""
    from src import standards_store as _store
    return jsonify({'suggestions': _suggestions_doc(g.user_id, _store.list_suggestions(g.user_id))})


@app.post('/api/standards/suggestions/<int:suggestion_id>/confirm')
@require_auth
def standards_confirm_suggestion(suggestion_id: int):
    """Make a suggestion a result. The body may correct it — `text`, `value`
    or for a ×BW standard `kg` (and `reps`) — read against the session's day.
    Idempotent; 404 when it is not the athlete's, 503 when the write fails."""
    from src import standards as _standards
    from src import standards_store as _store
    from src.analytics import benchmarks_data as _bd
    body = request.get_json(silent=True) or {}
    via = str(body.get('via') or 'web')[:20]
    value = inp = None
    try:
        current = _store.get_suggestion(g.user_id, suggestion_id)
    except Exception as exc:  # noqa: BLE001
        app.logger.warning('standards: read suggestion %s failed: %s', suggestion_id, exc)
        return jsonify({'detail': 'could not read the suggestion'}), 503
    if current is None:
        return jsonify({'detail': 'no such suggestion'}), 404
    sent = {k: body[k] for k in ('value', 'text', 'kg', 'reps') if body.get(k) is not None}
    if sent:
        _sex, tz = _standards_context(g.user_id)
        try:
            logs = _health.get_performance_logs(g.user_id) if sent.get('kg') is not None else {}
            value, inp = _standards.resolve_input(_bd.by_id().get(current['benchmarkId']), sent, logs,
                                                  current['loggedOn'] or _today_for(tz).isoformat(), tz)
        except _standards.InputError as exc:
            return jsonify({'detail': str(exc)}), 422
    try:
        done = _store.confirm_suggestion(g.user_id, suggestion_id, via=via, value=value, input_=inp or None)
    except Exception as exc:  # noqa: BLE001 — the client is told, and retries
        app.logger.warning('standards: confirm %s failed: %s', suggestion_id, exc)
        return jsonify({'detail': 'could not save the result'}), 503
    if done is None:
        return jsonify({'detail': 'no such suggestion'}), 404
    return jsonify({'suggestion': (_suggestions_doc(g.user_id, [done]) or [None])[0],
                    'resultId': done['performanceLogId']})


def _set_suggestion(suggestion_id: int, status: str, from_statuses: tuple):
    from src import standards_store as _store
    body = request.get_json(silent=True) or {}
    try:
        done = _store.set_suggestion_status(g.user_id, suggestion_id, status,
                                            via=str(body.get('via') or 'web')[:20], from_statuses=from_statuses)
    except Exception as exc:  # noqa: BLE001
        app.logger.warning('standards: %s %s failed: %s', status, suggestion_id, exc)
        return jsonify({'detail': 'could not save the change'}), 503
    if done is None:
        return jsonify({'detail': f'no {"/".join(from_statuses)} suggestion {suggestion_id}'}), 404
    return jsonify({'suggestion': (_suggestions_doc(g.user_id, [done]) or [None])[0]})


@app.post('/api/standards/suggestions/<int:suggestion_id>/dismiss')
@require_auth
def standards_dismiss_suggestion(suggestion_id: int):
    """"Not a test": the suggestion stays dismissed, even when the session is
    logged again. 404 unless it is pending."""
    return _set_suggestion(suggestion_id, 'dismissed', ('pending',))


@app.post('/api/standards/suggestions/<int:suggestion_id>/reopen')
@require_auth
def standards_reopen_suggestion(suggestion_id: int):
    """Undo a dismissal. 404 unless it is dismissed."""
    return _set_suggestion(suggestion_id, 'pending', ('dismissed',))


@app.delete('/api/health/performance/<benchmark_id>')
@require_auth
def health_delete_performance(benchmark_id: str):
    try:
        _health.delete_performance_log(g.user_id, benchmark_id)
    except Exception as exc:  # noqa: BLE001 — said, as every standards write is
        app.logger.warning('standards: delete series %s failed: %s', benchmark_id, exc)
        return jsonify({'detail': 'could not delete the results'}), 503
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


def _bio_for_scoring(user_id: str, days: int) -> tuple[list[dict], dict]:
    """The bio list every readiness score reads, and where its components
    came from: daily_bio merged with the watch's daily_wellness, resting HR
    from one series only (src/wellness.merge_for_scoring). The four scoring
    sites used to read daily_bio each on their own."""
    from src import wellness, wellness_store
    return wellness.merge_for_scoring(_health.get_recent_bio_logs(user_id, days=days),
                                      wellness_store.recent(user_id, days=days))


_WATCH_READING_MAX_AGE_H = 36


def _as_utc(value) -> _datetime | None:
    """A reading time as an aware datetime: the store returns ISO strings,
    the watch posts epoch seconds, tests pass datetimes."""
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return _datetime.fromtimestamp(value, _timezone.utc)
    if isinstance(value, str):
        value = _datetime.fromisoformat(value.replace('Z', '+00:00'))
    return value if value.tzinfo else value.replace(tzinfo=_timezone.utc)


def _watch_recovery(bio_list: list[dict], now: _datetime | None = None) -> dict | None:
    """The watch's newest Body Battery peak and the recovery hours still left,
    from a reading taken in the last 36 hours — older says nothing about this
    morning. Freshness is the reading's age, not its date: the server's UTC
    date runs a day ahead of the athlete's every evening west of Greenwich.
    Rows without a reading time fall back to their date (today or yesterday,
    UTC). Recovery time counts down from the post it came from."""
    now = now or _datetime.now(_timezone.utc)
    cutoff = (now.date() - _timedelta(days=1)).isoformat()

    def fresh(b: dict) -> bool:
        read = _as_utc(b.get('wellness_read_at'))
        if read is not None:
            return (now - read).total_seconds() <= _WATCH_READING_MAX_AGE_H * 3600
        return str(b['date']) >= cutoff

    rows = [b for b in bio_list
            if (b.get('body_battery_max') is not None or b.get('recovery_time_h') is not None) and fresh(b)]
    if not rows:
        return None
    row = max(rows, key=lambda b: str(b['date']))
    left = row.get('recovery_time_h')
    read_at = _as_utc(row.get('recovery_read_at'))
    if left is not None and read_at is not None:
        left = max(0.0, left - (now - read_at).total_seconds() / 3600)
    return {'body_battery': row.get('body_battery_max'), 'recovery_left_h': left}


def _score_watch_recovery(watch: dict) -> int:
    """HRV's 35 points from the watch, when there is no HRV: the morning's Body
    Battery peak (20 points, full at 80, none at 20) and the recovery time
    left (15 points, full at none, none at 72 h or more). With one of the two,
    it carries all 35."""
    bb, left = watch.get('body_battery'), watch.get('recovery_left_h')
    bb_part = None if bb is None else min(1.0, max(0.0, (bb - 20) / 60))
    rec_part = None if left is None else 1 - min(left, 72) / 72
    if bb_part is not None and rec_part is not None:
        return round(20 * bb_part + 15 * rec_part)
    return round(35 * (bb_part if bb_part is not None else rec_part))


def _compute_readiness(bio_list: list[dict], session_dict: dict, user_id: str | None = None,
                       sources: dict | None = None) -> dict:
    flags: list[str] = []
    rhr     = _score_rhr(bio_list, flags)
    watch   = _watch_recovery(bio_list)
    has_hrv = sum(1 for b in _recent_bio(bio_list, 14) if b.get('hrv') is not None) >= 3
    if not has_hrv and watch:
        # No HRV (Garmin does not pass it to Apple Health): the watch's
        # recovery signals carry its weight instead of a neutral 17.
        hrv = _score_watch_recovery(watch)
    else:
        hrv = _score_hrv(bio_list, flags)
    sleep   = _score_sleep(bio_list, flags)      # capped at 10 (was 15)
    fatigue = _score_fatigue(session_dict, flags)  # capped at 10 (was 15)
    tsb     = _score_tsb(user_id, flags) if user_id else 5
    # Rebalance sleep and fatigue to cap at 10 each (original scoring goes to 15/15;
    # clamp here so total remains 100: rhr(35) + hrv(35) + sleep(10) + fatigue(10) + tsb(10)
    sleep   = min(sleep, 10)
    fatigue = min(fatigue, 10)
    score = min(100, max(0, rhr + hrv + sleep + fatigue + tsb))
    # Recovery the watch still counts is a ceiling, as it is for Garmin's own
    # readiness: a steady resting HR used to score 67 with 68 h of recovery left.
    if watch and watch.get('recovery_left_h') is not None:
        ceiling = max(10, round(100 - watch['recovery_left_h']))
        if score > ceiling:
            score = ceiling
            flags.append('recovery_pending')
    status = 'green' if score >= 70 else 'yellow' if score >= 45 else 'red'
    out = {
        'score':      score,
        'status':     status,
        'flags':      flags,
        'components': {'rhr': rhr, 'hrv': hrv, 'sleep': sleep, 'fatigue': fatigue, 'tsb': tsb},
        # The score's parts in words with their maxima, for the readiness
        # detail on either client; the maxima live in the scoring above only.
        'parts': [
            {'id': 'rhr', 'label': 'Resting heart rate', 'points': rhr, 'max': 35},
            {'id': 'hrv', 'label': ('Body Battery and recovery' if not has_hrv and watch
                                    else 'Heart-rate variability'), 'points': hrv, 'max': 35},
            {'id': 'sleep', 'label': 'Sleep', 'points': sleep, 'max': 10},
            {'id': 'fatigue', 'label': 'Session fatigue', 'points': fatigue, 'max': 10},
            {'id': 'tsb', 'label': 'Training load', 'points': tsb, 'max': 10},
        ],
    }
    if 'recovery_pending' in flags:
        out['cappedAt'] = score
    if watch:
        out['watch'] = {'bodyBattery': watch['body_battery'],
                        'recoveryLeftH': None if watch['recovery_left_h'] is None
                        else round(watch['recovery_left_h'], 1)}
    if sources is not None:
        out['sources'] = dict(sources)  # where rhr / hrv / sleep came from
        if watch:
            out['sources']['recovery'] = 'garmin_watch'
    return out


@app.get('/api/health/readiness')
@require_auth
def health_readiness():
    bio_list, sources = _bio_for_scoring(g.user_id, days=14)
    session_dict = _health.get_session_logs(g.user_id)
    return jsonify(_compute_readiness(bio_list, session_dict, user_id=g.user_id, sources=sources))


# ---------------------------------------------------------------------------
# Training Load helpers (shared by /load/weekly and /load/pmc)
# ---------------------------------------------------------------------------

_BANISTER_WEIGHTS = [1.0, 1.5, 2.0, 3.0, 4.5]
_DEFAULT_ZONE_BOUNDARIES = [0.60, 0.70, 0.80, 0.90]


def _get_user_max_hr(user_id: str) -> int:
    """hrConfig override → 220 − age → the shared default.

    Used to ignore date of birth and fall back to 190, so the server's zones
    and TRIMP disagreed with the browser's for anyone who had set a DOB but no
    override. The resolution now lives with the analytics engine so every
    zone number on every platform starts from the same max HR.
    """
    from datetime import date as _d
    from src.analytics.context import AnalyticsInputs, Context
    from src.analytics.primitives import max_hr_for
    try:
        from src.db import get_user_profile
        profile = get_user_profile(user_id) or {}
    except Exception:
        profile = {}
    ctx = Context(AnalyticsInputs({}, _d.today(), _d.today(), profile=profile),
                  frameworks={}, modalities={})
    return int(round(max_hr_for(ctx)))


def _calc_workout_trimp(workout: dict, max_hr: int = 190) -> float:
    """Banister zone-minute TRIMP for one workout.

    Delegates to src/analytics/zones.py so this, the intensity split and the
    browser all bucket a sample from the same edges in data/commons/hr_zones.json
    — this function used to carry its own Friel 60/70/80/90 copy.
    """
    from src.analytics import zones as _zones
    return _zones.trimp(workout, float(max_hr))


def _workouts_for_load(user_id: str, max_hr: int, since=None, backfill: int = 40) -> list[dict]:
    """The library as summaries, each carrying its cached zone metrics.

    TRIMP, the PMC and the weekly load used to read every workout with its
    GPS track and HR series — ~40 MB of JSON for a year of watch activities,
    several hundred MB once parsed — and the readiness score did it on every
    Home open, which is what OOM-killed the 256 MB worker. Now the series are
    read only for rows whose cache is missing or stale (a new zone-edge
    version, a changed max HR), `backfill` of them per call, newest first,
    and written back so the next call reads none. A row still waiting for its
    turn is scored from its HR summary meanwhile, as summaries always were.
    `since` drops rows the caller's window cannot use before any of that.
    """
    from datetime import date as _date
    from src.analytics import zones as _zones

    summaries = _health.get_workouts(user_id, summary_only=True)
    if since is not None:
        kept = []
        for w in summaries:
            try:
                if _date.fromisoformat(str(w.get('date'))[:10]) >= since:
                    kept.append(w)
            except ValueError:
                continue
        summaries = kept
    stale = [w for w in summaries if _zones.cached_metrics(w, max_hr) is None]
    # A row with no HR summary has no series either: its metrics come from
    # the summary alone, with nothing to read.
    with_hr = [w for w in stale if (w.get('heartRate') or {}).get('avg')]
    todo = {w['id'] for w in with_hr[:backfill]}          # summaries are newest first
    by_id = {w['id']: w for w in summaries}
    for row in _health.get_workouts_with_hr(user_id, sorted(todo)):
        metrics = _zones.compute_metrics(row, max_hr)
        by_id[row['id']]['metrics'] = metrics
        _health.save_workout_metrics(user_id, row['id'], metrics)
    for w in stale:
        if w['id'] in todo or (w.get('heartRate') or {}).get('avg'):
            continue
        metrics = _zones.compute_metrics(w, max_hr)
        w['metrics'] = metrics
        _health.save_workout_metrics(user_id, w['id'], metrics)
    return summaries


def _matched_ids_in_window(matches: list, summaries: list, start, end) -> list[str]:
    """Ids of the non-rejected matched workouts dated start <= date < end —
    the window analytics/context.py applies — so only those rows are read
    with their series."""
    from datetime import date as _date
    dates = {}
    for w in summaries:
        try:
            dates[w['id']] = _date.fromisoformat(str(w.get('date'))[:10])
        except (KeyError, TypeError, ValueError):
            continue
    out = []
    for m in matches:
        if m.get('matchConfidence') == 'rejected':
            continue
        d = dates.get(m.get('importedWorkoutId'))
        if d is not None and start <= d < end:
            out.append(m['importedWorkoutId'])
    return out


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

    max_hr = _get_user_max_hr(g.user_id)
    cutoff = _date.today() - _td(weeks=12)
    workouts = _workouts_for_load(g.user_id, max_hr, since=cutoff)

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


@app.get('/api/health/load/summary')
@require_auth
def health_load_summary():
    """Analytics ▸ Load's totals, modality and activity mix, consistency and
    zone minutes for one period (src/analytics/load_summary.py) — what both
    clients used to sum on the device. `period` is 7d|30d|3m|1y|all;
    `today` is the client's local date (the server's is UTC)."""
    from datetime import date as _date, timedelta as _td
    from src.analytics.load_summary import PERIOD_DAYS, summarize

    period = request.args.get('period', '30d')
    if period not in PERIOD_DAYS:
        return jsonify({'detail': f'period must be one of {sorted(PERIOD_DAYS)}'}), 422
    try:
        today = _date.fromisoformat(request.args['today']) if request.args.get('today') else _date.today()
    except ValueError:
        return jsonify({'detail': 'today must be YYYY-MM-DD'}), 422
    days = PERIOD_DAYS[period]
    # Twice the period for the prior comparison; twelve weeks for consistency.
    lookback = max((days or 0) * 2, 7 * 12 + 7)
    since = None if days is None else today - _td(days=lookback)
    max_hr = _get_user_max_hr(g.user_id)
    workouts = _workouts_for_load(g.user_id, max_hr, since=since)
    return jsonify(summarize(workouts, max_hr, period, today))


@app.get('/api/health/load/pmc')
@require_auth
def health_load_pmc():
    from datetime import date as _date, timedelta as _td
    max_hr = _get_user_max_hr(g.user_id)
    workouts = _workouts_for_load(g.user_id, max_hr, since=_date.today() - _td(days=89))
    return jsonify(_compute_pmc(workouts, max_hr, days=90))


# ---------------------------------------------------------------------------
# TSB component for readiness score
# ---------------------------------------------------------------------------

def _score_tsb(user_id: str, flags: list[str]) -> int:
    """Score Training Stress Balance (form) as a readiness component (0–10 pts)."""
    try:
        from datetime import date as _date, timedelta as _td
        max_hr = _get_user_max_hr(user_id)
        # The 14-day PMC seeds from zero at its first day: nothing older counts.
        workouts = _workouts_for_load(user_id, max_hr, since=_date.today() - _td(days=13))
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


# ---------------------------------------------------------------------------
# Program-specific analytics
# ---------------------------------------------------------------------------
# One document: what the active program is for, and how the athlete is doing
# against it — per methodology, in that methodology's own currency. The engine
# is src/analytics; this only gathers inputs and caches the result.

def _program_analytics_inputs(user_id: str):
    """Everything the engine needs, or None when there is no usable program."""
    from datetime import date as _d
    from src.analytics.context import AnalyticsInputs, parse_iso_date
    from src.program_keys import normalize_program_keys

    stored = _db.get_user_program(user_id)
    if not isinstance(stored, dict):
        return None
    stored = normalize_program_keys(stored)
    program = stored.get('currentProgram') or ({'weeks': stored.get('weeks')} if stored.get('weeks') else None)
    if not program or not program.get('weeks'):
        return None
    start = parse_iso_date(stored.get('programStartDate') or program.get('program_start_date'))
    if start is None:
        return None

    from datetime import timedelta as _tdelta
    matches = _health.get_matches(user_id)
    # Only matched workouts inside the program's own span need their HR and
    # GPS series (context.py windows everything to it anyway); the rest of
    # the library is summary-only. Every match used to qualify, which read a
    # spring's worth of long-run GPS tracks for an autumn program.
    end = start + _tdelta(days=7 * len(program['weeks']))
    matched_ids = _matched_ids_in_window(matches, _health.get_workouts(user_id, summary_only=True), start, end)
    workouts = _health.get_workouts_by_ids(user_id, matched_ids)
    profile = _db.get_user_profile(user_id) or {}
    return AnalyticsInputs(
        program=program, start_date=start, today=_d.today(),
        session_logs=_health.get_session_logs(user_id), matches=matches, workouts=workouts,
        performance_logs=_health.get_performance_logs(user_id),
        bio_logs=_bio_for_scoring(user_id, days=42)[0], profile=profile,
        philosophy_weights=stored.get('sourceGoalWeights') or {},
    ), stored


def _watch_digest(bio_logs: list[dict]) -> dict | None:
    watch = _watch_recovery(bio_logs)
    if not watch:
        return None
    left = watch['recovery_left_h']
    return {'bb': watch['body_battery'], 'left_h': None if left is None else round(left)}


def _program_analytics_hash(inputs, stored: dict, revision) -> str:
    """Everything that can change the document. The old progression cache
    hashed session keys and exercise counts only, so adding sets to a logged
    exercise, importing a workout, a new PR, a changed max HR or simply a new
    day never invalidated it."""
    import hashlib as _h
    import json as _j
    parts = [
        _ANALYTICS_SHAPE, str(revision), inputs.today.isoformat(),
        # Each set's values, not only how many: the set logger edits a set's
        # kg, reps or seconds in place.
        _j.dumps({k: (v.get('completedAt'), sorted(
                      (ex, [((s or {}).get('completed'), (s or {}).get('repsActual'), (s or {}).get('weightKg'),
                             (s or {}).get('rpe'), (s or {}).get('durationSeconds'))
                            for s in ((d or {}).get('sets') or []) if isinstance(s, dict)],
                       (d or {}).get('rounds'), (d or {}).get('durationSec'), (d or {}).get('distanceKm'),
                       (d or {}).get('clean'))
                      for ex, d in (v.get('exercises') or {}).items() if isinstance(d, dict)),
                      # The watch's exercise times: they decide which minutes count in zones.
                      v.get('exerciseTimeline'))
                  for k, v in inputs.session_logs.items()}, sort_keys=True, default=str),
        _j.dumps(sorted((m.get('importedWorkoutId'), m.get('sessionKey'), m.get('matchConfidence'))
                        for m in inputs.matches), default=str),
        # The matched workouts themselves: a richer copy that merges into a
        # matched row (a Garmin file after the watch's live upload) changes its
        # heart rate and length without changing any match.
        _j.dumps(sorted((w.get('id'), w.get('durationMinutes'), (w.get('heartRate') or {}).get('avg'),
                         len((w.get('heartRate') or {}).get('samples') or []))
                        for w in inputs.workouts), default=str),
        _j.dumps(_standards_digest_key(inputs.performance_logs), default=str),
        # Values, not only dates: a same-date resting HR from the watch, or a
        # corrected Apple Health night, has to bust the cache too.
        _j.dumps(sorted((b.get('date', ''), b.get('resting_hr'), b.get('hrv'), b.get('sleep_duration_min'))
                        for b in inputs.bio_logs), default=str),
        # The watch's recovery readings readiness scores, with the hours left
        # to the hour: a later Body Battery or recovery post, and the
        # countdown itself, change the readiness this document carries.
        _j.dumps(_watch_digest(inputs.bio_logs), sort_keys=True),
        _j.dumps(inputs.profile.get('hrConfig') or {}, sort_keys=True), str(inputs.profile.get('dateOfBirth')),
        str(inputs.profile.get('sex')),
        # What the packages declare progress to be: a changed analytics.yaml
        # rebuilds the stored documents by itself.
        _analytics_specs_digest(),
        # The document's shape: bump when a section gains keys, so stored
        # copies are rebuilt (2: scorecard.weeks, for the Today card;
        # 5: intensity.zones, per-zone planned against recorded minutes;
        # 6: a session's programming decides whether its heart rate counts;
        # 7: only its zoned exercises' timed minutes count).
        'doc-7',
    ]
    return _h.sha256('|'.join(parts).encode()).hexdigest()


_SPECS_DIGEST: str | None = None


def _analytics_specs_digest() -> str:
    """A digest of every package's analytics.yaml, once per process: the
    files change only with a deploy, and a deploy starts a new process."""
    global _SPECS_DIGEST
    if _SPECS_DIGEST is None:
        import hashlib as _h
        import json as _j
        _SPECS_DIGEST = _h.sha256(_j.dumps(loader.load_analytics_specs(), sort_keys=True,
                                           default=str).encode()).hexdigest()[:16]
    return _SPECS_DIGEST


@app.get('/api/analytics/specs')
def analytics_specs():
    """Every package's analytics spec, described: what each philosophy tracks
    and measures, resolved to names. Static data — no user, no program."""
    from src.analytics.describe import describe_all
    return jsonify(describe_all())


@app.get('/api/analytics/vocabulary')
def analytics_vocabulary():
    """The analytics words: the twelve primitives, what each needs logged,
    and the load and recovery terms (src/analytics/vocabulary.py) — the About
    sections of the phone's detail screens. Static data — no user."""
    from src.analytics import vocabulary
    return jsonify(vocabulary.to_client())


@app.get('/api/analytics/development')
@require_auth
def analytics_development():
    """How the athlete has developed across programs — the history tables
    read as one document (src/analytics/development.py). `from` / `to` bound
    the window (default: the last twelve months); `fresh=1` recomputes."""
    from datetime import date as _date, timedelta as _td
    from src import program_history
    from src.analytics import benchmarks_data as _bd
    from src.analytics.development import DevelopmentInputs, compute_development

    today = _date.today()
    try:
        to_date = _date.fromisoformat(request.args.get('to') or today.isoformat())
        from_date = _date.fromisoformat(request.args.get('from') or (to_date - _td(days=365)).isoformat())
    except ValueError:
        return jsonify({'detail': 'bad_date'}), 400
    if from_date > to_date:
        from_date, to_date = to_date, from_date

    user_id = g.user_id
    activations = program_history.list_activations(user_id)
    if not activations:
        return jsonify({'status': 'no_history', 'window': {'from': from_date.isoformat(), 'to': to_date.isoformat()},
                        'blocks': [], 'lifts': [], 'currencies': [],
                        'load': {'weekly': [], 'pmc': []}, 'benchmarks': []})

    logs = _health.get_session_logs_by_uid(user_id)
    matches = _health.get_matches(user_id)
    max_hr = _get_user_max_hr(user_id)
    workouts = _workouts_for_load(user_id, max_hr, since=from_date)
    performance = _health.get_performance_logs(user_id)

    import hashlib as _h
    import json as _j
    digest = _h.sha256(_j.dumps([
        [(a.get('activationId'), a.get('effectiveFrom'), a.get('effectiveTo')) for a in activations],
        sorted((uid, v.get('completedAt'), len(v.get('exercises') or {})) for uid, v in logs.items()),
        sorted((m.get('importedWorkoutId'), m.get('sessionUid'), m.get('matchConfidence')) for m in matches),
        sorted((w.get('id'), w.get('date'), bool(w.get('metrics'))) for w in workouts),
        _standards_digest_key(performance), _ANALYTICS_SHAPE,
        today.isoformat(), from_date.isoformat(), to_date.isoformat(),
    ], sort_keys=True, default=str).encode()).hexdigest()
    period_key = f'development:{from_date.isoformat()}:{to_date.isoformat()}'
    if not request.args.get('fresh'):
        cached = _health.get_progression_snapshot(user_id, period_key, 'development')
        if cached and cached.get('session_hash') == digest:
            return jsonify(cached['data'])

    sex, tz = _standards_context(user_id)
    exercises, _ = loader.load_all_exercises()
    philosophies = {p['id']: p.get('name', p['id']) for p in loader.load_philosophies()}
    planned = {vid: program_history.sessions_for_version(user_id, vid)
               for vid in {a['versionId'] for a in activations}}
    pmc_days = max(1, (to_date - from_date).days + 1)
    try:
        pmc = _compute_pmc(workouts, max_hr, days=pmc_days)
    except Exception as exc:
        app.logger.warning('development: pmc failed: %s', exc)
        pmc = []

    doc = compute_development(DevelopmentInputs(
        today=today, window_from=from_date, window_to=to_date,
        activations=activations, planned=planned, logs_by_uid=logs, matches=matches,
        workouts=workouts, pmc=pmc, trimp_of=lambda w: _calc_workout_trimp(w, max_hr),
        performance_logs=performance, benchmarks=_bd.load_benchmarks(), sex=sex, timezone=tz,
        program_standards=_current_program_standards(user_id),
        exercise_names={eid: ex.get('name', eid) for eid, ex in exercises.items()},
        philosophy_names=philosophies,
    ))
    doc['generatedAt'] = today.isoformat()
    _health.save_progression_snapshot(user_id, period_key, 'development', digest, doc)
    return jsonify(doc)


@app.get('/api/analytics/program')
@require_auth
def analytics_program():
    from src.analytics.document import compute_program_analytics
    from src.db import get_program_revision

    got = _program_analytics_inputs(g.user_id)
    if got is None:
        return jsonify({'status': 'no_program'})
    inputs, stored = got
    revision = get_program_revision(g.user_id)
    period_key = f"{inputs.start_date.isoformat()}:{(stored.get('sourceGoalIds') or ['-'])[0]}"
    digest = _program_analytics_hash(inputs, stored, revision)

    if not request.args.get('fresh'):
        cached = _health.get_progression_snapshot(g.user_id, period_key, 'program')
        if cached and cached.get('session_hash') == digest:
            return jsonify(cached['data'])

    # The existing load numbers, computed once here and reframed by the engine.
    load = {}
    try:
        max_hr = _get_user_max_hr(g.user_id)
        all_workouts = _health.get_workouts(g.user_id, summary_only=True)
        load['pmc'] = _compute_pmc(all_workouts, max_hr, days=90)[-14:]
        load['readiness'] = _compute_readiness(inputs.bio_logs, inputs.session_logs, user_id=g.user_id)
    except Exception as load_err:
        app.logger.warning('analytics load inputs failed: %s', load_err)

    doc = compute_program_analytics(inputs, load=load)
    doc['status'] = 'ok'
    doc['revision'] = revision
    try:
        _health.save_progression_snapshot(g.user_id, period_key, 'program', digest, doc)
    except Exception as cache_err:
        app.logger.warning('analytics snapshot save failed: %s', cache_err)
    return jsonify(doc)


def _progression_history(user_id: str, matches: list[dict]) -> dict:
    """The cross-program context the progression readers need.

    Bounded on purpose: it looks up only the sessions something is attached to —
    every match and every log — rather than every snapshot the athlete has ever
    had. Degrades to empty, and the readers then behave exactly as they did when
    they could only see the stored program.
    """
    try:
        from src import program_history
        logs_by_uid = _health.get_session_logs_by_uid(user_id)
        uids = {m['sessionUid'] for m in matches if m.get('sessionUid')}
        uids |= set(logs_by_uid)
        return {
            'history_sessions':  program_history.session_lookup(user_id, sorted(uids)),
            'logs_by_uid':       logs_by_uid,
            'active_version_id': program_history.active_version_id(user_id),
        }
    except Exception as e:
        app.logger.warning('progression history context failed: %s', e)
        return {'history_sessions': [], 'logs_by_uid': {}, 'active_version_id': None}


@app.get('/api/progression/review')
@require_auth
def progression_review():
    period = request.args.get('period', 'weekly')
    if period not in ('weekly', 'biweekly'):
        period = 'weekly'

    session_logs = _health.get_session_logs(g.user_id)
    bio_logs     = _bio_for_scoring(g.user_id, days=42)[0]
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

    # Check snapshot cache. Keyed on everything the review reads — the
    # program analytics digest (revision, day, logs, matches, PRs, bio,
    # profile) — not on the session logs alone: a regenerate or a deploy that
    # changed the findings' wording left a stale review standing (production
    # said "completion rate is low" beside 100 % and "+0exercises").
    from src.db import get_program_revision
    period_key   = _pt._current_period_key(period)
    analytics_in = _program_analytics_inputs(g.user_id)
    if analytics_in is not None:
        base = _program_analytics_hash(analytics_in[0], analytics_in[1], get_program_revision(g.user_id))
    else:
        base = _pt.compute_session_hash(session_logs)
    session_hash = f'{base}:{period}:review-8'
    cached = _health.get_progression_snapshot(g.user_id, period_key, period)
    if cached and cached.get('session_hash') == session_hash:
        return jsonify(cached['data'])

    # Compute fresh
    # program_data may be the full GeneratedProgram or wrapped {currentProgram: ...}
    program = program_data.get('currentProgram') or program_data
    ctx = _progression_history(g.user_id, _health.get_matches(g.user_id))

    # The program analytics document, computed first: its scorecard is the
    # completion Today and the Program tab show, and the review takes it.
    doc = None
    completion = None
    try:
        from src.analytics.document import compute_program_analytics
        if analytics_in is not None:
            doc = compute_program_analytics(analytics_in[0])
            sc = doc.get('scorecard') or {}
            if sc.get('plannedSessions'):
                completion = (int(sc.get('completedSessions') or 0), int(sc['plannedSessions']))
    except Exception as engine_err:
        app.logger.warning('progression review: program analytics unavailable: %s', engine_err)

    review = _pt.compute_progression_review(
        user_id=g.user_id,
        program=program,
        bio_logs=bio_logs,
        session_logs=session_logs,
        period=period,
        history_sessions=ctx['history_sessions'],
        logs_by_uid=ctx['logs_by_uid'],
        active_version_id=ctx['active_version_id'],
        completion=completion,
    )

    # The per-exercise findings come from the program analytics engine, which
    # reads the stored prescription instead of replaying the generator against
    # a slot it no longer has, and knows each modality's real progression
    # model. The rest of the review (compliance, readiness, flags) is unchanged
    # so iOS ProgressionView and the Dashboard keep their shape.
    try:
        from src.analytics.document import progression_findings
        if doc is not None:
            findings = progression_findings(doc)
            if findings:
                review['exercise_findings'] = findings
                review['flags'] = [f for f in review.get('flags', []) if not f.startswith(('stalled', 'behind_target', 'insufficient_data'))]
                stalled = [f['name'] for f in findings if f['status'] == 'stalled']
                behind = [f['name'] for f in findings if f['status'] == 'behind']
                if stalled:
                    review['flags'].append('stalled: ' + ', '.join(stalled))
                if behind:
                    review['flags'].append('behind_target: ' + ', '.join(behind))
    except Exception as engine_err:
        app.logger.warning('progression review: engine findings unavailable: %s', engine_err)

    # The score, recomputed from what is measured, and the words that explain
    # it — the sum, the band, what the compliance covers, what is still
    # waiting for data (src/analytics/review.py).
    try:
        from src.analytics.review import explain
        review = explain(review, doc)
    except Exception as explain_err:
        app.logger.warning('progression review: explanation unavailable: %s', explain_err)

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

    weeks       = program.get('weeks', [])

    # Build matched-workout list for endurance exercise auto-population
    matches    = _health.get_matches(g.user_id)
    # Duration and the HR summary are all the tracker reads: no series.
    workouts   = _health.get_workouts(g.user_id, summary_only=True)
    wo_map     = {wo['id']: wo for wo in workouts}
    matched_wos = [
        {'sessionKey': m['sessionKey'], 'sessionUid': m.get('sessionUid'),
         'workout': wo_map[m['importedWorkoutId']]}
        for m in matches
        if m['matchConfidence'] != 'rejected' and m['importedWorkoutId'] in wo_map
    ]

    ctx = _progression_history(g.user_id, matches)
    history = _pt.compute_exercise_history(
        session_logs, program, matched_workouts=matched_wos,
        history_sessions=ctx['history_sessions'],
        logs_by_uid=ctx['logs_by_uid'],
        active_version_id=ctx['active_version_id'],
    )

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

    today = request.args.get('today') or str(_date.today())
    start = program_data.get('programStartDate') or program.get('start_date')
    so_far = _pt.exercises_scheduled_by(weeks, start, today)

    result = []
    for ex_id, (ex, slot) in ex_index.items():
        if ex_filter and ex_id != ex_filter:
            continue
        presc = _pt.prescribed_trajectory(weeks, ex_id, start, today)
        result.append({
            'exerciseId': ex_id,
            'name':       ex.get('name', ex_id),
            'history':    history.get(ex_id, []),
            'expected':   presc['expected'],
            'metricType': presc['metricType'],
            'unit':       presc['unit'],
            'target':     presc['target'],
            'scheduledSoFar': ex_id in so_far,
        })

    # Three counts, one window each: the program's movements, those whose
    # day has come, and those with a logged or matched point (earlier
    # programs' history included — the lift's record, not this block's).
    counts = {'inProgram': len(result),
              'soFar': sum(1 for r in result if r['scheduledSoFar']),
              'withData': sum(1 for r in result if r['history'])}
    return jsonify({'exercises': result, 'counts': counts})


@app.get('/api/progression/history')
@require_auth
def progression_history():
    snapshots = _health.list_progression_snapshots(g.user_id)
    return jsonify(snapshots)


@app.get('/api/progression/sessions')
@require_auth
def progression_sessions():
    # No `if not program_data: return []` guard: an athlete between programs
    # still has every matched session of every block they have trained.
    program_data = _db.get_user_program(g.user_id) or {}
    program  = program_data.get('currentProgram') or program_data
    matches  = [m for m in _health.get_matches(g.user_id) if m['matchConfidence'] != 'rejected']
    workouts = _health.get_workouts(g.user_id, summary_only=True)
    wo_map   = {wo['id']: wo for wo in workouts}
    ctx      = _progression_history(g.user_id, matches)
    return jsonify(_pt.compute_matched_sessions(
        matches, wo_map, program,
        history_sessions=ctx['history_sessions'],
        active_version_id=ctx['active_version_id'],
    ))


if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8000))
    print(f'Training API running on http://localhost:{port}/api')
    app.run(host='0.0.0.0', port=port, debug=True)
