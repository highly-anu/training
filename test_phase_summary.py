#!/usr/bin/env python
"""src/phase_summary.py: how sessions and exercises change from phase to phase.

Run: SUPABASE_URL='' .venv/bin/python test_phase_summary.py
"""
from __future__ import annotations

import os
import sys

from src import phase_summary

FAILURES: list[str] = []


def check(label: str, condition: bool, detail: str = '') -> None:
    if condition:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label} {detail}")
        FAILURES.append(label)


def ex(eid, kg=None, minutes=None):
    load = {}
    if kg is not None:
        load = {'sets': 3, 'reps': 5, 'weight_kg': kg}
    if minutes is not None:
        load = {'duration_minutes': minutes, 'zone_lower': 1, 'zone_upper': 2}
    return {'exercise': {'id': eid, 'name': eid.replace('_', ' ').title()},
            'slot_type': 'sets_reps' if kg is not None else 'time_domain', 'load': load}


def sess(mod, aid, exercises, minutes=60):
    return {'modality': mod, 'archetype': {'id': aid, 'name': aid.title(),
                                           'duration_estimate_minutes': minutes},
            'exercises': exercises}


def week(n, pid, schedule, deload=False):
    return {'week_number': n, 'phase': 'base', 'phase_id': pid, 'phase_name': pid.title(),
            'framework': f'fw_{pid}', 'is_deload': deload, 'schedule': schedule}


def base_week(n, kg):
    return week(n, 'base', {
        'Monday': [sess('max_strength', 'lift', [ex('back_squat', kg)])],
        'Wednesday': [sess('aerobic_base', 'z2', [ex('run', minutes=60)])],
        'Friday': [sess('max_strength', 'lift', [ex('back_squat', kg + 2.5)])],
    })


def build_week(n):
    return week(n, 'build', {
        'Monday': [sess('max_strength', 'lift', [ex('back_squat', 120)])],
        'Tuesday': [sess('anaerobic_intervals', 'threshold', [ex('hill_repeat', minutes=40)])],
        'Thursday': [sess('aerobic_base', 'z2', [ex('run', minutes=90)])],
        'Saturday': [sess('aerobic_base', 'z2', [ex('run', minutes=90)])],
    })


def test_build() -> None:
    print('phase summary')
    weeks = [base_week(1, 100), base_week(2, 105), week(3, 'base', {
        'Monday': [sess('max_strength', 'lift', [ex('back_squat', 80)])]}, deload=True),
        build_week(4), build_week(5)]
    goal = {'phase_sequence': [{'phase_id': 'base', 'name': 'Base'}, {'phase_id': 'build', 'name': 'Build'}]}
    out = phase_summary.build(weeks, goal)
    check('one entry per phase, in order', [p['phase_id'] for p in out] == ['base', 'build'])
    base, build = out
    check('weeks and deloads counted', base['weeks'] == 3 and base['deload_weeks'] == 1
          and base['week_start'] == 1 and base['week_end'] == 3)
    check('weekly shape skips the deload', base['sessions_per_week'] == {'max_strength': 2.0, 'aerobic_base': 1.0},
          str(base['sessions_per_week']))
    check('lifts run first to last, deload excluded',
          base['lifts'] == [{'id': 'back_squat', 'name': 'Back Squat', 'first_kg': 100, 'last_kg': 107.5}],
          str(base['lifts']))
    check('the first phase marks nothing', all(a['status'] is None for a in base['archetypes']))
    statuses = {a['id']: a['status'] for a in build['archetypes']}
    lift = next(a for a in base['archetypes'] if a['id'] == 'lift')
    check('per_week counts working weeks only', lift['sessions'] == 5 and lift['per_week'] == 2.0,
          str(lift))
    check('new and continued archetypes',
          statuses == {'threshold': 'new', 'z2': 'continued', 'lift': 'continued'}, str(statuses))
    check('a new exercise', any(e['id'] == 'hill_repeat' and e['status'] == 'new' for e in build['exercises']))
    changes = ' | '.join(build['changes'])
    check('changes name the modality that enters', 'Anaerobic intervals enters' in changes, changes)
    check('and the one that drops', 'Max strength 2 → 1×/week' in changes, changes)
    check('and the volume', 'Weekly volume' in changes, changes)
    check('hard minutes are counted', build['intensity'].get('zone1_2', 0) > 0)
    dropped = phase_summary.build([build_week(1), base_week(2, 100)])[1]['dropped']
    check('dropped archetypes are listed', [a['id'] for a in dropped['archetypes']] == ['threshold'])


def test_api() -> None:
    print('the API serves it and never stores it')
    os.environ.setdefault('SUPABASE_URL', '')
    import api
    from src import db
    client = api.app.test_client()
    # Uphill's contract (since 2026-10-21) asks for six days and a kettlebell;
    # twelve weeks reach its second phase (eight of transition, then base).
    body = {'philosophy_id': 'uphill_athlete', 'num_weeks': 12,
            'constraints': {'days_per_week': 6, 'session_time_minutes': 75, 'training_level': 'intermediate',
                            'equipment': ['barbell', 'rack', 'plates', 'pull_up_bar', 'ruck_pack',
                                          'open_space', 'box', 'dumbbell', 'kettlebell'], 'injury_flags': []}}
    resp = client.post('/api/programs/generate', json=body)
    data = resp.get_json() or {}
    summary = data.get('phase_summary') or []
    check('generate returns phase_summary', resp.status_code == 200 and len(summary) == 2,
          f"{resp.status_code} {[p.get('phase_id') for p in summary]}")
    saved = {}
    real = db._get_pg_conn
    try:
        db._get_pg_conn = lambda: None
        db._ensure_local_storage()
        db.save_user_program('phase-summary-test', {'currentProgram': {**data, 'phase_summary': summary}})
        import json
        path = db._local_storage_dir / 'phase-summary-test_program.json'
        saved = json.loads(path.read_text())
        path.unlink()
    finally:
        db._get_pg_conn = real
    check('save strips it', 'phase_summary' not in saved.get('currentProgram', {'phase_summary': 1}))


def test_put_answers_with_the_summary() -> None:
    print('a save answers with the summary of the weeks it saved')
    os.environ.setdefault('SUPABASE_URL', '')
    import api
    from src import db
    stored = {}
    patches = {
        'get_user_program': lambda uid: stored.get(uid),
        'save_user_program': lambda uid, data: stored.__setitem__(uid, data),
        'get_program_revision': lambda uid: 'r1',
    }
    saved_db = {k: getattr(db, k) for k in patches}
    saved_hist = api._record_program_history
    try:
        for k, v in patches.items():
            setattr(db, k, v)
        api._record_program_history = lambda *a, **k: {}
        weeks = [base_week(1, 100), build_week(2)]
        resp = api.app.test_client().put('/api/user/program', json={
            'currentProgram': {'weeks': weeks, 'goal': {'phase_sequence': []}},
            'sourceGoalIds': [], 'baseRevision': 'r1'})
        body = resp.get_json() or {}
        summary = body.get('phaseSummary') or []
        check('PUT returns phaseSummary', resp.status_code == 200 and [p['phase_id'] for p in summary] == ['base', 'build'],
              f"{resp.status_code} {body}")
    finally:
        for k, v in saved_db.items():
            setattr(db, k, v)
        api._record_program_history = saved_hist


def main() -> int:
    test_build()
    test_api()
    test_put_answers_with_the_summary()
    print()
    if FAILURES:
        print(f"{len(FAILURES)} failure(s)")
        return 1
    print('all phase summary tests passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
