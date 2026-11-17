"""Tests of the standards in generated programs (src/standard_tests.py,
src/generator._plan_week_tests): when a phase tests, what a test replaces, how
it is prescribed, when it is skipped, and that everything else in the program
is left as it would have been. No database. A package's own tests of its
standards are in its folder (data/packages/<id>/tests/).

    SUPABASE_URL='' .venv/bin/python test_standard_tests.py
"""
import copy
import os

os.environ.setdefault('SUPABASE_URL', '')

import fixture_packages  # noqa: E402
fixture_packages.use()

from src import goals, loader, phases, program_history, standard_tests
from src.generator import generate
from src.selector import select_archetype

FRAMEWORKS = list(loader.load_all_frameworks().values())


ALL_EQUIPMENT = ['barbell', 'rack', 'plates', 'kettlebell', 'pull_up_bar', 'open_space', 'rower',
                 'jump_rope', 'ruck_pack', 'sandbag', 'box', 'dumbbell', 'bench']


def _constraints(**over):
    c = {'days_per_week': 5, 'session_time_minutes': 75, 'training_level': 'intermediate',
         'equipment': ALL_EQUIPMENT, 'injury_flags': [], 'periodization_week': 1, 'fatigue_state': 'normal'}
    c.update(over)
    return c


def _gen(phil, track=None, weeks=4, goal=None, **over):
    goal = goal or goals.philosophy_to_goal(phil, FRAMEWORKS, track_id=track)
    if goal.get('training_contract'):
        over.setdefault('mastered_exercises', [eid for m in goal['training_contract']['modules'] for eid in m.get('requires_mastery', [])])
    return generate(goal_id=goal['id'], goal_dict=goal, constraints=_constraints(**over),
                    num_weeks=weeks, output_format='dict')


def _sessions(week):
    return [(day, i, s) for day, ss in sorted(week['schedule'].items()) for i, s in enumerate(ss)]


def _tests(week):
    return [s for _, _, s in _sessions(week) if s.get('test')]


# ── when ─────────────────────────────────────────────────────────────────────

def test_which_weeks_test():
    def fires(t, wip, weeks=4, repeatable=False):
        return standard_tests.tests_for_week({'tests': [t], 'phase_weeks': weeks, 'repeatable': repeatable,
                                              'week_in_phase': wip})
    assert [w for w in range(1, 5) if fires({'archetype': 'a', 'week': 'first'}, w)] == [1]
    assert [w for w in range(1, 5) if fires({'archetype': 'a', 'week': 'last'}, w)] == [4]
    assert [w for w in range(1, 5) if fires({'archetype': 'a', 'week': 2}, w)] == [2]
    assert [w for w in range(1, 13) if fires({'archetype': 'a', 'every': 4}, w, 12)] == [4, 8, 12]
    assert [w for w in range(1, 9) if fires({'archetype': 'a', 'every': 3, 'start': 2}, w, 8)] == [2, 5, 8]
    assert not fires({'archetype': 'a', 'week': 'last'}, 8), 'past its end, a non-repeatable phase tests no more'
    assert fires({'archetype': 'a', 'week': 'last'}, 8, repeatable=True), 'a repeatable one repeats its test points'
    rot = {'archetypes': ['c', 'f', 'h'], 'every': 4}
    turns = [fires(rot, w, 12, True)[0]['archetypes'][0] for w in (4, 8, 12, 16, 20)]
    assert turns == ['c', 'f', 'h', 'c', 'f'], f'a rotation takes turns across cycles: {turns}'
    assert fires(rot, 8, 12)[0]['archetypes'] == ['f', 'h', 'c'], 'the rest of the rotation is the fallback'
    assert fires({'archetype': 'a', 'week': 'last'}, 4)[0]['day'] == 'last'
    assert fires({'archetype': 'a', 'week': 'first'}, 1)[0]['day'] == 'first'


def test_phases_carry_the_tests():
    phil = next(p for p in loader.load_philosophies() if p['id'] == 'wildman_kettlebell')
    track = next(t for t in phases.tracks_of(phil) if t['id'] == 'pentathlon')
    seq = phases.phase_sequence_for(track)
    comp = next(e for e in seq if e['phase_id'] == 'competition')
    assert comp['tests'] == [{'archetype': 'kb_pentathlon_test', 'week': 'last'}]
    entry = phases.week_entry(comp, 2, 8)
    assert entry['tests'] and entry['phase_weeks'] == 2 and entry['repeatable'] is False
    errs = phases.validate_philosophy_tracks({'id': 'x', 'tracks': [{'id': 't', 'phases': [
        {'id': 'p', 'kind': 'base', 'weeks': 2, 'framework_id': 'f', 'tests': [{'archetype': 'a', 'week': 3}]}]}]})
    assert any('week 3 of a 2-week phase' in e for e in errs), errs


# ── what it replaces, and nothing else ───────────────────────────────────────

def test_a_test_replaces_one_session_and_nothing_else():
    goal = goals.philosophy_to_goal('wildman_kettlebell', FRAMEWORKS, track_id='pentathlon')
    with_test = _gen(None, goal=goal, weeks=2, start_phase='competition')
    bare = copy.deepcopy(goal)
    for e in bare['phase_sequence']:
        e.pop('tests', None)
    without = _gen(None, goal=bare, weeks=2, start_phase='competition')

    w1, w2 = with_test['weeks'][1], without['weeks'][1]
    tests = _tests(w1)
    assert len(tests) == 1 and tests[0]['archetype']['id'] == 'kb_pentathlon_test', 'one test in the last week'
    assert not _tests(with_test['weeks'][0]), 'and none in the first'
    t = tests[0]['test']
    assert t['standards'] == ['kb_pentathlon_clean_reps', 'kb_pentathlon_long_cycle_press_reps',
                              'kb_pentathlon_jerk_reps', 'kb_pentathlon_half_snatch_reps',
                              'kb_pentathlon_push_press_reps']
    assert t['in_place_of'] == 'strength_endurance' and t['instead_of']['archetype'] == 'kb_pentathlon_training'
    a = [(d, (s.get('archetype') or {}).get('id'), [((e.get('exercise') or {}).get('id')) for e in s['exercises']])
         for d, _, s in _sessions(w1) if not s.get('test')]
    b = [(d, (s.get('archetype') or {}).get('id'), [((e.get('exercise') or {}).get('id')) for e in s['exercises']])
         for d, i, s in _sessions(w2)
         if not (d == next(dd for dd, _, ss in _sessions(w1) if ss.get('test')) and s['modality'] == 'strength_endurance'
                 and i == next(ii for dd, ii, ss in _sessions(w1) if ss.get('test')))]
    assert a == b, 'every other session is exactly what it would have been without the test'
    assert len(_sessions(w1)) == len(_sessions(w2)), 'the week keeps its session count'


def test_a_test_is_prescribed_as_written():
    raw = _gen('block_fixture', weeks=4, start_phase='realization')
    last = raw['weeks'][3]
    assert last['is_deload'], 'the fixture deloads the last week of a block'
    test = _tests(last)[0]
    row = next(e for e in test['exercises'] if e.get('standard'))
    assert row['standard'] == {'id': 'row_2km_minutes', 'result': 'duration'}
    assert row['load']['distance_km'] == 2.0 and row['load']['test'] and row['load']['effort'] == 'max', \
        f"2000 m, unscaled by the deload: {row['load']}"
    pent = _tests(_gen('wildman_kettlebell', 'pentathlon', weeks=2, start_phase='competition')['weeks'][1])[0]
    clean = next(e for e in pent['exercises'] if e['slot_role'] == 'clean')
    assert clean['load']['duration_minutes'] == 6 and clean['load']['target_rpm'] == 20, clean['load']
    assert pent['archetype']['duration_estimate_minutes'] == 60, 'the test runs its full length'


# ── when it is skipped ───────────────────────────────────────────────────────

def test_skips_say_why_and_leave_the_week_as_scheduled():
    def skipped(raw, week):
        return [t['reason'] for t in raw['weeks'][week].get('tests_skipped') or []]
    assert skipped(_gen('block_fixture', weeks=1, start_phase='accumulation', equipment=['barbell', 'plates', 'kettlebell']), 0) \
        == ['equipment_gap'], 'no rower'
    for overrides in ({'training_level': 'novice'}, {'session_time_minutes': 40}):
        rejected = _gen('wildman_kettlebell', 'pentathlon', weeks=2, start_phase='competition', **overrides)
        assert not rejected['weeks'] and rejected.get('validation_errors'), 'a contract cannot silently lose essential event work'
    assert skipped(_gen('wildman_kettlebell', 'pentathlon', weeks=2, start_phase='competition',
                        fatigue_state='overreached'), 1) == ['overreached']


def test_a_test_exercise_stays_in_its_test():
    raw = _gen('block_fixture', weeks=16, days_per_week=4)
    outside = [(w['week_number'], s.get('archetype', {}).get('id')) for w in raw['weeks'] for _, _, s in _sessions(w)
               if not s.get('test') and any((ea.get('exercise') or {}).get('id') == 'row_2km_test'
                                            for ea in s.get('exercises', []))]
    assert not outside, f'the time trial was picked for an ordinary session: {outside}'
    lumbar = _gen('block_fixture', weeks=1, start_phase='accumulation', injury_flags=['lumbar_disc'])
    assert [t['reason'] for t in lumbar['weeks'][0].get('tests_skipped') or []] == ['injury_skip'], \
        'the row test is contraindicated with a lumbar disc (the flag id is lumbar_disc)'
    report = lumbar['coverage_report']
    assert report['skipped_tests'][0]['reason'] == 'injury_skip' and report['placed_tests'] == []


def test_a_test_that_can_never_fire_is_refused():
    phil = {'id': 'p', 'tracks': [{'id': 't', 'phases': [
        {'id': 'a', 'kind': 'base', 'weeks': 4, 'framework_id': 'f', 'tests': [{'archetype': 'x', 'every': 6}]},
        {'id': 'b', 'kind': 'base', 'weeks': 4, 'framework_id': 'f', 'repeatable': True,
         'tests': [{'archetype': 'x', 'every': 6}]}]}]}
    errors = phases.validate_philosophy_tracks(phil)
    assert any('never runs' in e and '/a:' in e for e in errors), errors
    assert not any('/b:' in e for e in errors), 'a repeatable phase reaches week 6 on its second cycle'


def test_a_tail_regenerate_tests_in_its_own_week():
    raw = _gen('wildman_kettlebell', 'pentathlon', weeks=1, start_phase='competition', periodization_week=2)
    assert len(_tests(raw['weeks'][0])) == 1, 'resuming at week 2 of the phase still tests in week 2'


def test_selection_never_picks_a_test():
    from src.standard_tests import is_test_only
    data = loader.load_all_data()
    tests = [a for a in data['archetypes'] if is_test_only(a)]
    assert tests
    for test in tests:
        archs = [a for a in data['archetypes'] if a.get('_package') == test.get('_package')]
        for i in range(10):
            a = select_archetype(test['modality'], _constraints(), 'base', False, {}, archs,
                                 recent_ids=[x['id'] for x in archs][:i % 3])
            assert not (a and is_test_only(a)), (test['id'], a and a['id'])


# ── what it carries ──────────────────────────────────────────────────────────

def test_the_program_carries_tests_and_standards():
    import api
    goal = goals.philosophy_to_goal('wildman_kettlebell', FRAMEWORKS, track_id='pentathlon')
    raw = _gen(None, goal=goal, weeks=2, start_phase='competition')

    class V:
        feasible, errors, warnings, info = True, [], [], []
    out = api._transform_program(raw, goal, _constraints(), V())
    sessions = [s for day in out['weeks'][1]['schedule'].values() for s in day]
    test = next(s for s in sessions if s.get('test'))
    assert test['test']['archetype'] == 'kb_pentathlon_test'
    assert next(e for e in test['exercises'] if e['slot_role'] == 'jerk')['standard'] == \
        {'id': 'kb_pentathlon_jerk_reps', 'result': 'reps'}, 'the standard survives the slot being stripped'
    novice = _gen(None, goal=goal, weeks=2, start_phase='competition', training_level='novice')
    out2 = api._transform_program(novice, goal, _constraints(), V())
    assert not out2['weeks'] and novice.get('validation_errors'), 'an unsupported contract level is explicitly refused'

    env = {'currentProgram': out, 'programStartDate': '2026-10-05'}
    stripped = copy.deepcopy(env)
    for w in stripped['currentProgram']['weeks']:
        for day in w['schedule'].values():
            for s in day:
                s.pop('test', None)
                for e in s['exercises']:
                    e.pop('standard', None)
    assert program_history.skeleton_hash(env) == program_history.skeleton_hash(stripped), \
        'a test adds nothing to the skeleton (its archetype id already is): no new version'
    assert program_history.richness(env) > program_history.richness(stripped), \
        'a copy that dropped the test is the poorer one'


def test_adjustments_leave_a_test_alone():
    import api
    goal = goals.philosophy_to_goal('block_fixture', FRAMEWORKS)
    raw = _gen(None, goal=goal, weeks=1, start_phase='accumulation')

    class V:
        feasible, errors, warnings, info = True, [], [], []
    weeks = api._transform_program(raw, goal, _constraints(), V())['weeks']
    row = next(e for day in weeks[0]['schedule'].values() for s in day if s.get('test')
               for e in s['exercises'] if e.get('standard'))
    before = dict(row['load'])
    api.apply_adjustment_to_weeks(weeks, 0, {'type': 'reduce_volume_10pct', 'target': 'all'}, {})
    api.apply_adjustment_to_weeks(weeks, 0, {'type': 'early_deload'}, {})
    assert row['load'] == before, f'2000 m stays 2000 m: {row["load"]}'


def test_the_phase_summary_lists_its_tests():
    from src import phase_summary
    import api
    goal = goals.philosophy_to_goal('wildman_kettlebell', FRAMEWORKS, track_id='pentathlon')

    class V:
        feasible, errors, warnings, info = True, [], [], []
    weeks = api._transform_program(_gen(None, goal=goal, weeks=2, start_phase='competition'), goal,
                                   _constraints(), V())['weeks']
    comp = phase_summary.build(weeks, goal)[0]
    assert [(t['week_number'], t['status'], t['archetype']['id']) for t in comp['tests']] == \
        [(2, 'planned', 'kb_pentathlon_test')]
    assert comp['tests'][0]['standards'][0] == {'id': 'kb_pentathlon_clean_reps',
                                                'name': 'KB Pentathlon — Clean (reps in 6 min)'}
    assert 'kb_pentathlon_test' not in {a['id'] for a in comp['archetypes']}, 'a test is not a session the phase trains'
    assert any(c.startswith('Test: KB Pentathlon') for c in comp['changes']), comp['changes']
    # Volume, repeats and intervals: three a week, the test counted as the volume session.
    assert comp['sessions_per_week'].get('strength_endurance') == 3.0, 'the test counts as the session it replaced'


# ── fidelity ─────────────────────────────────────────────────────────────────

def test_fidelity_reads_the_tests():
    from src import fidelity
    phase = {'id': 'p', 'weeks': 2, 'tests': [{'archetype': 't1', 'week': 'last'}]}
    std = {'slot_role': 'x', 'exercise': {'id': 'e'}, 'standard': {'id': 's'}, 'load': {'test': True}}
    test_session = {'modality': 'm', 'archetype': {'id': 't1'}, 'test': {'archetype': 't1'}, 'exercises': [std]}

    def run(weeks):
        out = fidelity._Collector()
        fidelity._check_tests(out, 'p', phase, weeks)
        return {f.rule for f in out.findings()}
    ok = [{'week_number': 1, 'week_in_phase': 1, 'schedule': {}},
          {'week_number': 2, 'week_in_phase': 2, 'schedule': {'Monday': [test_session]}}]
    assert run(ok) == set()
    assert run([ok[0], {'week_number': 2, 'week_in_phase': 2, 'schedule': {}}]) == {'test_missing'}
    assert run([{**ok[0], 'schedule': {'Monday': [test_session]}}, ok[1]]) == {'test_unexpected'}
    scaled = copy.deepcopy(test_session)
    scaled['exercises'][0]['load'] = {'distance_km': 1.5}
    assert run([ok[0], {**ok[1], 'schedule': {'Monday': [scaled]}}]) == {'test_scaled'}
    assert run([ok[0], {**ok[1], 'tests_skipped': [{'archetypes': ['t1'], 'reason': 'equipment_gap'}]}]) \
        == {'test_skipped'}
    assert run([ok[0], {**ok[1], 'tests_skipped': [{'archetypes': ['t1'], 'reason': 'archetype_unavailable'}]}]) \
        == {'test_unplaceable'}


if __name__ == '__main__':
    for name, fn in list(globals().items()):
        if name.startswith('test_'):
            fn(); print('ok', name)
    print('all passed')
