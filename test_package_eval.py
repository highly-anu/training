#!/usr/bin/env python
"""Unit tests for src/package_eval.py: each scorecard grader on hand-built
programs and files, no generation (tools/evaluate_packages.py runs them over
generated ones).

Run: .venv/bin/python test_package_eval.py
"""
from __future__ import annotations

import sys
from types import SimpleNamespace

from src import package_eval as pe, package_fidelity as pf

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
    gapped = program([s(rows=[ex(), empty()]), s()])
    check('a session with one slot of two empty is partial E1', pe.grade_e1({'ideal': gapped})[0] == pe.PARTIAL)
    check('the volume bands are claims', {'volume_ramp', 'volume_vs_previous_phase'} <= pe.CLAIM_RULES)
    some = program([s(substituted_for='x'), s(), s(), s(), s()])
    most = program([s(substituted_for='x'), s(substituted_for='x'), s()])
    check('a fifth substituted is partial', pe.grade_e2({'ideal': some})[0] == pe.PARTIAL)
    check('two thirds substituted fails', pe.grade_e2({'ideal': most})[0] == pe.FAIL)
    check('a level served that the track is not written for fails E3',
          pe.grade_e3({'elite': False, 'advanced': True})[0] == pe.FAIL)
    check('refused levels pass E3', pe.grade_e3({'elite': True})[0] == pe.PASS)
    archs = [{'id': a, 'modality': 'max_strength'} for a in ('lp', 'lp_b', 'lp_c')]
    same = program([s(), s()], [s(), s()])
    found = pe.concentration(same, TRACK, archs, 'novice', set(), set())
    check('one archetype for four sessions fails E4', pe.grade_e4(found)[0] == pe.FAIL)
    check('one template on offer concentrates too',
          pe.grade_e4(pe.concentration(same, TRACK, archs[:1], 'novice', set(), set()))[0] == pe.FAIL)
    capped = {**TRACK, 'phases': [{'id': 'p1', 'checks': {'max_archetype_share': 1.0}}]}
    cited = {'checks:t/p1.max_archetype_share'}
    check("the phase's own cap, cited by a rule, is the method's word",
          pe.grade_e4(pe.concentration(same, capped, archs, 'novice', set(), cited))[0] == pe.PASS)
    check('a cap no rule cites is a number, not the method: E4 still fails',
          pe.grade_e4(pe.concentration(same, capped, archs, 'novice', set(), set()))[0] == pe.FAIL)
    check('alternating two is partial',
          pe.grade_e4(pe.concentration(program([s(), s(aid='lp_b')], [s(), s(aid='lp_b')]),
                                       TRACK, archs, 'novice', set(), set()))[0] == pe.PARTIAL)
    check('a contract program is exempt',
          not pe.concentration({**same, 'training_contract': {'id': 'c'}}, TRACK, archs, 'novice', set(), set()))
    check('no claim declared is partial', pe.grade_e5(False, [])[0] == pe.PARTIAL)
    check('a contract a rule cites declares its claims',
          pe.declares_claims(TRACK, {'modules': []}, {'data:training_contract.yaml#tracks.t.modules'}))
    check('a contract no rule cites declares nothing', not pe.declares_claims(TRACK, {'modules': []}, set()))
    claimed = {**TRACK, 'phases': [{'id': 'p1', 'checks': {'max_zone': 5}}]}
    check('an uncited claim key declares nothing', not pe.declares_claims(claimed, None, set()))
    check('a cited claim key declares the phase', pe.declares_claims(claimed, None, {'checks:t/p1.max_zone'}))
    check("another track's citation is not this one's (t is not t_b)",
          not pe.declares_claims(TRACK, {'modules': []}, {'data:training_contract.yaml#tracks.t_b.modules'}))
    check('the track itself counts', pe.declares_claims(TRACK, {'modules': []}, {'data:training_contract.yaml#tracks.t'}))
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
          pe.grade_m1('bar_load', 'attendance', 'R5')[0] == pe.FAIL)
    check('no currency declared fails M1', pe.grade_m1(None, 'bar_load', None)[0] == pe.FAIL)
    check('a currency no rule supports fails M1', pe.grade_m1('bar_load', 'bar_load', None)[0] == pe.FAIL)
    check('the cited currency leading passes M1', pe.grade_m1('bar_load', 'bar_load', 'R5')[0] == pe.PASS)
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


def _record(**kw) -> dict:
    rec = {'shape': 'contract',
           'sources': [{'id': 'book', 'kind': 'primary', 'title': 'T', 'where': 'w', 'read': 'full'}],
           'rules': [{'id': 'R1', 'text': 'Three days a week.', 'cites': [{'source': 'book'}],
                      'enforced_by': ['data:philosophy.yaml#id']}],
           'inventions': [{'id': 'I1', 'text': 'A track.'}]}
    rec.update(kw)
    return rec


def test_source_and_status() -> None:
    print('source and status')
    rec = _record()
    check('a record with sources and rules, and a dossier, passes S1', pe.grade_s1(rec, True)[0] == pe.PASS)
    check('headings without a record fail S1', pe.grade_s1(None, True)[0] == pe.FAIL)
    check('a record with no rules fails S1', pe.grade_s1(_record(rules=[]), True)[0] == pe.FAIL)
    check('a primary source read in full passes S2', pe.grade_s2(pf.sources_kind(rec), rec)[0] == pe.PASS)
    unread = _record(sources=[{**rec['sources'][0], 'read': 'not_read'}])
    check('"primary" is not a word in a file: a primary source not read is no source',
          pe.grade_s2(pf.sources_kind(unread), unread)[0] == pe.FAIL)
    three = _record(sources=[{'id': f's{i}', 'kind': 'secondary', 'title': 't', 'where': 'w', 'read': 'partial'}
                             for i in range(3)])
    check('three secondary sources read are a consensus', pf.sources_kind(three) == 'consensus')
    two = _record(sources=three['sources'][:2])
    check('two are partial S2', pe.grade_s2(pf.sources_kind(two), two)[0] == pe.PARTIAL)
    debt = _record(rules=rec['rules'] + [{'id': 'R2', 'text': 'Repeat after a layoff.', 'cites': [{'source': 'book'}]}])
    check('debt is computed: a rule nothing enforces', pf.debt(debt) == ['R2'])
    check('debt is partial S3', pe.grade_s3(debt, pf.debt(debt), [])[0] == pe.PARTIAL)
    check('enforcement that names nothing fails S3', pe.grade_s3(rec, [], ['R1: no x'])[0] == pe.FAIL)
    stub = {'shape': 'scheduler'}
    check('a record with no rules has no debt, and fails S3 and S4 all the same',
          pe.grade_s3(stub, pf.debt(stub), [])[0] == pe.FAIL and pe.grade_s4(stub, [])[0] == pe.FAIL)
    check('a rule resting on an unread source fails S4',
          any('rests on no source' in e for e in pf.citation_errors('x', unread, None)))
    excluded = _record(excluded_tracks={'t': 'I9'})
    check('an excluded track must be an invention',
          any('I9' in e for e in pf.citation_errors('x', excluded, None)))
    check('the dossier names every rule and invention',
          pf.citation_errors('x', rec, 'R1 and I1') == [] and
          any('never names I1' in e for e in pf.citation_errors('x', rec, 'R1 only')))
    check('a clean record passes S4', pe.grade_s4(rec, pf.citation_errors('x', rec, 'R1, I1'))[0] == pe.PASS)
    check('no record fails S4', pe.grade_s4(None, [])[0] == pe.FAIL)
    check('a data reference resolves through list ids and slot roles',
          pf._walk({'slots': [{'role': 'rope', 'f': {'ordered': True}}]}, 'slots.rope.f.ordered')[1] is None)
    check('a reference to a missing key names the step',
          pf._walk({'tracks': [{'id': 'a'}]}, 'tracks.b.modules')[1] == 'b')
    check('a manual standard counts only when a rule cites it',
          pf.manual_cited(_record(rules=[{**rec['rules'][0], 'enforced_by': ['data:analytics.yaml#benchmarks.ssst']}]),
                          'ssst') and not pf.manual_cited(rec, 'ssst'))
    invented = _record(inventions=[{'id': 'I1', 'text': 'x', 'implemented_by': ['data:training_contract.yaml#tracks.t']},
                                   {'id': 'I2', 'text': 'y', 'implemented_by': ['data:training_contract.yaml#tracks.u.modules']}],
                       currency={'t': {'entry': 'm', 'rule': 'I1'}, 'u': {'entry': 'm', 'rule': 'I2'}})
    check('an invented track is the invention that names the whole track',
          pf.invented_track(invented, 't') == 'I1' and pf.invented_track(invented, 'u') is None)
    check("an invention is the currency's rule only on the track it is",
          pf.currency(invented, 't') == ('m', 'I1') and pf.currency(invented, 'u') == ('m', None))
    inv = _record(inventions=[{'id': 'I1', 'text': 'x', 'implemented_by': ['data:training_contract.yaml#tracks.t']}])
    check("an invention's implementation declares its track's claims, as the owner's word",
          pe.declares_claims(TRACK, {'modules': []}, pf.refs(inv)))
    check("an invention's tests are not source tests",
          pf.source_tests(_record(inventions=[{'id': 'I1', 'text': 'x', 'implemented_by': ['test:a.py::t']}])) == [])
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
