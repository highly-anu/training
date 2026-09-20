#!/usr/bin/env python
"""Assert the Python matcher against the shared golden fixtures.

The same fixtures (data/matcher_fixtures.json) are asserted by the TypeScript
matcher in frontend/src/lib/workoutMatcher.test.ts. Both read their thresholds
from data/matching_rules.json. If this passes and the vitest suite fails (or
vice versa) the two implementations have drifted — that is exactly what these
fixtures exist to catch.

Run: .venv/bin/python test_workout_matcher.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from src import workout_matcher as wm

FIXTURES = json.loads((Path(__file__).parent / 'data' / 'matcher_fixtures.json').read_text())

_failures: list[str] = []


def check(label: str, condition: bool, detail: str = '') -> None:
    if condition:
        print(f'  ok   {label}')
    else:
        print(f'  FAIL {label}' + (f' — {detail}' if detail else ''))
        _failures.append(label)


def test_score_cases() -> None:
    print('\nscore_match (shared fixtures)')
    for case in FIXTURES['scoreCases']:
        got = wm.score_match(case['workout'], case['sessionModality'], case['sessionDuration'])
        check(case['name'], got == case['expectedScore'],
              f"expected {case['expectedScore']}, got {got}")


def test_match_cases() -> None:
    print('\nauto_match (shared fixtures)')
    for case in FIXTURES['matchCases']:
        got = wm.auto_match(case['workouts'], case['program'],
                            case['programStartDate'], case['existingMatches'])
        exp = case['expected']

        got_confirmed = [(m['importedWorkoutId'], m['sessionKey']) for m in got['confirmed']]
        exp_confirmed = [(m['importedWorkoutId'], m['sessionKey']) for m in exp['confirmed']]
        check(f"{case['name']} — confirmed", got_confirmed == exp_confirmed,
              f'expected {exp_confirmed}, got {got_confirmed}')

        got_sugg = [(s['importedWorkoutId'], s['sessionKey'], s['score']) for s in got['suggested']]
        exp_sugg = [(s['importedWorkoutId'], s['sessionKey'], s['score']) for s in exp['suggested']]
        check(f"{case['name']} — suggested", got_sugg == exp_sugg,
              f'expected {exp_sugg}, got {got_sugg}')

        for m in got['confirmed']:
            check(f"{case['name']} — confidence is 'auto'", m['matchConfidence'] == 'auto')


def test_calendar_dates() -> None:
    print('\nsession_calendar_date')
    check('week 0 Monday is the start date',
          wm.session_calendar_date('2026-03-02', 0, 'Monday') == '2026-03-02')
    check('week 0 Sunday is start + 6',
          wm.session_calendar_date('2026-03-02', 0, 'Sunday') == '2026-03-08')
    check('week 1 Monday is start + 7',
          wm.session_calendar_date('2026-03-02', 1, 'Monday') == '2026-03-09')
    check('an unknown day name yields nothing',
          wm.session_calendar_date('2026-03-02', 0, 'Caturday') == '')
    check('a malformed start date yields nothing',
          wm.session_calendar_date('not-a-date', 0, 'Monday') == '')
    check('an ISO datetime start is tolerated',
          wm.session_calendar_date('2026-03-02T00:00:00Z', 0, 'Monday') == '2026-03-02')


def test_key_spelling_tolerance() -> None:
    """iOS has written camelCase into user_programs; the TS reads snake_case
    only, so this tolerance is Python-side and deliberately not in the shared
    fixtures."""
    print('\ncamelCase program tolerance (Python-only)')
    program = {
        'weeks': [{
            'weekNumber': 3,
            'schedule': {
                'Monday': [{'modality': 'aerobic_base',
                            'archetype': {'durationEstimateMinutes': 60}}],
            },
        }],
    }
    workouts = [{'id': 'w1', 'date': '2026-03-02',
                 'inferredModalityId': 'aerobic_base', 'durationMinutes': 60}]
    out = wm.auto_match(workouts, program, '2026-03-02', [])
    check('camelCase weekNumber is read', bool(out['confirmed']))
    if out['confirmed']:
        check('session key uses the camelCase week number',
              out['confirmed'][0]['sessionKey'] == '3-Monday-0',
              out['confirmed'][0]['sessionKey'])

    # A week with no number at all falls back to its 1-based position.
    program['weeks'][0].pop('weekNumber')
    out = wm.auto_match(workouts, program, '2026-03-02', [])
    check('a week with no number falls back to its position',
          out['confirmed'] and out['confirmed'][0]['sessionKey'] == '1-Monday-0')


def test_robustness() -> None:
    print('\nrobustness')
    check('an empty program matches nothing',
          wm.auto_match([{'id': 'x', 'date': '2026-03-02'}], {'weeks': []}, '2026-03-02', [])
          == {'confirmed': [], 'suggested': []})
    check('no workouts is a no-op',
          wm.auto_match([], {'weeks': []}, '2026-03-02', [])
          == {'confirmed': [], 'suggested': []})
    check('a workout with no id is skipped',
          wm.auto_match([{'date': '2026-03-02'}], {'weeks': []}, '2026-03-02', [])
          == {'confirmed': [], 'suggested': []})
    check('an unknown modality falls into the "other" family',
          wm.modality_family('not_a_modality') == 'other')
    check('a null modality falls into the "other" family',
          wm.modality_family(None) == 'other')
    check('a non-numeric duration does not raise',
          wm.score_match({'inferredModalityId': 'aerobic_base', 'durationMinutes': 'abc'},
                         'aerobic_base', 60) == 3)


def test_rules_are_shared() -> None:
    print('\nshared rules file')
    check('rules load from data/matching_rules.json', bool(wm.RULES))
    check('auto threshold is above the suggest threshold',
          wm.RULES['autoThreshold'] > wm.RULES['suggestThreshold'])
    families = set(wm.RULES['families'])
    check('the four modality families are defined',
          families == {'strength', 'cardio', 'durability', 'skill'}, str(families))
    # Every modality appears in at most one family, or scoring is ambiguous.
    seen: set[str] = set()
    dupes = set()
    for modalities in wm.RULES['families'].values():
        for m in modalities:
            if m in seen:
                dupes.add(m)
            seen.add(m)
    check('no modality is in two families', not dupes, str(dupes))


if __name__ == '__main__':
    test_rules_are_shared()
    test_score_cases()
    test_match_cases()
    test_calendar_dates()
    test_key_spelling_tolerance()
    test_robustness()

    if _failures:
        print(f'\n{len(_failures)} matcher test(s) failed.')
        sys.exit(1)
    print('\nAll workout matcher tests passed.')
