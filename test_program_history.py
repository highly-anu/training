#!/usr/bin/env python
"""The pure half of program history: hashing, flattening, interval arithmetic.

No database. These are the invariants the stored history depends on, and the
ones that are cheapest to get wrong:

  * the skeleton hash must be blind to everything the self-healing re-saves and
    the iOS round-trip change, or every app open mints a spurious version;
  * session_uid must stay unique on a spliced program, where one `week_number`
    legitimately appears at two array indices;
  * a flattened row's date must agree with the matcher's own date function, or
    the same workout matches differently through history than through the
    current program.

Run: .venv/bin/python test_program_history.py
"""
from __future__ import annotations

import copy
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from src import program_history as ph
from src import workout_matcher as wm

_failures: list[str] = []


def check(label: str, condition: bool, detail: str = '') -> None:
    if condition:
        print(f'  ok   {label}')
    else:
        print(f'  FAIL {label}' + (f' — {detail}' if detail else ''))
        _failures.append(label)


def session(modality: str, arch_id: str, minutes: int, *ex_ids: str) -> dict:
    return {
        'modality': modality,
        'archetype': {'id': arch_id, 'name': arch_id.title(),
                      'duration_estimate_minutes': minutes},
        'exercises': [
            {'exercise': {'id': e, 'name': e.title()},
             'slot': {'slot_type': 'linear_load', 'role': 'primary'},
             'load': {'sets': 3, 'reps': 5, 'weight_kg': 100.0}}
            for e in ex_ids
        ],
    }


def envelope(weeks: list[dict], start: str | None = '2026-03-02') -> dict:
    return {
        'currentProgram': {
            'goal': {'id': '_phil_uphill_athlete', 'name': 'Uphill Athlete'},
            'constraints': {'training_level': 'intermediate'},
            'validation': {'feasible': True},
            'volume_summary': [],
            'coverage_report': {},
            'weeks': weeks,
        },
        'programStartDate': start,
        'eventDate': None,
        'sourceGoalIds': ['uphill_athlete'],
        'sourceGoalWeights': {},
    }


def base_weeks() -> list[dict]:
    return [
        {'week_number': 1, 'phase': 'base', 'is_deload': False, 'schedule': {
            'Monday':    [session('max_strength', 'squat_day', 60, 'back_squat', 'bench')],
            'Wednesday': [session('aerobic_base', 'z2_run', 90, 'easy_run')],
            'Saturday':  [session('aerobic_base', 'z2_run', 120, 'long_run'),
                          session('mobility', 'flow', 20, 'hip_flow')],
        }},
        {'week_number': 2, 'phase': 'base', 'is_deload': False, 'schedule': {
            'Monday':    [session('max_strength', 'squat_day', 60, 'back_squat', 'bench')],
            'Wednesday': [session('aerobic_base', 'z2_run', 95, 'easy_run')],
        }},
    ]


# ── Hash invariance ──────────────────────────────────────────────────────────

def test_hash_invariance() -> None:
    print('\nskeleton hash is blind to what the heals and iOS rewrite')
    env = envelope(base_weeks())
    want = ph.skeleton_hash(env)

    # Heal 1: the envelope wrap. A bare GeneratedProgram is the same plan.
    bare = dict(env['currentProgram'])
    bare['program_start_date'] = env['programStartDate']
    check('an envelope-less program hashes the same', ph.skeleton_hash(bare) == want)

    # Heal 2: goal + volume_summary reconstruction.
    healed = copy.deepcopy(env)
    healed['currentProgram']['goal'] = {'id': 'rebuilt', 'name': 'Rebuilt'}
    healed['currentProgram']['volume_summary'] = [{'week': 1, 'minutes': 300}]
    check('rebuilding goal and volume_summary hashes the same',
          ph.skeleton_hash(healed) == want)

    # Heal 3: legacy snake_case top-level keys.
    legacy = {'current_program': env['currentProgram'],
              'program_start_date': env['programStartDate'],
              'source_goal_ids': ['uphill_athlete']}
    check('legacy snake_case top-level keys hash the same',
          ph.skeleton_hash(legacy) == want)

    # An iOS save: no goal, no slot, blanked weights, reps as a float.
    ios = copy.deepcopy(env)
    ios['currentProgram'].pop('goal')
    ios['currentProgram'].pop('constraints')
    ios['sourceGoalWeights'] = {}
    for week in ios['currentProgram']['weeks']:
        week.pop('is_deload')
        for sessions in week['schedule'].values():
            for s in sessions:
                for ea in s['exercises']:
                    ea.pop('slot')
                    ea['load']['reps'] = 5.0
    check('an iOS round-trip hashes the same', ph.skeleton_hash(ios) == want,
          f'{ph.skeleton_hash(ios)} != {want}')

    # Swift re-encodes the schedule dictionary in arbitrary order.
    shuffled = copy.deepcopy(env)
    for week in shuffled['currentProgram']['weeks']:
        week['schedule'] = dict(reversed(list(week['schedule'].items())))
    check('a permuted schedule day order hashes the same',
          ph.skeleton_hash(shuffled) == want)

    # Archetype display metadata is not the plan.
    cosmetic = copy.deepcopy(env)
    for week in cosmetic['currentProgram']['weeks']:
        for sessions in week['schedule'].values():
            for s in sessions:
                s['archetype']['name'] = 'Renamed'
                s['archetype']['duration_estimate_minutes'] = 45
    check('renaming an archetype hashes the same',
          ph.skeleton_hash(cosmetic) == want)


def test_hash_sensitivity() -> None:
    print('\nskeleton hash changes when the plan changes')
    env = envelope(base_weeks())
    want = ph.skeleton_hash(env)

    moved = copy.deepcopy(env)
    week = moved['currentProgram']['weeks'][0]
    week['schedule']['Tuesday'] = week['schedule'].pop('Monday')
    check('moving a session to another day', ph.skeleton_hash(moved) != want)

    swapped = copy.deepcopy(env)
    swapped['currentProgram']['weeks'][0]['schedule']['Monday'][0] = \
        session('max_strength', 'squat_day', 60, 'front_squat', 'bench')
    check('swapping an exercise', ph.skeleton_hash(swapped) != want)

    restarted = envelope(base_weeks(), start='2026-03-09')
    check('changing the start date', ph.skeleton_hash(restarted) != want)

    rearch = copy.deepcopy(env)
    rearch['currentProgram']['weeks'][0]['schedule']['Monday'][0]['archetype']['id'] = 'deadlift_day'
    check('changing the archetype id', ph.skeleton_hash(rearch) != want)

    dropped = copy.deepcopy(env)
    dropped['currentProgram']['weeks'][0]['schedule'].pop('Saturday')
    check('removing a day', ph.skeleton_hash(dropped) != want)

    phase = copy.deepcopy(env)
    phase['currentProgram']['weeks'][1]['phase'] = 'build'
    check('changing a week phase', ph.skeleton_hash(phase) != want)

    reordered = copy.deepcopy(env)
    sat = reordered['currentProgram']['weeks'][0]['schedule']['Saturday']
    sat.reverse()
    check('reordering two sessions on one day', ph.skeleton_hash(reordered) != want)


def test_version_id_is_user_scoped() -> None:
    print('\nversion id')
    env = envelope(base_weeks())
    check('two athletes with identical programs get different version ids',
          ph.version_id('user-a', env) != ph.version_id('user-b', env))
    check('the same athlete and program is stable',
          ph.version_id('user-a', env) == ph.version_id('user-a', copy.deepcopy(env)))


def test_content_hash_and_richness() -> None:
    print('\ncontent hash and richness')
    env = envelope(base_weeks())
    with_rev = dict(env, revision='2026-09-29T10:00:00', programVersionId='abc')
    check('read-time injections do not change the content hash',
          ph.content_hash(with_rev) == ph.content_hash(env))

    level = copy.deepcopy(env)
    level['currentProgram']['constraints']['training_level'] = 'advanced'
    check('a different training level changes the content hash',
          ph.content_hash(level) != ph.content_hash(env))
    check('...but not the skeleton hash',
          ph.skeleton_hash(level) == ph.skeleton_hash(env))

    stripped = copy.deepcopy(env)
    stripped['currentProgram'].pop('goal')
    for week in stripped['currentProgram']['weeks']:
        for sessions in week['schedule'].values():
            for s in sessions:
                for ea in s['exercises']:
                    ea.pop('slot')
    check('an iOS-stripped copy is less rich than the server copy',
          ph.richness(stripped) < ph.richness(env),
          f'{ph.richness(stripped)} vs {ph.richness(env)}')


# ── Flattening ───────────────────────────────────────────────────────────────

def test_flatten_dates_agree_with_the_matcher() -> None:
    print('\nflattened dates agree with workout_matcher.session_calendar_date')
    for start in ('2026-03-02', '2026-03-05'):   # a Monday and a Thursday
        env = envelope(base_weeks(), start=start)
        vid = ph.version_id('u', env)
        rows = ph.flatten_program(vid, env)
        ok = all(
            r['date'] == wm.session_calendar_date(start, r['week_index'], r['day_name'])
            for r in rows
        )
        check(f'every row date matches, start={start}', ok)

    env = envelope(base_weeks())
    rows = ph.flatten_program(ph.version_id('u', env), env)
    check('week 0 Monday is the start date',
          next(r['date'] for r in rows if r['week_index'] == 0 and r['day_name'] == 'Monday')
          == '2026-03-02')
    check('week 1 Monday is start + 7',
          next(r['date'] for r in rows if r['week_index'] == 1 and r['day_name'] == 'Monday')
          == '2026-03-09')


def test_flatten_matches_the_matchers_own_index() -> None:
    print('\nthe history index is the matcher index plus a uid')
    env = envelope(base_weeks())
    start = env['programStartDate']
    vid = ph.version_id('u', env)

    from_history = ph.index_by_date(ph.flatten_program(vid, env))
    from_program = wm.index_sessions_by_date(env['currentProgram'], start)

    check('same dates', sorted(from_history) == sorted(from_program),
          f'{sorted(from_history)} vs {sorted(from_program)}')
    same = all(
        [{k: v for k, v in c.items() if k != 'sessionUid'} for c in from_history[d]]
        == from_program[d]
        for d in from_program
    )
    check('same candidates modulo sessionUid', same)

    # The parity that actually matters: the matcher agrees on both indexes.
    workouts = [{'id': 'w1', 'date': '2026-03-04',
                 'inferredModalityId': 'aerobic_base', 'durationMinutes': 90}]
    a = wm.auto_match_indexed(workouts, from_program, [])
    b = wm.auto_match_indexed(workouts, from_history, [])
    check('auto_match agrees on both indexes',
          [(m['importedWorkoutId'], m['sessionKey']) for m in a['confirmed']]
          == [(m['importedWorkoutId'], m['sessionKey']) for m in b['confirmed']])
    check('the history match carries a session uid',
          bool(b['confirmed'] and b['confirmed'][0].get('sessionUid')))
    check('the program-only match carries none',
          bool(a['confirmed']) and 'sessionUid' not in a['confirmed'][0])


def test_spliced_program_uids_stay_unique() -> None:
    """The regression test for keying identity on week_number.

    src/generator.py numbers weeks from `week_in_program`, and with an event
    date phase_calendar starts that at the athlete's absolute program week. A
    partial regenerate splices such a tail onto the kept head, so `week_number`
    16 can sit at two array indices. Keyed on week_number the primary key
    collides and the whole version is lost.
    """
    print('\na spliced program (weeks 1..16 + 16..31)')
    weeks = []
    for n in list(range(1, 17)) + list(range(16, 32)):
        weeks.append({'week_number': n, 'phase': 'base', 'schedule': {
            'Monday': [session('max_strength', 'squat_day', 60, 'back_squat')],
        }})
    env = envelope(weeks)
    vid = ph.version_id('u', env)
    rows = ph.flatten_program(vid, env)

    uids = [r['session_uid'] for r in rows]
    check('a duplicate week_number really is present',
          len({r['week_number'] for r in rows}) < len(rows),
          f"{len({r['week_number'] for r in rows})} numbers for {len(rows)} rows")
    check('session uids are unique', len(set(uids)) == len(uids),
          f'{len(uids) - len(set(uids))} collisions')
    check('legacy keys collide, as expected',
          len({r['legacy_key'] for r in rows}) < len(rows))
    check('dates are unique, so (legacy_key, date) disambiguates',
          len({r['date'] for r in rows}) == len(rows))


def test_flatten_edge_cases() -> None:
    print('\nflattening edge cases')
    check('no start date yields no rows',
          ph.flatten_program('v', envelope(base_weeks(), start=None)) == [])
    check('a malformed start date yields no rows',
          ph.flatten_program('v', envelope(base_weeks(), start='not-a-date')) == [])
    check('an empty program yields no rows',
          ph.flatten_program('v', envelope([])) == [])
    check('no program at all yields no rows', ph.flatten_program('v', {}) == [])

    numberless = [{'phase': 'base', 'schedule': {
        'Monday': [session('mobility', 'flow', 20, 'hip_flow')]}}]
    rows = ph.flatten_program('v', envelope(numberless))
    check('a week with no number falls back to its position',
          rows and rows[0]['legacy_key'] == '1-Monday-0',
          rows[0]['legacy_key'] if rows else 'no rows')

    camel = {'currentProgram': {'weeks': [{'weekNumber': 3, 'schedule': {
        'Monday': [{'modality': 'aerobic_base',
                    'archetype': {'id': 'z2', 'durationEstimateMinutes': 75}}]}}]},
             'programStartDate': '2026-03-02'}
    rows = ph.flatten_program('v', camel)
    check('camelCase weekNumber and duration are read',
          rows and rows[0]['legacy_key'] == '3-Monday-0' and rows[0]['duration_min'] == 75,
          str(rows))

    missing = {'currentProgram': {'weeks': [{'week_number': 1, 'schedule': {
        'Monday': [{'modality': 'aerobic_base'}]}}]},
               'programStartDate': '2026-03-02'}
    rows = ph.flatten_program('v', missing)
    check('a session with no archetype gets the default duration',
          rows and rows[0]['duration_min'] == wm.RULES['defaultSessionMinutes'])

    unknown_day = {'currentProgram': {'weeks': [{'week_number': 1, 'schedule': {
        'Someday': [session('mobility', 'flow', 20, 'x')]}}]},
                   'programStartDate': '2026-03-02'}
    check('an unknown day name is skipped',
          ph.flatten_program('v', unknown_day) == [])


# ── Interval arithmetic ──────────────────────────────────────────────────────

def test_intervals() -> None:
    print('\nactivation intervals')
    d = date.fromisoformat

    check('the first activation runs from the program start date, not from now',
          ph.compute_effective_from(d('2026-09-29'), d('2026-03-02'), True)
          == d('2026-03-02'))
    check('a later activation starts the day it was activated',
          ph.compute_effective_from(d('2026-09-29'), d('2026-03-02'), False)
          == d('2026-09-29'))
    check('a future start date is honoured, leaving the gap to the predecessor',
          ph.compute_effective_from(d('2026-09-29'), d('2026-10-05'), False)
          == d('2026-10-05'))

    check('an interval closes at its successor',
          ph.clamp_effective_to(d('2026-03-02'), d('2026-09-29')) == d('2026-09-29'))
    check('two activations in one day give a zero-length interval',
          ph.clamp_effective_to(d('2026-09-29'), d('2026-09-29')) == d('2026-09-29'))
    check('a successor that would invert the interval is clamped',
          ph.clamp_effective_to(d('2026-09-29'), d('2026-03-02')) == d('2026-09-29'))


if __name__ == '__main__':
    test_hash_invariance()
    test_hash_sensitivity()
    test_version_id_is_user_scoped()
    test_content_hash_and_richness()
    test_flatten_dates_agree_with_the_matcher()
    test_flatten_matches_the_matchers_own_index()
    test_spliced_program_uids_stay_unique()
    test_flatten_edge_cases()
    test_intervals()

    if _failures:
        print(f'\n{len(_failures)} failure(s): ' + ', '.join(_failures))
        sys.exit(1)
    print('\nAll program history tests passed.')
