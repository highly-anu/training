#!/usr/bin/env python
"""The program preview's server half: does a profile change change the program
(POST /programs/constraint-change), adopting a change that does not
(PATCH /user/program/constraints), and the Held back runs for every athlete
(POST /programs/impact, the Dev Lab's constraint impact out from behind the
authoring gate).

Before this the Profile offered a regenerate for any difference between the
profile and the program's constraints — adding a kettlebell to a Starting
Strength athlete's kit, which no session uses, asked to rebuild the plan.

Run: SUPABASE_URL='' DATABASE_URL='' .venv/bin/python test_program_preview.py
"""
from __future__ import annotations

import os
import sys

os.environ.setdefault('SUPABASE_URL', '')
os.environ.setdefault('DATABASE_URL', '')

from src import constraint_impact  # noqa: E402

FAILURES: list[str] = []


def check(label: str, condition: bool, detail=None) -> None:
    if condition:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label} {'' if detail is None else detail}")
        FAILURES.append(label)


# ── diff_programs, on hand-built programs ────────────────────────────────────

def _session(modality, arch, *exercises, gap=None):
    eas = [{'slot_role': f's{i}', 'exercise': {'id': e, 'name': e} if e else None,
            **({'gap_reason': gap} if e is None and gap else {})} for i, e in enumerate(exercises)]
    return {'modality': modality, 'archetype': {'id': arch, 'name': arch}, 'exercises': eas}


def _program(*weeks):
    return {'weeks': [{'week_number': n + 1, 'schedule': days} for n, days in enumerate(weeks)]}


def test_diff_programs() -> None:
    print('before and after one change')
    week = {'Monday': [_session('max_strength', 'a', 'back_squat', 'press')],
            'Wednesday': [_session('aerobic_base', 'z2', 'run')]}
    same = constraint_impact.diff_programs(_program(week, week), _program(week, week))
    check('the same program is unaffected', same['affected'] is False and same['sessions'] == {
        'total': 4, 'changed': 0} and same['first_week_number'] is None, same)

    emptied = {**week, 'Monday': [_session('max_strength', 'a', None, 'press', gap='EQUIPMENT_UNAVAILABLE')]}
    d = constraint_impact.diff_programs(_program(week, week), _program(week, emptied))
    check('an emptied slot is a change, from the week it happens',
          d['affected'] and d['sessions']['changed'] == 1 and d['first_week_number'] == 2, d)
    slot = d['changes'][0]['slots'][0]
    check('the slot says what it was and why it is empty',
          d['changes'][0]['change'] == 'slots' and slot['before']['id'] == 'back_squat'
          and slot['after'] is None and slot['gap_after'] == 'EQUIPMENT_UNAVAILABLE', slot)

    other = {**week, 'Wednesday': [_session('aerobic_base', 'hills', 'run')]}
    d = constraint_impact.diff_programs(_program(week), _program(other))
    check('another archetype', [c['change'] for c in d['changes']] == ['archetype'], d['changes'])
    moved = {**week, 'Wednesday': [_session('mobility', 'flow', 'cars')]}
    d = constraint_impact.diff_programs(_program(week), _program(moved))
    check('another modality', [c['change'] for c in d['changes']] == ['modality'], d['changes'])
    fewer = {'Monday': week['Monday']}
    d = constraint_impact.diff_programs(_program(week), _program(fewer))
    check('a session that goes', [c['change'] for c in d['changes']] == ['removed'], d['changes'])
    d = constraint_impact.diff_programs(_program(week), {'weeks': []})
    check('a refused program changes every session', d['sessions']['changed'] == 2
          and all(c['change'] == 'removed' for c in d['changes']), d)


# ── The routes ───────────────────────────────────────────────────────────────

ATHLETE = {'days_per_week': 3, 'session_time_minutes': 90, 'training_level': 'novice',
           'equipment': ['barbell', 'rack', 'plates', 'pull_up_bar', 'bench'], 'injury_flags': [],
           'fatigue_state': 'normal', 'periodization_week': 1}


def _change(client, after: dict, before: dict | None = None, phil='starting_strength', weeks=3):
    return client.post('/api/programs/constraint-change', json={
        'philosophy_id': phil, 'num_weeks': weeks,
        'constraints': after, 'baseline_constraints': before or ATHLETE})


def test_constraint_change() -> None:
    print('does a profile change change the program')
    import api
    client = api.app.test_client()

    res = _change(client, {**ATHLETE, 'equipment': ATHLETE['equipment'] + ['kettlebell', 'rings']})
    body = res.get_json()
    check('200', res.status_code == 200, (res.status_code, body))
    check('adding equipment no session uses changes nothing',
          body.get('affected') is False and body['comparable'] and body['sessions']['total'] > 0, body)
    check('no program comes back when nothing changed', 'program' not in body)

    body = _change(client, {**ATHLETE, 'equipment': ['pull_up_bar', 'bench']}).get_json()
    check('removing the barbell changes the program', body.get('affected') is True, body.get('sessions'))
    check('the tail with the new constraints comes back for the preview', 'program' in body
          and 'validation' in body['program'], list(body))

    body = _change(client, {**ATHLETE, 'injury_flags': ['knee_meniscus_post_op']}).get_json()
    check('a knee flag changes a squat program', body.get('affected') is True, body.get('sessions'))
    first = body.get('first_week_number')
    check('and says from which week', first == 1, first)

    res = client.post('/api/programs/constraint-change', json={'philosophy_id': 'starting_strength'})
    check('both constraint sets are required', res.status_code == 422, res.status_code)

    # Gym Jones on a bare kit: a barbell is what most of its sessions want.
    bare = {**ATHLETE, 'training_level': 'intermediate', 'days_per_week': 4, 'equipment': ['kettlebell']}
    body = _change(client, {**bare, 'equipment': ['kettlebell', 'barbell', 'plates', 'rack']}, bare,
                   phil='gym_jones', weeks=2).get_json()
    check('adding equipment that fills slots does change it', body.get('affected') is True, body.get('sessions'))


def test_heavy_runs_are_gated() -> None:
    print('one heavy run at a time, cached on its body')
    import api
    client = api.app.test_client()
    calls = []
    real = api._generate_program_inner

    def counting(body):
        calls.append(1)
        return real(body)
    api._generate_program_inner = counting
    try:
        api._HEAVY_CACHE.clear()
        after = {**ATHLETE, 'equipment': ATHLETE['equipment'] + ['sandbag']}
        _change(client, after, weeks=1)
        n = len(calls)
        again = _change(client, after, weeks=1)
        check('the same body is answered from the cache', again.status_code == 200 and len(calls) == n,
              (n, len(calls)))
        api._HEAVY_USERS.add('local-dev-user')
        try:
            busy = _change(client, {**after, 'session_time_minutes': 60}, weeks=1)
        finally:
            api._HEAVY_USERS.discard('local-dev-user')
        check('a second run for the same athlete is told to retry', busy.status_code == 429
              and busy.get_json().get('busy') is True, busy.status_code)
    finally:
        api._generate_program_inner = real


def test_impact_for_every_athlete() -> None:
    print('Held back runs without the authoring gate')
    import api
    client = api.app.test_client()
    real = api._authoring_enabled
    api._authoring_enabled = lambda: False
    try:
        body = {'philosophy_id': 'gym_jones', 'num_weeks': 1,
                'constraints': {**ATHLETE, 'training_level': 'intermediate', 'days_per_week': 4,
                                'equipment': ['kettlebell']}}
        dev = client.post('/api/dev/constraint-impact', json=body)
        check('the Dev Lab route keeps its gate', dev.status_code == 403, dev.status_code)
        res = client.post('/api/programs/impact', json=body)
        out = res.get_json()
        check('the preview route answers a signed-in athlete', res.status_code == 200, (res.status_code, out))
        check('with what the equipment holds back and what would restore it',
              out.get('lifted') == ['equipment'] and (out.get('restore') or {}).get('equipment'), out.get('restore'))
    finally:
        api._authoring_enabled = real


def test_adopt_constraints() -> None:
    print('an unaffected change is adopted')
    import api
    from src import db
    store = {'program': {'currentProgram': {'weeks': [], 'constraints': {**ATHLETE, 'session_time_minutes': 75}},
                         'programStartDate': '2026-10-19'}, 'rev': 1}
    saved = []
    orig = (db.get_user_program, db.save_user_program, db.get_program_revision)

    def save(user_id, data):
        saved.append(data)
        store['program'] = data
        store['rev'] += 1
    db.get_user_program = lambda user_id: store['program']
    db.save_user_program = save
    db.get_program_revision = lambda user_id: str(store['rev'])
    try:
        client = api.app.test_client()
        res = client.patch('/api/user/program/constraints', json={
            'baseRevision': '1',
            'constraints': {'equipment': ['barbell', 'kettlebell'], 'session_time_minutes': 20}})
        body = res.get_json()
        check('200 with the next revision', res.status_code == 200 and body['revision'] == '2', body)
        cons = store['program']['currentProgram']['constraints']
        check('the equipment is the profile\'s now', cons['equipment'] == ['barbell', 'kettlebell'], cons)
        check('only the adoptable keys move', cons['session_time_minutes'] == 75, cons)
        stale = client.patch('/api/user/program/constraints', json={
            'baseRevision': '1', 'constraints': {'training_level': 'advanced'}})
        check('a stale revision is refused', stale.status_code == 409
              and stale.get_json()['detail'] == 'stale_revision', stale.status_code)
        check('and nothing is written', len(saved) == 1, len(saved))
        empty = client.patch('/api/user/program/constraints', json={'constraints': {'foo': 1}})
        check('nothing to adopt is a 422', empty.status_code == 422, empty.status_code)
    finally:
        db.get_user_program, db.save_user_program, db.get_program_revision = orig


def main() -> int:
    for t in (test_diff_programs, test_constraint_change, test_heavy_runs_are_gated,
              test_impact_for_every_athlete, test_adopt_constraints):
        t()
    if FAILURES:
        print(f"\n{len(FAILURES)} failed: {FAILURES}")
        return 1
    print('\nall passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
