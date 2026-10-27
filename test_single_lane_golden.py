"""Single-track programs are exactly what they were before compositions.

Every shipped track is generated through `POST /programs/generate` on three
schedules and its level(s), plus a few paths that carry state (a mid-track
start, an injury, overreached), and each response is hashed. The hashes were
recorded at a121a38, before the engine was refactored to compose several
tracks; a single-track request must reproduce them byte for byte, both as
`philosophy_id` and as a one-element `lanes` request.

    .venv/bin/python test_single_lane_golden.py            # check
    .venv/bin/python test_single_lane_golden.py --record   # rewrite the .json (only before an intended change)
"""
import hashlib
import json
import os
import re
import sys
from unittest.mock import patch

os.environ['SUPABASE_URL'] = ''
os.environ['DATABASE_URL'] = ''
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

GYM = ['barbell', 'rack', 'plates', 'kettlebell', 'dumbbell', 'pull_up_bar', 'rings', 'rower',
       'box', 'ghd', 'medicine_ball', 'rope', 'jump_rope', 'open_space', 'sandbag', 'sled', 'tire']

_DAY = {'session1': 'rest', 'session2': 'rest', 'session3': 'rest', 'session4': 'rest'}


def _week(**days):
    names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
    return {n: {**_DAY, **{f'session{i + 1}': s for i, s in enumerate(days.get(n[:3].lower(), []))}}
            for n in names}


PROFILES = {
    'three_45': {'days_per_week': 3, 'session_time_minutes': 45},
    'four_60': {'days_per_week': 4, 'session_time_minutes': 60},
    # Six days, a long Saturday and a second session on Tuesday (day_configs, split days).
    'six_long': {'days_per_week': 6, 'session_time_minutes': 75,
                 'weekly_schedule': _week(mon=['long'], tue=['short', 'mobility'], wed=['long'],
                                          thu=['short'], fri=['long'], sat=['long', 'long'])},
}


def _cases():
    """(name, body) for every shipped track and the stateful extras."""
    from src import loader
    from src.training_contract import load_contract
    cases = []
    for pid in sorted(p['id'] for p in loader.load_philosophies()):
        phil = loader.load_philosophy(pid)
        for track in phil.get('tracks') or []:
            contract = load_contract(pid, track['id'])
            levels = (contract or {}).get('training_levels') or ['novice', 'intermediate', 'advanced']
            mastered = sorted({e for lv in levels for e in
                               ((contract or {}).get('level_seeds') or {}).get(lv, [])})
            requires = sorted({e for m in (contract or {}).get('modules', [])
                               for e in m.get('requires_mastery') or []})
            for level in [lv for lv in ('novice', 'intermediate', 'advanced') if lv in levels][:2]:
                for pname, profile in PROFILES.items():
                    constraints = {'equipment': GYM, 'training_level': level, 'injury_flags': [],
                                   'mastered_exercises': sorted(set(mastered) | set(requires)),
                                   'kettlebell_count': 2, **profile}
                    cases.append((f'{pid}/{track["id"]}/{level}/{pname}',
                                  {'philosophy_id': pid, 'track_id': track['id'], 'constraints': constraints}))
    base = {'equipment': GYM, 'training_level': 'intermediate', 'injury_flags': [],
            'days_per_week': 6, 'session_time_minutes': 75, 'kettlebell_count': 2}
    cases += [
        ('extra/horsemen_mid_track', {'philosophy_id': 'horsemen_gpp', 'track_id': 'four_month_macro',
                                      'num_weeks': 6, 'week_in_program': 7,
                                      'constraints': {**base, 'start_phase': 'strength', 'periodization_week': 3}}),
        ('extra/uphill_specific', {'philosophy_id': 'uphill_athlete', 'track_id': 'full_program', 'num_weeks': 6,
                                   'constraints': {**base, 'start_phase': 'specific'}}),
        ('extra/ss_injury', {'philosophy_id': 'starting_strength', 'track_id': 'linear_progression', 'num_weeks': 6,
                             'constraints': {**base, 'training_level': 'novice', 'days_per_week': 3,
                                             'injury_flags': ['shoulder_impingement']}}),
        ('extra/crossfit_overreached', {'philosophy_id': 'crossfit', 'track_id': 'constantly_varied', 'num_weeks': 6,
                                        'constraints': {**base, 'fatigue_state': 'overreached'}}),
        ('extra/gym_jones_trace', {'philosophy_id': 'gym_jones', 'track_id': 'operator_fitness', 'num_weeks': 4,
                                   'trace': True, 'constraints': base}),
    ]
    return cases


# Volatile text the response may carry (none expected; kept for safety).
_VOLATILE = re.compile(r'"(generated_at|generatedAt)": "[^"]*"')


def _digest(client, body: dict) -> str:
    from src import db  # noqa: F401
    with patch('src.db.get_user_program', return_value=None), patch('src.db.save_user_program'):
        r = client.post('/api/programs/generate', json={**body, 'persist': False, 'start_date': '2026-11-02'})
    text = _VOLATILE.sub('', json.dumps({'status': r.status_code, 'body': r.get_json()}, sort_keys=True))
    return hashlib.sha256(text.encode()).hexdigest()


def _as_lanes(body: dict) -> dict:
    """The same request as a one-element composition."""
    out = {k: v for k, v in body.items() if k not in ('philosophy_id', 'track_id')}
    constraints = dict(body['constraints'])
    lane = {'philosophy_id': body['philosophy_id'], 'track_id': body['track_id'], 'weight': 1}
    for key in ('start_phase', 'periodization_week'):
        if key in constraints:
            lane[key] = constraints.pop(key)
    return {**out, 'constraints': constraints, 'lanes': [lane]}


def main():
    with patch('src.db._get_pg_conn', return_value=None):
        import api
    client = api.app.test_client()
    record = '--record' in sys.argv
    lanes_too = '--no-lanes' not in sys.argv and not record
    got, failures = {}, []
    for name, body in _cases():
        got[name] = _digest(client, body)
        if record:
            continue
        want = GOLDEN.get(name)
        if want is None:
            failures.append(f'{name}: no recorded hash')
        elif got[name] != want:
            failures.append(f'{name}: changed')
        elif lanes_too and _digest(client, _as_lanes(body)) != want:
            failures.append(f'{name}: a one-element lanes request differs')
    if record:
        with open(GOLDEN_PATH, 'w') as f:
            json.dump(got, f, indent=1, sort_keys=True)
            f.write('\n')
        print(f'recorded {len(got)} programs')
        return 0
    for f in failures:
        print('FAIL', f)
    print(f'{len(got) - len(failures)}/{len(got)} single-track programs unchanged')
    return 1 if failures else 0


GOLDEN_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'test_single_lane_golden.json')
GOLDEN = json.load(open(GOLDEN_PATH)) if os.path.exists(GOLDEN_PATH) else {}

if __name__ == '__main__':
    sys.exit(main())
