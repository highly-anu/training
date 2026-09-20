#!/usr/bin/env python
"""Cross-source dedup: one activity, one row, richest data wins.

The case that matters: a single morning run can arrive as a Garmin webhook
push, an Apple Health relay from the phone, a Strava pull and a hand-uploaded
.fit. Each carries a different deterministic id, so nothing upstream stops them
becoming four rows.

Run: .venv/bin/python test_workout_dedupe.py
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from src import workout_dedupe as dd

_failures: list[str] = []


def check(label: str, condition: bool, detail: str = '') -> None:
    if condition:
        print(f'  ok   {label}')
    else:
        print(f'  FAIL {label}' + (f' — {detail}' if detail else ''))
        _failures.append(label)


def workout(source, start='2026-03-28T08:00:00+00:00', duration=60,
            modality='aerobic_base', **extra):
    w = {
        'id': f'{source}-{start}-{duration}',
        'source': source,
        'startTime': start,
        'durationMinutes': duration,
        'inferredModalityId': modality,
        'heartRate': {},
    }
    w.update(extra)
    return w


def test_dedupe_key() -> None:
    print('\ndedupe_key')
    a = workout('garmin', '2026-03-28T08:00:00+00:00', 60)
    b = workout('strava', '2026-03-28T08:00:30+00:00', 60)
    check('the same activity from two sources shares a key',
          dd.dedupe_key(a) == dd.dedupe_key(b))
    check('the key ignores the source',
          dd.dedupe_key(a) == dd.dedupe_key(workout('apple_health')))
    c = workout('garmin', '2026-03-28T14:00:00+00:00', 60)
    check('a different activity gets a different key', dd.dedupe_key(a) != dd.dedupe_key(c))
    check('a workout with no start time has no key',
          dd.dedupe_key({'durationMinutes': 60}) is None)


def test_same_activity() -> None:
    print('\nis_same_activity')
    base = workout('garmin')
    check('identical start and duration',
          dd.is_same_activity(base, workout('strava')))
    check('a two-minute start difference still matches',
          dd.is_same_activity(base, workout('strava', '2026-03-28T08:02:00+00:00')))
    check('a ten-minute start difference does not',
          not dd.is_same_activity(base, workout('strava', '2026-03-28T08:10:00+00:00')))
    check('a two-minute duration difference still matches',
          dd.is_same_activity(base, workout('strava', duration=58)))
    check('a thirty-minute duration difference does not',
          not dd.is_same_activity(base, workout('strava', duration=30)))
    check('a short workout gets the absolute tolerance',
          dd.is_same_activity(workout('garmin', duration=10),
                              workout('strava', duration=12)))
    check('different modality families never merge',
          not dd.is_same_activity(base, workout('strava', modality='max_strength')))
    check('within one family they do merge',
          dd.is_same_activity(base, workout('strava', modality='anaerobic_intervals')))
    check('an unlabelled workout is not blocked',
          dd.is_same_activity(base, workout('strava', modality=None)))


def test_source_rank() -> None:
    print('\nsource ranking')
    check('fit_file outranks strava', dd.source_rank('fit_file') < dd.source_rank('strava'))
    check('garmin outranks apple_health', dd.source_rank('garmin') < dd.source_rank('apple_health'))
    check('an unknown source ranks last',
          dd.source_rank('mystery') >= dd.source_rank('manual'))


def test_merge_fields() -> None:
    print('\nmerge_fields')
    thin = workout('strava', calories=500)
    rich = workout('garmin', calories=520,
                   gpsTrack=[{'lat': 1, 'lng': 2}],
                   heartRate={'avg': 150, 'samples': [{'timestamp': 't', 'bpm': 150}]})

    updates = dd.merge_fields(thin, rich)
    check('a gap is filled from the richer source', updates.get('gpsTrack') is not None)
    check('a richer source overwrites an existing scalar', updates.get('calories') == 520)
    check('nested heart-rate data is merged', updates['heartRate']['avg'] == 150)

    # Now the other direction: the thin source must not clobber the rich one.
    updates = dd.merge_fields(rich, thin)
    check('a poorer source does not overwrite', 'calories' not in updates)
    check('a poorer source does not remove a GPS track', 'gpsTrack' not in updates)

    thin_no_cals = workout('strava')
    with_cals = workout('apple_health', calories=400)
    updates = dd.merge_fields(thin_no_cals, with_cals)
    check('a poorer source still fills an empty field', updates.get('calories') == 400)

    check('an empty incoming value is ignored',
          'gpsTrack' not in dd.merge_fields(rich, workout('garmin', gpsTrack=[])))


def test_plan_upserts() -> None:
    print('\nplan_upserts — the four-sources scenario')
    # A morning run, as each path would report it.
    existing = [workout('strava', calories=500)]
    incoming = [
        workout('garmin', '2026-03-28T08:00:10+00:00', 59,
                gpsTrack=[{'lat': 1, 'lng': 2}], calories=520),
        workout('apple_health', '2026-03-28T08:00:00+00:00', 60),
        workout('fit_file', '2026-03-28T08:00:05+00:00', 60,
                heartRate={'avg': 152, 'samples': [{'timestamp': 't', 'bpm': 152}]}),
    ]
    actions = dd.plan_upserts(incoming, existing)
    check('every later arrival merges rather than inserting',
          all(a['action'] == 'merge' for a in actions),
          str([a['action'] for a in actions]))
    check('they all merge into the row that was already there',
          {a['canonicalId'] for a in actions} == {existing[0]['id']})
    check('the GPS track is promoted onto the canonical row',
          existing[0].get('gpsTrack') is not None)
    check('the richest source wins on calories', existing[0].get('calories') == 520)
    check('HR samples arrive from the fit file',
          bool((existing[0].get('heartRate') or {}).get('samples')))

    print('\nplan_upserts — other cases')
    actions = dd.plan_upserts([workout('garmin', '2026-03-28T14:00:00+00:00')], existing)
    check('an unrelated workout is inserted', actions[0]['action'] == 'insert')

    same = workout('strava', calories=500)
    actions = dd.plan_upserts([same], [same])
    check('re-importing the identical row is a plain insert (idempotent upsert)',
          actions[0]['action'] == 'insert')

    # Two copies of one activity inside a single batch must not race.
    actions = dd.plan_upserts(
        [workout('garmin'), workout('strava', '2026-03-28T08:00:20+00:00')], [])
    check('a batch containing a duplicate collapses it',
          [a['action'] for a in actions] == ['insert', 'merge'],
          str([a['action'] for a in actions]))

    check('an empty batch is a no-op', dd.plan_upserts([], existing) == [])

    print('\nplan_upserts — identity is preserved')
    canonical_before = existing[0]['id']
    dd.plan_upserts([workout('fit_file', calories=999)], existing)
    check('the canonical id never changes', existing[0]['id'] == canonical_before)
    check('the canonical source never changes', existing[0]['source'] == 'strava')


if __name__ == '__main__':
    test_dedupe_key()
    test_same_activity()
    test_source_rank()
    test_merge_fields()
    test_plan_upserts()

    if _failures:
        print(f'\n{len(_failures)} dedup test(s) failed.')
        sys.exit(1)
    print('\nAll workout dedup tests passed.')
