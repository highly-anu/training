#!/usr/bin/env python
"""Guard the profile blob against partial-write data loss.

The profile is one JSONB blob shared by clients that know different subsets of
its keys — iOS's UserProfile struct has no activeGoalId, the web app has no
performanceLogs. PUT /api/profile used to rebuild the blob from the request
body, so whichever client saved last silently nulled the keys it didn't know
about. These tests pin the merge that fixed it, and the auto-import settings
that depend on it.

Run: .venv/bin/python test_profile_merge.py
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

os.environ['SUPABASE_URL'] = ''
os.environ['DATABASE_URL'] = ''

sys.path.insert(0, str(Path(__file__).parent))

import api  # noqa: E402
from src import db  # noqa: E402

USER = '_test_profile_merge_user'

_failures: list[str] = []


def check(label: str, condition: bool, detail: str = '') -> None:
    if condition:
        print(f'  ok   {label}')
    else:
        print(f'  FAIL {label}' + (f' — {detail}' if detail else ''))
        _failures.append(label)


# Call the *undecorated* handlers: @require_auth bypasses to 'local-dev-user'
# when SUPABASE_URL is empty, which would overwrite the g.user_id set here and
# scribble over the developer's own local profile.
_update_profile = api.update_profile.__wrapped__
_get_profile = api.get_profile.__wrapped__


def put(body: dict):
    with api.app.test_request_context('/api/profile', method='PUT', json=body):
        from flask import g
        g.user_id = USER
        return _update_profile()


def get() -> dict:
    with api.app.test_request_context('/api/profile'):
        from flask import g
        g.user_id = USER
        return json.loads(_get_profile().get_data(as_text=True))


def reset() -> None:
    path = db._get_profile_path(USER)
    if path.exists():
        path.unlink()


def test_merge() -> None:
    print('\nProfile merge')
    reset()

    put({'trainingLevel': 'advanced', 'equipment': ['barbell'],
         'activeGoalId': 'goal-42', 'hrConfig': {'maxHROverride': 190}})
    check('a full save round-trips', get()['activeGoalId'] == 'goal-42')

    # Exactly the shape ios/TrainingCompanion/AppModels.swift UserProfile encodes.
    put({'trainingLevel': 'advanced', 'equipment': ['barbell'], 'injuryFlags': [],
         'customInjuryFlags': [], 'dateOfBirth': None, 'weeklySchedule': None,
         'hrConfig': {'maxHROverride': 190}})
    p = get()
    check('an iOS-shaped save preserves activeGoalId', p['activeGoalId'] == 'goal-42',
          repr(p['activeGoalId']))
    check('...and preserves hrConfig', p['hrConfig'] == {'maxHROverride': 190})

    # An explicit null is a deliberate clear, and must still work.
    put({'activeGoalId': None})
    check('an explicit null still clears the key', get()['activeGoalId'] is None)

    put({'trainingLevel': None, 'equipment': None})
    p = get()
    check('null trainingLevel falls back to intermediate', p['trainingLevel'] == 'intermediate')
    check('null equipment falls back to []', p['equipment'] == [])


def test_integrations() -> None:
    print('\nAuto-import settings')
    reset()

    p = get()
    ints = p['integrations']
    check('defaults to auto-import on', ints['autoImport'] is True)
    check('every source is present',
          set(ints['sources']) == set(api.INTEGRATION_SOURCES), str(list(ints['sources'])))
    check('every source defaults on',
          all(v['enabled'] for v in ints['sources'].values()))

    # A client that only knows about Garmin must not erase the other sources.
    put({'integrations': {'autoImport': False, 'sources': {'garmin': {'enabled': False}}}})
    ints = get()['integrations']
    check('master switch persists', ints['autoImport'] is False)
    check('named source persists', ints['sources']['garmin']['enabled'] is False)
    check('unnamed sources are filled back in',
          ints['sources']['strava']['enabled'] is True)

    check('a disabled master blocks every source',
          api.integration_allows(USER, 'strava') is False)

    put({'integrations': {'autoImport': True, 'sources': {'garmin': {'enabled': False},
                                                          'strava': {'enabled': True}}}})
    check('master on + source off blocks that source',
          api.integration_allows(USER, 'garmin') is False)
    check('master on + source on allows it',
          api.integration_allows(USER, 'strava') is True)
    check('an unknown source is never allowed',
          api.integration_allows(USER, 'nonsense') is False)

    # Settings must not be collateral damage of an unrelated save.
    put({'trainingLevel': 'beginner'})
    ints = get()['integrations']
    check('an unrelated save leaves settings alone',
          ints['sources']['garmin']['enabled'] is False)

    # Garbage in the stored blob must not crash the readers.
    put({'integrations': 'not-an-object'})
    check('a malformed stored value falls back to defaults',
          get()['integrations']['autoImport'] is True)


if __name__ == '__main__':
    try:
        test_merge()
        test_integrations()
    finally:
        reset()

    if _failures:
        print(f'\n{len(_failures)} profile test(s) failed.')
        sys.exit(1)
    print('\nAll profile merge tests passed.')
