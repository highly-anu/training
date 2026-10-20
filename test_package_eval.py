#!/usr/bin/env python
"""Unit tests for src/package_eval.py: each scorecard grader on hand-built
programs and files, no generation (tools/evaluate_packages.py runs them over
generated ones).

Run: .venv/bin/python test_package_eval.py
"""
from __future__ import annotations

import sys
from types import SimpleNamespace

from src import package_eval as pe

FAILURES: list[str] = []


def check(label: str, condition: bool, detail: str = '') -> None:
    if condition:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label} {detail}")
        FAILURES.append(label)


def ex(eid='squat'):
    return {'exercise': {'id': eid}, 'slot_role': 'main', 'load': {}}


def empty():
    return {'exercise': None, 'slot_role': 'main', 'equipment_gap': True}


def s(modality='max_strength', aid='lp', rows=None, **kw):
    return {'modality': modality, 'archetype': {'id': aid}, 'exercises': rows or [ex()], **kw}


def program(*weeks):
    return {'weeks': [{'week_number': i + 1, 'phase_id': 'p1', 'phase': 'build', 'is_deload': False,
                       'schedule': {d + 1: [sess] for d, sess in enumerate(w)}}
                      for i, w in enumerate(weeks)]}


TRACK = {'id': 't', 'phases': [{'id': 'p1', 'framework_id': 'fw'}]}


def test_execution() -> None:
    print('execution')
    good = program([s(), s(aid='lp_b')])
    hollow = program([s(rows=[empty(), empty()]), s()])
    check('a delivered session with every slot empty fails E1', pe.grade_e1({'ideal': hollow})[0] == pe.FAIL)
    check('meta-only rows are not an empty session',
          pe.grade_e1({'ideal': program([s(rows=[{'meta': True}])])})[0] == pe.PASS)
    check('no empties passes E1', pe.grade_e1({'ideal': good})[0] == pe.PASS)
    some = program([s(substituted_for='x'), s(), s(), s(), s()])
    most = program([s(substituted_for='x'), s(substituted_for='x'), s()])
    check('a fifth substituted is partial', pe.grade_e2({'ideal': some})[0] == pe.PARTIAL)
    check('two thirds substituted fails', pe.grade_e2({'ideal': most})[0] == pe.FAIL)
    check('a level served that the track is not written for fails E3',
          pe.grade_e3({'elite': False, 'advanced': True})[0] == pe.FAIL)
    check('refused levels pass E3', pe.grade_e3({'elite': True})[0] == pe.PASS)
    archs = [{'id': a, 'modality': 'max_strength'} for a in ('lp', 'lp_b', 'lp_c')]
    same = program([s(), s()], [s(), s()])
    found = pe.concentration(same, TRACK, archs, 'novice', set())
    check('one archetype for four sessions fails E4', pe.grade_e4(found)[0] == pe.FAIL)
    check('one template on offer concentrates too',
          pe.grade_e4(pe.concentration(same, TRACK, archs[:1], 'novice', set()))[0] == pe.FAIL)
    capped = {**TRACK, 'phases': [{'id': 'p1', 'checks': {'max_archetype_share': 1.0}}]}
    check("the phase's own cap is the method's word",
          pe.grade_e4(pe.concentration(same, capped, archs, 'novice', set()))[0] == pe.PASS)
    check('alternating two is partial',
          pe.grade_e4(pe.concentration(program([s(), s(aid='lp_b')], [s(), s(aid='lp_b')]),
                                       TRACK, archs, 'novice', set()))[0] == pe.PARTIAL)
    check('a contract program is exempt',
          not pe.concentration({**same, 'training_contract': {'id': 'c'}}, TRACK, archs, 'novice', set()))
    check('no claim declared is partial', pe.grade_e5(False, [])[0] == pe.PARTIAL)
    check('a contract declares its claims', pe.declares_claims(TRACK, {'modules': []}))
    check('a broken claim fails', pe.grade_e5(True, ['p1: x'])[0] == pe.FAIL)
    check('warnings only are partial E6', pe.grade_e6([{'severity': 'warn', 'rule': 'r'}])[0] == pe.PARTIAL)
    check('levels from the frameworks', pe.written_levels(
        TRACK, {'fw': {'applicable_when': {'training_level': ['novice']}}}, None) == {'novice'})


def test_robustness() -> None:
    print('robustness')
    no = SimpleNamespace(feasible=False)
    yes = SimpleNamespace(feasible=True)
    check('refused, and lifting one constraint unblocks it',
          pe.robustness_outcome(None, no, TRACK, True)[0] == pe.PASS)
    check('refused with no way out is partial',
          pe.robustness_outcome(None, no, TRACK, False)[0] == pe.PARTIAL)
    check('served hollow is degraded',
          pe.robustness_outcome(program([s(rows=[empty()])]), yes, TRACK, None)[0] == pe.FAIL)
    check('served as written passes', pe.robustness_outcome(program([s()]), yes, TRACK, None)[0] == pe.PASS)
    outcomes = {'a': (pe.PASS, ''), 'b': (pe.FAIL, 'hollow')}
    check('R1 is the worst profile', pe.grade_r1(outcomes) == (pe.FAIL, 'b: hollow'))


def test_data_and_measurement() -> None:
    print('data and measurement')
    check('media under half fails D3', pe.grade_d3(4, 10)[0] == pe.FAIL)
    check('media at ninety per cent passes D3', pe.grade_d3(9, 10)[0] == pe.PASS)
    check('inert scaling is partial D4', pe.grade_d4(0, 0, 2)[0] == pe.PARTIAL)
    check('orphans are partial D2', pe.grade_d2(['x'])[0] == pe.PARTIAL)
    check('a lead other than the declared currency fails M1',
          pe.grade_m1('bar_load', 'attendance')[0] == pe.FAIL)
    check('no currency declared fails M1', pe.grade_m1(None, 'bar_load')[0] == pe.FAIL)
    prims = {'set_load': {'needs': ['sets']}, 'load_at_rpe': {'needs': ['sets', 'rpe', 'rpe_target']},
             'zone_minutes': {'needs': ['hr']}}
    cap = {'sets': 'logged', 'rpe': 'optional', 'rpe_target': 'program', 'hr': 'device'}
    check('a logged lead passes M2', pe.grade_m2('set_load', prims, cap)[0] == pe.PASS)
    check('an optional field is partial M2', pe.grade_m2('load_at_rpe', prims, cap)[0] == pe.PARTIAL)
    check('a watch-only lead is partial M2', pe.grade_m2('zone_minutes', prims, cap)[0] == pe.PARTIAL)
    check('a standard nothing measures is partial M3',
          pe.grade_m3(['a', 'b'], {'a'}, set(), set())[0] == pe.PARTIAL)
    check('manual counts for M3', pe.grade_m3(['a', 'b'], {'a'}, set(), {'b'})[0] == pe.PASS)
    check('an unknown standard fails M4', pe.grade_m4({'a', 'z'}, {'a'})[0] == pe.FAIL)


def test_source_and_status() -> None:
    print('source and status')
    text = ('# X\n\n## Sources\n\n- a\n- b\n- c\n\n## Rules → where they live\n\n| r |\n\n'
            '## Open\n\n- o\n\n## Inventions (see status.yaml)\n\n- one\n\n## Tests\n\nt\n')
    sections = pe.dossier_sections(text)
    check('every section found', pe.grade_s1(sections)[0] == pe.PASS)
    check('a missing section fails S1', pe.grade_s1(pe.dossier_sections('## Sources\n'))[0] == pe.FAIL)
    check('a consensus of three passes S2', pe.grade_s2('consensus', sections)[0] == pe.PASS)
    check('secondary sources are partial', pe.grade_s2('secondary', sections)[0] == pe.PARTIAL)
    check('inventions counted alike pass S4', pe.grade_s4(['one'], sections)[0] == pe.PASS)
    check('inventions that differ fail S4', pe.grade_s4(['one', 'two'], sections)[0] == pe.FAIL)
    check('unstated debt is partial', pe.grade_s3(None)[0] == pe.PARTIAL)
    passing = {c: (pe.PASS, '') for crits in pe.DIMENSIONS.values() for c in crits}
    hygiene = {**passing, 'D3': (pe.FAIL, 'no media')}
    check('hygiene never blocks audited', pe.derived_status({'t': hygiene}, set(), True) == 'audited')
    check('hygiene never sets a dimension', pe.dimension_grades(hygiene)['data'] == pe.PASS)
    failing = {**passing, 'E2': (pe.PARTIAL, '')}
    check('a partial criterion keeps it partial', pe.derived_status({'t': failing}, set(), True) == 'partial')
    check('an excluded track does not count',
          pe.derived_status({'t': passing, 'x': failing}, {'x'}, True) == 'audited')
    check('no dossier is not started', pe.derived_status({'t': passing}, set(), False) == 'not_started')


def main() -> int:
    for t in (test_execution, test_robustness, test_data_and_measurement, test_source_and_status):
        t()
    print()
    if FAILURES:
        print(f"{len(FAILURES)} failure(s)")
        return 1
    print('every scorecard grader pinned')
    return 0


if __name__ == '__main__':
    sys.exit(main())
