#!/usr/bin/env python
"""Unit tests for src/source_weeks.py: a source week against hand-built
programs, no generation (tools/evaluate_packages.py generates; S5 grades).

Run: .venv/bin/python test_source_weeks.py
"""
from __future__ import annotations

import sys

from src import package_eval as pe, source_weeks as sw

FAILURES: list[str] = []


def check(label: str, condition: bool, detail: str = '') -> None:
    if condition:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label} {detail}")
        FAILURES.append(label)


def ex(eid, **load):
    return {'exercise': {'id': eid}, 'load': load}


def s(aid, *rows, modality='max_strength', **kw):
    return {'archetype': {'id': aid}, 'modality': modality, 'exercises': list(rows), **kw}


def week(days: dict):
    return {'schedule': {d: (v if isinstance(v, list) else [v]) for d, v in days.items()}}


A = s('a', ex('squat', sets=3, reps=5, weight_kg=65), ex('press', sets=3, reps=5))
B = s('b', ex('squat', sets=3, reps=5, weight_kg=70), ex('bench', sets=3, reps=5))
PROGRAM = {'weeks': [week({1: A, 3: B, 5: A})]}


def entry(**kw):
    return {'id': 'e', 'rule': 'R1', 'track': 't', 'profile': {}, **kw}


def test_weeks() -> None:
    print('weeks')
    want_a = {'archetype': 'a', 'exercises': [{'id': 'squat', 'sets': 3, 'reps': 5}, 'press']}
    want_b = {'archetype': 'b', 'exercises': ['squat', 'bench']}
    st, nu = sw.compare(PROGRAM, entry(weeks=[{'days': [want_a, want_b, want_a]}]))
    check('the source week reproduces', not st and not nu, str(st + nu))
    st, nu = sw.compare(PROGRAM, entry(weeks=[{'days': [{'archetype': 'a'}, {'archetype': 'b'}]}]))
    check('a day too many is structure', any('3 training days' in x for x in st), str(st))
    changed = {'archetype': 'a', 'exercises': [{'id': 'squat', 'sets': 5, 'reps': 5}, 'press']}
    st, nu = sw.compare(PROGRAM, entry(weeks=[{'days': [changed, want_b, want_a]}]))
    check('a changed set count is a number, not structure', not st and any('sets 3' in x for x in nu), str(st + nu))
    st, _ = sw.compare(PROGRAM, entry(weeks=[{'days': [{'exercises': ['squat']}, want_b, want_a]}]))
    check('a missing exercise is structure', any('exercises' in x for x in st), str(st))
    st, nu = sw.compare(PROGRAM, entry(weeks=[{'days': [{'archetype': 'a'}, {'archetype': 'b'}, {'archetype': 'a'}]}]))
    check('fields the source leaves out are never compared', not st and not nu)
    positional = [want_a, 'rest', want_b, 'rest', want_a, 'rest', 'rest']
    st, _ = sw.compare(PROGRAM, entry(weeks=[{'days': positional}]))
    check('a week with rest days is compared day by day', not st, str(st))
    shifted = ['rest', want_a, want_b, 'rest', want_a, 'rest', 'rest']
    st, _ = sw.compare(PROGRAM, entry(weeks=[{'days': shifted}]))
    check('…so a session on a day the source rests is structure', st, str(st))
    st, nu = sw.compare(PROGRAM, entry(weeks=[{'days': [{'includes': [{'id': 'press', 'reps': 5}]}, want_b, want_a]}]))
    check('includes names some of a session, in any order', not st and not nu, str(st + nu))
    st, _ = sw.compare(PROGRAM, entry(weeks=[{'modalities': {'max_strength': 3}}]))
    check('a week counted by modality', not st, str(st))
    st, _ = sw.compare(PROGRAM, entry(weeks=[{'modalities': {'max_strength': 2, 'combat_sport': 1}}]))
    check('…and a count that differs is structure', len(st) == 2, str(st))
    st, _ = sw.compare({'weeks': [], 'validation_errors': ['x']}, entry(weeks=[{'days': []}]))
    check('a refused profile is structure', st and 'refused' in st[0])


def test_series_and_plates() -> None:
    print('series and plates')
    st, nu = sw.compare(PROGRAM, entry(series=[{'exercise': 'squat', 'field': 'weight_kg', 'values': [65, 70, 65]}]))
    check('a series over successive sessions', not st and not nu, str(st + nu))
    st, nu = sw.compare(PROGRAM, entry(series=[{'exercise': 'squat', 'field': 'weight_kg', 'values': [65, 72]}]))
    check('a series that differs is a number', not st and nu, str(st + nu))
    st, _ = sw.compare(PROGRAM, entry(series=[{'exercise': 'squat', 'field': 'weight_kg', 'values': [65] * 4}]))
    check('a series longer than the sessions is structure', st, str(st))
    st, nu = sw.compare(PROGRAM, entry(round_kg=2.5,
                                       series=[{'exercise': 'squat', 'field': 'weight_kg', 'values': [64, 69, 64]}]))
    check("a source's kilograms on the contract's plates", not st and not nu, str(st + nu))
    check('to the nearest plate', sw._expected('weight_kg', 72, 1.25) == 72.5)
    from src.training_contract import _round_kg
    check('a tie rounds as the contract loads it', sw._expected('weight_kg', 70.625, 1.25) == _round_kg(70.625, 1.25))
    check('reps are never rounded', sw._expected('reps', 7, 5) == 7)


def test_grade() -> None:
    print('the grade')
    check('every week reproduced passes S5', pe.grade_s5(2, [], [], 0)[0] == pe.PASS)
    check('numbers alone are partial', pe.grade_s5(2, [], ['x'], 3)[0] == pe.PARTIAL)
    check('structure fails', pe.grade_s5(2, ['x'], [], 3)[0] == pe.FAIL)
    check('no source week, a source test CI runs: partial', pe.grade_s5(0, [], [], 1)[0] == pe.PARTIAL)
    check('neither fails', pe.grade_s5(0, [], [], 0)[0] == pe.FAIL)
    check('a track that is an invention has no source to reproduce', pe.grade_s5(0, [], [], 0, 'I1')[0] == pe.PASS)
    check('an entry for a track the package lacks is structure, not an exception',
          sw.check_entry('x', {'id': 'e', 'track': 'nope'}, {'t'})[0])
    st, _ = sw.check_entry('no_such_package', {'id': 'e', 'track': 't', 'profile': {}}, {'t'})
    check('an entry that cannot generate is structure, not an exception', st and 'does not generate' in st[0], str(st))
    weekly = {'weeks': [week({1: A}), week({1: B})]}
    st, nu = sw.compare(weekly, entry(from_week=2, series=[{'exercise': 'squat', 'field': 'weight_kg', 'values': [70]}]))
    check('a series starts at the week the entry does', not st and not nu, str(st + nu))


def main() -> int:
    for t in (test_weeks, test_series_and_plates, test_grade):
        t()
    print()
    if FAILURES:
        print(f"{len(FAILURES)} failure(s)")
        return 1
    print('source weeks pinned')
    return 0


if __name__ == '__main__':
    sys.exit(main())
