#!/usr/bin/env python
"""Program-specific analytics: the pure engine, no database.

Fixtures are built by hand to the stored-program shape (what
api._clean_exercise_assignment leaves behind), so these assert against what
the athlete actually saw, not against a re-run of the generator.

Run: .venv/bin/python test_program_analytics.py
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from src.analytics import families, trend, zones

_failures: list[str] = []


def check(label: str, condition: bool, detail: str = '') -> None:
    if condition:
        print(f'  ok   {label}')
    else:
        print(f'  FAIL {label}' + (f' — {detail}' if detail else ''))
        _failures.append(label)


# ── families ─────────────────────────────────────────────────────────────────

def test_families() -> None:
    print('\nmodality families')
    import os
    real = sorted(f[:-5] for f in os.listdir('data/commons/modalities') if f.endswith('.yaml'))
    covered = sorted(m for ms in families.families().values() for m in ms)
    check('every real modality is in exactly one family', covered == real,
          str(set(covered) ^ set(real)))
    check('combat_sport and rehab are no longer dropped',
          families.family_of('combat_sport') == 'combat' and families.family_of('rehab') == 'skill')
    check('an unknown id is "other", not an error', families.family_of('long_zone_2') == 'other')
    check('None is "other"', families.family_of(None) == 'other')
    check('is_strength', families.is_strength('power') and not families.is_strength('aerobic_base'))


# ── zones ────────────────────────────────────────────────────────────────────

def _samples(bpm_by_minute: list[int], start='2026-03-02T09:00:00+00:00') -> list[dict]:
    from datetime import datetime, timedelta
    t0 = datetime.fromisoformat(start)
    return [{'timestamp': (t0 + timedelta(minutes=i)).isoformat(), 'bpm': b}
            for i, b in enumerate(bpm_by_minute)]


def test_zones() -> None:
    print('\nHR zones')
    check('assign_zone respects the data-declared edges',
          [zones.assign_zone(b, 200) for b in (100, 140, 165, 180, 195)] == [0, 1, 2, 3, 4])

    # 30 min at 72% of max HR — honest Zone 2. Under Friel 60/70/80/90 this was Z3.
    w = {'durationMinutes': 30, 'heartRate': {'samples': _samples([144] * 31)}}
    zm = zones.zone_minutes(w, 200)
    check('sample integration is exact', abs(zm['minutes'][1] - 30) < 0.01, str(zm))
    check('and reports method=samples', zm['method'] == 'samples')
    check('72% of max lands in zone1_2, the bucket Uphill writes its 80/20 in',
          zones.to_framework_buckets(zm['minutes'])['zone1_2_pct'] > 29.9)

    # A 10-minute gap between samples is capped at 60 s, not counted as 10 min.
    gappy = {'durationMinutes': 20, 'heartRate': {'samples': [
        {'timestamp': '2026-03-02T09:00:00+00:00', 'bpm': 140},
        {'timestamp': '2026-03-02T09:10:00+00:00', 'bpm': 140},
        {'timestamp': '2026-03-02T09:10:30+00:00', 'bpm': 140}]}}
    check('sample gaps are capped at 60 s',
          abs(zones.zone_fractions(gappy, 200)['measured_seconds'] - 90) < 0.01)

    est = zones.zone_fractions({'durationMinutes': 60, 'heartRate': {'avg': 135, 'max': 160}}, 190)
    check('no samples → summary estimate, and it says so', est['method'] == 'summary_estimate')
    check('estimate fractions sum to 1', abs(sum(est['fractions']) - 1) < 1e-9)

    none = zones.zone_fractions({'durationMinutes': 45}, 190)
    check('no HR at all → method none, zero fractions', none['method'] == 'none'
          and sum(none['fractions']) == 0)
    check('and a TRIMP of exactly 0', zones.trimp({'durationMinutes': 45}, 190) == 0.0)

    check('TRIMP weights climb with zone',
          zones.trimp({'durationMinutes': 10, 'heartRate': {'samples': _samples([190] * 11)}}, 200)
          > zones.trimp({'durationMinutes': 10, 'heartRate': {'samples': _samples([120] * 11)}}, 200))
    check('config carries a version for cache keys', isinstance(zones.version(), int))


# ── trend ────────────────────────────────────────────────────────────────────

def test_trend() -> None:
    print('\ntrend and stall')
    P = trend.Point
    up = [P(i, 100 + 2.5 * i) for i in range(6)]
    check('a steady +2.5/wk on 100 is improving', trend.fit(up).direction == 'improving')
    flat = [P(i, 100) for i in range(6)]
    check('a flat series is stable', trend.fit(flat).direction == 'stable')
    down = [P(i, 100 - 3 * i) for i in range(6)]
    check('a falling series is declining', trend.fit(down).direction == 'declining')
    check('two points is insufficient', trend.fit(up[:2]).direction == 'insufficient_data')

    # A deload dip in the middle must not turn a rising series into "stable".
    dip = [P(0, 100), P(1, 102.5), P(2, 60, is_deload=True), P(3, 107.5), P(4, 110)]
    t = trend.fit(dip)
    check('deload points are excluded from the fit', t.points_used == 4 and t.direction == 'improving',
          str(t))

    # First-third vs last-third would have called this "improving" (mean 100 vs ~100.7);
    # the slope sees a single spike in an otherwise flat series.
    spiky = [P(0, 100), P(1, 100), P(2, 100), P(3, 100), P(4, 100), P(5, 102)]
    check('a single late uptick is not a trend', trend.fit(spiky).direction == 'stable')

    check('stall after 3 flat sessions',
          trend.stalled([P(i, 100) for i in range(4)], sessions=3))
    check('no stall while still climbing',
          not trend.stalled([P(i, 100 + 2.5 * i) for i in range(4)], sessions=3))
    check('a stall window ignores deload sessions',
          trend.stalled([P(0, 100), P(1, 60, True), P(2, 100), P(3, 100), P(4, 100)], sessions=3))
    check('too few sessions cannot be a stall', not trend.stalled(flat[:2], sessions=3))

    t = trend.fit(up)
    check('ahead of an expected slope', trend.status(t, expected_slope=2.0, base=100) == 'ahead')
    check('behind an expected slope', trend.status(t, expected_slope=6.0, base=100) == 'behind')
    check('on track', trend.status(t, expected_slope=2.5, base=100) == 'on_track')
    check('flat with no expectation is stable_by_design, not failure',
          trend.status(trend.fit(flat), None, 100) == 'stable_by_design')


# ── spec: declared, default, composed, scoped ────────────────────────────────

import contextlib
import os
import shutil
import yaml

_PKG_ROOT = Path(__file__).parent / 'data' / 'packages'


@contextlib.contextmanager
def throwaway_package(pkg_id: str, analytics: dict | None, borrows: list | None = None):
    """A minimal package on disk: philosophy + one framework (+ analytics.yaml).

    The self-containment proof: a new methodology must get its own analytics
    with no change to src/.
    """
    root = _PKG_ROOT / pkg_id
    if root.exists():
        shutil.rmtree(root)
    (root / 'frameworks').mkdir(parents=True)
    phil = {'id': pkg_id, 'name': 'Throwaway', 'core_principles': ['test'],
            'scope': ['max_strength', 'aerobic_base'], 'bias': ['max_strength'],
            'progression_philosophy': 'load_based',
            'primary_framework_id': f'{pkg_id}_fw', 'self_contained': True}
    if borrows:
        phil['borrows_from'] = borrows
    (root / 'philosophy.yaml').write_text(yaml.safe_dump(phil))
    (root / 'frameworks' / f'{pkg_id}_fw.yaml').write_text(yaml.safe_dump({
        'id': f'{pkg_id}_fw', 'name': 'Throwaway FW', 'source_philosophy': pkg_id,
        'sessions_per_week': {'max_strength': 3, 'aerobic_base': 2},
        'modality_priority': {'committed': ['max_strength'], 'core': ['aerobic_base'],
                              'supplementary': []},
        'progression_model': 'linear_load',
        'expectations': {'min_weeks': 4, 'ideal_weeks': 8, 'min_days_per_week': 3,
                         'ideal_days_per_week': 5, 'min_session_minutes': 45,
                         'ideal_session_minutes': 60, 'supports_split_days': False}}))
    (root / 'exercises.yaml').write_text(yaml.safe_dump({'exercises': [
        {'id': f'{pkg_id}_lift', 'name': 'Lift', 'category': 'barbell',
         'modality': ['max_strength'], 'equipment': ['barbell'], 'effort': 'high'}]}))
    if analytics is not None:
        (root / 'analytics.yaml').write_text(yaml.safe_dump(analytics))
    try:
        yield root
    finally:
        shutil.rmtree(root, ignore_errors=True)


def test_spec_defaults() -> None:
    print('\nspec: synthesised defaults')
    from src import loader
    from src.analytics import spec
    fws, mods = loader.load_all_frameworks(), loader.load_all_modalities()

    def default_for(pid):   # the fallback path, regardless of whether a file now exists
        return spec._synthesise(pid, fws, mods, loader.load_philosophy(pid), 1.0)

    filly = spec.spec_for('marcus_filly')
    check('a package with no analytics.yaml gets a synthesised default', filly.source == 'default')
    ss = default_for('starting_strength')
    check('SS default measures load on the bar', [e.primitive for e in ss.entries] == ['set_load'])
    check('scoped to max_strength working sets, excluding preparatory roles rather than guessing names',
          ss.entries[0].scope['modalities'] == ['max_strength']
          and ss.entries[0].scope['slot_types'] == ['sets_reps']
          and '*warm*' in ss.entries[0].scope['exclude_slot_roles'] and 'slot_roles' not in ss.entries[0].scope,
          str(ss.entries[0].scope))
    check('expected = last achieved + increment (survives phase resets)',
          ss.entries[0].expected == 'achieved_plus_increment')
    check('load_based philosophy leads with set_load', ss.entries[0].headline)

    up = default_for('uphill_athlete')
    prims = {e.id: e.primitive for e in up.entries}
    check('Uphill aerobic base measures the zone split against the framework',
          prims.get('aerobic_base_zone_minutes') == 'zone_minutes')
    check('and the framework_field expectation points at intensity_distribution',
          next(e for e in up.entries if e.id == 'aerobic_base_zone_minutes').expected
          == {'framework_field': 'intensity_distribution'})
    check('a modality governed by several phase frameworks appears once',
          len([e for e in up.entries if e.id == 'max_strength_set_load']) == 1)
    check('exactly one headline', sum(e.headline for e in up.entries) == 1)

    ido = default_for('ido_portal')
    check('complexity-based philosophy leads with unlocks',
          next(e for e in ido.entries if e.headline).primitive == 'unlocks')
    for pid in ('starting_strength', 'uphill_athlete', 'wildman_kettlebell', 'ido_portal'):
        check(f'{pid} now ships a declared analytics.yaml', spec.spec_for(pid).source == 'declared')


def test_spec_declared_overrides_default() -> None:
    print('\nspec: a declared analytics.yaml overrides the default')
    from src.analytics import spec
    declared = {'id': '_zz_test', 'progress': [
        {'id': 'my_metric', 'label': 'My metric', 'primitive': 'rounds',
         'scope': {'modalities': ['aerobic_base']}, 'expected': {'constant': 5},
         'headline': True},
        {'id': 'std', 'primitive': 'benchmark_level',
         'benchmarks': ['back_squat_bw_ratio'], 'target_level': 'advanced'}],
        'movement': {'balance': [{'a': 'push', 'b': 'pull', 'min': 0.8, 'max': 1.2}]},
        'benchmarks': ['deadlift_bw_ratio']}
    with throwaway_package('_zz_test', None):
        s = spec.spec_for('_zz_test')
        check('no file → default, from the package\'s own framework', s.source == 'default'
              and {e.primitive for e in s.entries} == {'set_load', 'zone_minutes'}, str(s))
    with throwaway_package('_zz_test', declared):
        s = spec.spec_for('_zz_test')
        check('with the file → declared', s.source == 'declared')
        check('entries are the package\'s, in order',
              [e.id for e in s.entries] == ['my_metric', 'std'])
        check('the declared headline is honoured', s.entries[0].headline and not s.entries[1].headline)
        check('declared balance ratios become warnings', s.balance_declared
              and s.balance[0]['a'] == 'push')
        check('extra benchmarks carried', s.benchmarks == ['deadlift_bw_ratio'])
        check('target_level and benchmarks reach the entry',
              s.entries[1].target_level == 'advanced'
              and s.entries[1].benchmarks == ['back_squat_bw_ratio'])
        # The new package validates against the schema with no change to src/.
        import subprocess
        r = subprocess.run([sys.executable, 'tools/validate_entities.py',
                            str(_PKG_ROOT / '_zz_test' / 'analytics.yaml')],
                           capture_output=True, text=True)
        check('the schema validates the declared file', r.returncode == 0, r.stdout[-300:])


def test_spec_provenance() -> None:
    print('\nspec: provenance')
    sys.path.insert(0, 'tools')
    import importlib
    cp = importlib.import_module('check_provenance')
    bad = {'id': '_zz_test', 'progress': [
        {'id': 'x', 'primitive': 'set_load', 'scope': {'exercises': ['back_squat']}},
        {'id': 'y', 'primitive': 'set_load', 'scope': {'archetypes': ['3x5_linear']}},
        {'id': 'z', 'primitive': 'benchmark_level', 'benchmarks': ['no_such_benchmark']}]}
    with throwaway_package('_zz_test', bad):
        problems = [p for p in cp.report_authoring() if '_zz_test' in p]
        check('a foreign exercise is rejected', any("exercise 'back_squat'" in p for p in problems),
              str(problems))
        check('a foreign archetype is rejected', any("archetype '3x5_linear'" in p for p in problems))
        check('an unknown benchmark is rejected', any('no_such_benchmark' in p for p in problems))
    ok = {'id': '_zz_test', 'progress': [
        {'id': 'x', 'primitive': 'set_load', 'scope': {'exercises': ['back_squat']}}]}
    with throwaway_package('_zz_test', ok, borrows=[{'package': 'starting_strength',
                                                     'kinds': ['exercises']}]):
        problems = [p for p in cp.report_authoring() if '_zz_test' in p]
        check('a borrowed exercise is allowed', not problems, str(problems))
    with throwaway_package('_zz_test', {'id': 'wrong_id', 'progress': [
            {'id': 'x', 'primitive': 'set_load'}]}):
        problems = [p for p in cp.report_authoring() if '_zz_test' in p]
        check('id must equal the package', any('must equal the package' in p for p in problems))


def test_spec_compose_and_scope() -> None:
    print('\nspec: composition and scope')
    from src.analytics import spec
    goal = {'primary_sources': ['uphill_athlete', 'starting_strength']}
    specs = spec.compose(goal, {'uphill_athlete': 0.7, 'starting_strength': 0.3})
    check('one spec per philosophy, primary first',
          [s.philosophy for s in specs] == ['uphill_athlete', 'starting_strength'])
    check('weights flow onto every entry',
          all(e.weight == 0.7 for e in specs[0].entries)
          and all(e.weight == 0.3 for e in specs[1].entries))
    check('a single philosophy weighs 1.0',
          spec.compose({'primary_sources': ['starting_strength']})[0].entries[0].weight == 1.0)

    weeks = [{'week_number': 1, 'framework': 'linear_progression', 'schedule': {
        'Monday': [{'modality': 'max_strength', 'archetype': {'id': '3x5_linear'}, 'exercises': [
            {'exercise': {'id': 'back_squat', 'movement_patterns': ['squat']}, 'slot_role': 'primary_squat', 'slot_type': 'sets_reps'},
            {'exercise': {'id': 'plank', 'movement_patterns': ['isometric']}, 'slot_role': 'accessory_core', 'slot_type': 'static_hold'},
            {'exercise': {'id': 'x'}, 'slot_role': 'primary_pull', 'slot_type': 'sets_reps', 'injury_skip': True},
            {'exercise': None, 'meta': True, 'slot_role': 'warmup'}]},
                   {'modality': 'aerobic_base', 'archetype': {'id': 'z2'}, 'exercises': []}]}},
        {'week_number': 2, 'framework': {'id': 'other_fw'}, 'schedule': {
            'Monday': [{'modality': 'max_strength', 'archetype': {'id': '3x5_linear'}, 'exercises': []}]}}]
    e = spec.Entry(id='t', primitive='set_load', philosophy='p',
                   scope={'modalities': ['max_strength'], 'slot_roles': ['primary_*']})
    hits = spec.select(e, weeks)
    check('session-level scope picks only max_strength sessions',
          [h['session']['modality'] for h in hits] == ['max_strength', 'max_strength'])
    check('slot_roles glob keeps primary_* and drops accessories',
          [ea['exercise']['id'] for ea in hits[0]['assignments']] == ['back_squat'])
    check('injury_skip and meta rows are never work',
          not any(ea.get('injury_skip') or ea.get('meta') for ea in hits[0]['assignments']))
    e2 = spec.Entry(id='t', primitive='set_load', philosophy='p',
                    scope={'frameworks': ['other_fw']})
    check('frameworks scope accepts an id or a dict on week.framework',
          [h['week']['week_number'] for h in spec.select(e2, weeks)] == [2])
    e_ex = spec.Entry(id='t', primitive='set_load', philosophy='p',
                      scope={'exclude_slot_roles': ['*accessory*']})
    check('exclude_slot_roles drops matching roles and keeps the rest',
          [ea['exercise']['id'] for ea in spec.select(e_ex, weeks)[0]['assignments']] == ['back_squat'])
    e3 = spec.Entry(id='t', primitive='set_load', philosophy='p',
                    scope={'movement_patterns': ['isometric']})
    check('movement_patterns scope selects by exercise pattern',
          [ea['exercise']['id'] for ea in spec.select(e3, weeks)[0]['assignments']] == ['plank'])
    check('an empty scope selects everything', len(spec.select(spec.Entry('t', 'duration', 'p'), weeks)) == 3)


# ── context, frame, scorecard ────────────────────────────────────────────────

from datetime import date, timedelta
from src.analytics.context import AnalyticsInputs, Context
from src.analytics import frame as frame_mod, scorecard as scorecard_mod, spec as spec_mod

TEST_FW = {'test_fw': {
    'id': 'test_fw', 'name': 'Test FW', 'source_philosophy': 'starting_strength',
    'sessions_per_week': {'max_strength': 2, 'aerobic_base': 1},
    'modality_priority': {'committed': ['max_strength'], 'core': ['aerobic_base'],
                          'supplementary': []},
    'progression_model': 'linear_load',
    'expectations': {'min_weeks': 4, 'ideal_weeks': 8, 'min_days_per_week': 2,
                     'ideal_days_per_week': 5, 'min_session_minutes': 45,
                     'ideal_session_minutes': 60, 'supports_split_days': False}}}


def _lift(ex_id, role, kg, sets=3, reps=5):
    return {'exercise': {'id': ex_id, 'name': ex_id, 'movement_patterns': ['squat']},
            'slot_role': role, 'slot_type': 'sets_reps',
            'load': {'sets': sets, 'reps': reps, 'weight_kg': kg}}


def _aerobic(minutes):
    return {'exercise': {'id': 'easy_run', 'name': 'Easy run', 'movement_patterns': ['locomotion']},
            'slot_role': 'main_aerobic', 'slot_type': 'time_domain',
            'load': {'duration_minutes': minutes, 'zone_target': 'Zone 2'}}


def fixture_program(weeks=4, deload_week=3):
    """SS-like: Mon/Wed squat, Sat easy run. Week `deload_week` is a deload."""
    out = []
    for n in range(1, weeks + 1):
        kg = 100 + 2.5 * (n - 1)
        out.append({
            'week_number': n, 'week_in_phase': n, 'phase': 'base',
            'is_deload': n == deload_week, 'framework': 'test_fw',
            'schedule': {
                'Monday':    [{'modality': 'max_strength', 'archetype': {'id': 'sq', 'name': 'Squat day', 'duration_estimate_minutes': 60},
                               'exercises': [_lift('back_squat', 'primary_squat', kg), _lift('press', 'upper_press', 40),
                                             {'exercise': None, 'meta': True, 'slot_role': 'warmup'}]}],
                'Wednesday': [{'modality': 'max_strength', 'archetype': {'id': 'sq', 'name': 'Squat day', 'duration_estimate_minutes': 60},
                               'exercises': [_lift('back_squat', 'primary_squat', kg + 1.25)]}],
                'Saturday':  [{'modality': 'aerobic_base', 'archetype': {'id': 'z2', 'name': 'Easy run', 'duration_estimate_minutes': 45},
                               'exercises': [_aerobic(60)]}],
            }})
    return {
        'goal': {'id': '_phil_starting_strength', 'name': 'SS', 'primary_sources': ['starting_strength'],
                 'priorities': {'max_strength': 0.67, 'aerobic_base': 0.33},
                 'phase_sequence': [{'phase': 'base', 'weeks': weeks, 'focus': 'Build the base.'}],
                 'framework_selection': {'default_framework': 'test_fw'}},
        'constraints': {'training_level': 'novice', 'days_per_week': 3, 'session_time_minutes': 60},
        'weeks': out,
    }


START = date(2026, 3, 2)              # a Monday
TODAY = START + timedelta(days=17)    # Thursday of week 3


def _log(completed_at, exercises=None, **extra):
    return {'completedAt': completed_at, 'exercises': exercises or {}, **extra}


def test_context() -> None:
    print('\ncontext: window, dates, duration hierarchy')
    logs = {
        '1-Monday-0': _log('2026-03-02T10:00:00+00:00'),
        '1-Wednesday': _log('2026-03-04T10:00:00+00:00'),            # day-level key, one session that day
        '2-Monday-0': _log('2026-02-01T10:00:00+00:00'),             # BEFORE the program: last block's row
        '3-Monday-0': _log('2026-03-16T10:00:00+00:00', exerciseTimeline=[
            {'exerciseId': 'back_squat', 'startOffset': 0, 'endOffset': 2700}]),
    }
    workouts = [
        {'id': 'w-sat1', 'date': '2026-03-07', 'durationMinutes': 55, 'heartRate': {'avg': 130}},
        {'id': 'w-old', 'date': '2026-01-10', 'durationMinutes': 55},
    ]
    matches = [{'importedWorkoutId': 'w-sat1', 'sessionKey': '1-Saturday-0', 'matchConfidence': 'auto'},
               {'importedWorkoutId': 'w-old', 'sessionKey': '1-Saturday-0', 'matchConfidence': 'auto'},
               {'importedWorkoutId': 'w-sat1', 'sessionKey': '2-Saturday-0', 'matchConfidence': 'rejected'}]
    ctx = Context(AnalyticsInputs(fixture_program(), START, TODAY, logs, matches, workouts),
                  frameworks=TEST_FW)

    check('a log dated before the program is outside the window', '2-Monday-0' not in ctx.session_logs)
    check('a workout dated before the program is outside the window', 'w-old' not in ctx.workouts)
    check('rejected matches are dropped', all(m['matchConfidence'] != 'rejected' for m in ctx.matches))
    check('week → date is Monday-anchored', ctx.session_date(2, 'Wednesday') == date(2026, 3, 18))
    check('elapsed week indexes stop at today', ctx.elapsed_week_indexes == [0, 1, 2])
    check('current week index', ctx.current_week_index == 2)
    hits = list(ctx.sessions(elapsed_only=True))
    check('elapsed sessions: 3+3+2 (week-3 Saturday is in the future)', len(hits) == 8, str(len(hits)))

    by = {(h['week_index'], h['day']): h for h in hits}
    check('indexed key completes a session', ctx.completed(by[(0, 'Monday')]))
    check('a day-level key completes the only session that day', ctx.completed(by[(0, 'Wednesday')]))
    check('an unlogged session is not complete', not ctx.completed(by[(1, 'Wednesday')]))
    check('a matched workout is found by key', (ctx.workout_for(by[(0, 'Saturday')]) or {}).get('id') == 'w-sat1')

    check('duration: matched workout wins', ctx.duration_minutes(by[(0, 'Saturday')]) == (55.0, 'workout'))
    check('duration: timeline span next', ctx.duration_minutes(by[(2, 'Monday')]) == (45.0, 'timeline'))
    check('duration: prescribed minutes next', ctx.duration_minutes(by[(1, 'Saturday')]) == (60.0, 'prescribed'))
    m, src_ = ctx.duration_minutes(by[(1, 'Monday')])
    check('duration: archetype estimate last', (m, src_) == (60.0, 'estimate'))
    m, _ = ctx.duration_minutes(by[(2, 'Wednesday')])
    check('estimate is scaled 0.7 on a deload week', abs(m - 42.0) < 1e-9, str(m))

    check('tier from the governing framework', ctx.tier_of('max_strength', ctx.weeks[0]) == 'committed'
          and ctx.tier_of('aerobic_base', ctx.weeks[0]) == 'core')
    check('a modality the framework never schedules is unscheduled',
          ctx.tier_of('combat_sport', ctx.weeks[0]) == 'unscheduled')
    check('deload by flag', ctx.is_deload_week(ctx.weeks[2]))
    check('deload by phase (taper)', ctx.is_deload_week({'phase': 'taper'}))


def test_frame() -> None:
    print('\nframe')
    ctx = Context(AnalyticsInputs(fixture_program(), START, TODAY), frameworks=TEST_FW)
    specs = spec_mod.compose(ctx.goal)
    f = frame_mod.build(ctx, specs)
    check('status active', f['status'] == 'active')
    check('phase from the current week, with its focus prose',
          f['phase']['name'] == 'base' and f['phase']['weekInProgram'] == 3
          and f['phase']['focus'] == 'Build the base.')
    check('the current week is a deload and the frame says so', f['phase']['isDeload'])
    check('deload weeks listed by number', f['deloadWeeks'] == [3])
    check('elapsed / planned weeks', (f['elapsedWeeks'], f['plannedWeeks']) == (3, 4))
    check('philosophy carries its analytics source (SS now ships analytics.yaml)',
          f['philosophies'][0]['analytics'] == 'declared'
          and f['philosophies'][0]['progressionPhilosophy'] == 'load_based')
    check('framework in force', f['framework']['id'] == 'test_fw')
    fid = {row['field']: row['status'] for row in f['planFidelity']}
    check('plan fidelity: 3 days vs ideal 5 is below_ideal', fid.get('days_per_week') == 'below_ideal')
    check('plan fidelity: 60 min meets ideal', fid.get('session_time_minutes') == 'meets_ideal')
    check('plan fidelity: 4 weeks is below ideal 8 but not below min 4', fid.get('weeks') == 'below_ideal')
    before = frame_mod.build(Context(AnalyticsInputs(fixture_program(), START, START - timedelta(days=1)),
                                     frameworks=TEST_FW), specs)
    check('before the start date the status is not_started', before['status'] == 'not_started')


def test_scorecard() -> None:
    print('\nscorecard')
    # Every aerobic session done, only 2 of 6 elapsed strength sessions done.
    logs = {
        '1-Monday-0': _log('2026-03-02T10:00:00+00:00'), '2-Monday-0': _log('2026-03-09T10:00:00+00:00'),
        '1-Saturday-0': _log('2026-03-07T10:00:00+00:00'), '2-Saturday-0': _log('2026-03-14T10:00:00+00:00'),
    }
    ctx = Context(AnalyticsInputs(fixture_program(), START, TODAY, logs), frameworks=TEST_FW)
    sc = scorecard_mod.build(ctx)
    rows = {r['modality']: r for r in sc['modalities']}
    check('planned counts only elapsed sessions', rows['max_strength']['plannedSessions'] == 6
          and rows['aerobic_base']['plannedSessions'] == 2)
    check('completion per modality', rows['max_strength']['completedSessions'] == 2
          and rows['aerobic_base']['completionPct'] == 100.0)
    check('overall completion is 4/8', sc['overallPct'] == 50.0)
    check('committed tier at 33% gates the headline to off_plan, despite 100% aerobic',
          sc['headline'] == 'off_plan' and sc['tiers']['committed']['pct'] < 70)
    check('rows ordered by goal priority', [r['modality'] for r in sc['modalities']]
          == ['max_strength', 'aerobic_base'])
    check('tier on each row', rows['max_strength']['tier'] == 'committed'
          and rows['aerobic_base']['tier'] == 'core')
    # aerobic_base min_weekly_minutes is 90; one 60-minute run per week is under-dosed —
    # by the PLAN, not just by the athlete.
    check('plan dose: 60 min/wk of aerobic is under the modality minimum',
          rows['aerobic_base']['planDoseStatus'] == 'under')
    check('actual dose follows the athlete', rows['aerobic_base']['doseStatus'] == 'under')
    check('minutes source is recorded', rows['aerobic_base']['minutesSource'] == {'prescribed': 2})

    # Do the committed work instead → on_plan.
    logs2 = {f'{n}-{d}-0': _log(f'2026-03-{2 + (n-1)*7 + o:02d}T10:00:00+00:00')
             for n in (1, 2) for d, o in (('Monday', 0), ('Wednesday', 2))}
    logs2['3-Monday-0'] = _log('2026-03-16T10:00:00+00:00')
    sc2 = scorecard_mod.build(Context(AnalyticsInputs(fixture_program(), START, TODAY, logs2),
                                      frameworks=TEST_FW))
    check('5 of 6 committed sessions → on_plan even with no aerobic at all',
          sc2['headline'] == 'on_plan' and sc2['tiers']['core']['pct'] == 0.0)
    empty = scorecard_mod.build(Context(AnalyticsInputs(fixture_program(), START, START - timedelta(days=3)),
                                        frameworks=TEST_FW))
    check('nothing elapsed → not_started', empty['headline'] == 'not_started')


# ── primitives ───────────────────────────────────────────────────────────────

from src.analytics import primitives as prims
from src.analytics.primitives import run as run_primitive, max_hr_for
E = spec_mod.Entry


def _sets(*pairs, rpe=None, completed=True, hold=None):
    out = []
    for i, (w, r) in enumerate(pairs):
        s = {'setIndex': i, 'completed': completed, 'weightKg': w, 'repsActual': r}
        if rpe is not None:
            s['rpe'] = rpe
        if hold is not None:
            s['durationSeconds'] = hold
        out.append(s)
    return out


def _hr_samples(bpm: int, minutes: int, start: str):
    from datetime import datetime as _dt, timedelta as _td
    t0 = _dt.fromisoformat(start)
    return [{'timestamp': (t0 + _td(minutes=i)).isoformat(), 'bpm': bpm} for i in range(minutes + 1)]


def _ctx(program, logs=None, workouts=None, matches=None, today=TODAY, profile=None, perf=None):
    return Context(AnalyticsInputs(program, START, today, logs or {}, matches or [], workouts or [],
                                   perf or {}, [], profile or {}), frameworks=TEST_FW)


def test_set_load() -> None:
    print('\nprimitive: set_load')
    prog = fixture_program(weeks=4, deload_week=3)
    kg = lambda n: 100 + 2.5 * (n - 1)  # noqa: E731
    logs = {}
    for n, day, off in ((1, 'Monday', 0), (1, 'Wednesday', 2), (2, 'Monday', 7), (2, 'Wednesday', 9),
                        (3, 'Monday', 14), (3, 'Wednesday', 16)):
        w = kg(n) if n != 3 else 80.0    # week 3 is the deload
        logs[f'{n}-{day}-0'] = _log(f'2026-03-{2 + off:02d}T10:00:00+00:00',
                                    {'back_squat': {'sets': _sets((w, 5), (w, 5), (w, 5))}})
    # A set with a weight but no reps in the middle — the old tracker's pairing bug.
    logs['2-Monday-0']['exercises']['back_squat']['sets'][1]['repsActual'] = None
    logs['2-Monday-0']['exercises']['back_squat']['sets'][2] = {'setIndex': 2, 'completed': True,
                                                                'weightKg': 105, 'repsActual': 3}
    ctx = _ctx(prog, logs)
    e = E('bar', 'set_load', 'starting_strength', scope={'modalities': ['max_strength'],
          'slot_roles': ['primary_*']}, expected='achieved_plus_increment', stall={'sessions': 3})
    r = run_primitive(e, ctx)
    check('one exercise measured (press is not primary_*)', [x['exerciseId'] for x in r['exercises']] == ['back_squat'])
    sq = r['exercises'][0]
    check('six sessions of points', len(sq['series']) == 6)
    check('coverage 100% of completed in-scope sessions', r['coverage']['pct'] == 100.0, str(r['coverage']))
    p2 = sq['series'][2]
    check('best set is the heaviest, paired with ITS OWN reps (105×3, not 105×5)',
          p2['value'] == 105 and p2['reps'] == 3, str(p2))
    check('Epley from the paired reps', p2['est1rm'] == round(105 * (1 + 0.0333 * 3), 1))
    check('volume skips the rep-less set', p2['volume'] == 102.5 * 5 + 105 * 3)
    # 100 → expect 102.5 → still 102.5 (week-1 Wednesday also lifted 100) →
    # 107.5, because session 3's best set was the 105×3 above.
    check('first expected = prescribed; later = last achieved + increment',
          [e['value'] for e in sq['expected'][:4]] == [100.0, 102.5, 102.5, 107.5], str(sq['expected'][:4]))
    check('deload points are flagged, not dropped', sq['series'][4]['isDeload'] and sq['series'][4]['value'] == 80)
    check('trend fits the non-deload points and is improving', sq['trend']['direction'] == 'improving'
          and sq['trend']['pointsUsed'] == 4, str(sq['trend']))
    check('status relative to the increment', sq['status'] in ('on_track', 'ahead'), sq['status'])
    check('prescribedNow is the latest prescription (week-3 Wednesday)', sq['prescribedNow'] == kg(3) + 1.25)
    check('stall rule recorded as declared', r['stallRule'] == {'sessions': 3, 'source': 'declared'})

    # Three flat sessions → stalled.
    flat = {k: v for k, v in logs.items()}
    for key in ('1-Monday-0', '1-Wednesday-0', '2-Monday-0', '2-Wednesday-0'):
        flat[key] = _log(logs[key]['completedAt'], {'back_squat': {'sets': _sets((100, 5), (100, 5), (100, 5))}})
    r2 = run_primitive(e, _ctx(prog, flat, today=START + timedelta(days=10)))
    check('three flat sessions after the first → stalled', r2['exercises'][0]['stalled']
          and r2['status'] == 'stalled', str(r2['exercises'][0]['status']))

    # Completed but unlogged: counts for coverage denominator, not measured.
    partial = {'1-Monday-0': _log('2026-03-02T10:00:00+00:00'), '1-Wednesday-0': logs['1-Wednesday-0']}
    r3 = run_primitive(e, _ctx(prog, partial, today=START + timedelta(days=5)))
    check('completed-but-unlogged lowers coverage, not the metric',
          r3['coverage'] == {'inScope': 2, 'measured': 1, 'pct': 50.0, 'reason': None}, str(r3['coverage']))
    r4 = run_primitive(e, _ctx(prog, {'1-Monday-0': _log('2026-03-02T10:00:00+00:00')},
                               today=START + timedelta(days=1)))
    check('nothing logged → reason no_sets_logged', r4['coverage']['reason'] == 'no_sets_logged')


def test_load_at_rpe() -> None:
    print('\nprimitive: load_at_rpe')
    prog = fixture_program(weeks=2)
    for wk in prog['weeks']:
        for s in wk['schedule']['Monday']:
            s['exercises'][0]['load']['target_rpe'] = 8
    logs = {'1-Monday-0': _log('2026-03-02T10:00:00+00:00', {'back_squat': {'sets':
                _sets((100, 5), rpe=7) + _sets((110, 5), rpe=8) + _sets((120, 5), rpe=10)}}),
            '2-Monday-0': _log('2026-03-09T10:00:00+00:00', {'back_squat': {'sets': _sets((115, 5), rpe=8)}})}
    e = E('rpe', 'load_at_rpe', 'marcus_filly', scope={'modalities': ['max_strength'], 'slot_roles': ['primary_*']})
    r = run_primitive(e, _ctx(prog, logs))
    check('heaviest set within ±1 of RPE 8 (110 @8, not 120 @10)', r['series'][0]['value'] == 110)
    check('second session', r['series'][1]['value'] == 115)
    nolog = run_primitive(e, _ctx(prog, {'1-Monday-0': _log('2026-03-02T10:00:00+00:00',
                                                            {'back_squat': {'sets': _sets((100, 5))}})}))
    check('sets without RPE → rpe_not_logged', nolog['coverage']['reason'] == 'rpe_not_logged')
    notarget = run_primitive(e, _ctx(fixture_program(weeks=1), {'1-Monday-0': logs['1-Monday-0']}))
    check('no target anywhere → no_rpe_target (the generator gap)', notarget['coverage']['reason'] == 'no_rpe_target')


def density_program():
    prog = fixture_program(weeks=2)
    for wk in prog['weeks']:
        wk['schedule']['Friday'] = [{'modality': 'mixed_modal_conditioning',
            'archetype': {'id': 'amrap20', 'name': 'AMRAP 20', 'duration_estimate_minutes': 30},
            'exercises': [{'exercise': {'id': 'kb_swing', 'name': 'KB swing', 'movement_patterns': ['hip_hinge', 'ballistic']},
                           'slot_role': 'main', 'slot_type': 'amrap',
                           'load': {'time_minutes': 20, 'target_rounds': 8}}]}]
    return prog


def test_rounds_rate_hold_distance() -> None:
    print('\nprimitives: rounds / rate / hold_seconds / distance')
    prog = density_program()
    e = E('r', 'rounds', 'crossfit', scope={'slot_types': ['amrap']})
    before = run_primitive(e, _ctx(prog, {'1-Friday-0': _log('2026-03-06T10:00:00+00:00')}))
    check('AMRAP completed but rounds not captured → coverage 0, rounds_not_logged',
          before['coverage'] == {'inScope': 1, 'measured': 0, 'pct': 0.0, 'reason': 'rounds_not_logged'},
          str(before['coverage']))
    check('and status insufficient_data, not a fake number', before['status'] == 'insufficient_data')
    after = run_primitive(e, _ctx(prog, {
        '1-Friday-0': _log('2026-03-06T10:00:00+00:00', {'kb_swing': {'sets': [], 'rounds': 7}}),
        '2-Friday-0': _log('2026-03-13T10:00:00+00:00', {'kb_swing': {'sets': [], 'rounds': 9}})}))
    check('with rounds logged the series appears against target_rounds',
          [p['value'] for p in after['series']] == [7, 9] and after['expected'][0]['value'] == 8)
    check('coverage now 100%', after['coverage']['pct'] == 100.0)

    e = E('rpm', 'rate', 'wildman_kettlebell', scope={'exercises': ['kb_swing']}, rpm_target=20)
    r = run_primitive(e, _ctx(prog, {'1-Friday-0': _log('2026-03-06T10:00:00+00:00', {'kb_swing': {'sets': [
        {'setIndex': 0, 'completed': True, 'repsActual': 120, 'durationSeconds': 360}]}})}))
    check('reps per minute from a timed set (120 in 6 min = 20 rpm)', r['series'][0]['value'] == 20.0)
    check('on target', r['status'] == 'on_track')
    untimed = run_primitive(e, _ctx(prog, {'1-Friday-0': _log('2026-03-06T10:00:00+00:00',
                                                             {'kb_swing': {'sets': _sets((24, 120))}})}))
    check('reps without seconds → timed_sets_not_logged', untimed['coverage']['reason'] == 'timed_sets_not_logged')

    hold = fixture_program(weeks=1)
    hold['weeks'][0]['schedule']['Monday'][0]['exercises'].append(
        {'exercise': {'id': 'plank', 'name': 'Plank', 'movement_patterns': ['isometric']},
         'slot_role': 'core', 'slot_type': 'static_hold', 'load': {'sets': 3, 'hold_seconds': 60}})
    e = E('h', 'hold_seconds', 'atg', scope={'slot_types': ['static_hold']})
    r = run_primitive(e, _ctx(hold, {'1-Monday-0': _log('2026-03-02T10:00:00+00:00',
                                                        {'plank': {'sets': _sets((0, 1), (0, 1), hold=45) +
                                                                   [{'setIndex': 2, 'completed': True, 'durationSeconds': 75}]}})}))
    check('longest completed hold vs hold_seconds', r['series'][0]['value'] == 75 and r['expected'][0]['value'] == 60)
    check('hold is called a proxy for range', any('proxy' in ev for ev in r['evidence']))

    dist = fixture_program(weeks=1)
    dist['weeks'][0]['schedule']['Saturday'][0]['exercises'][0]['load'] = {'distance_km': 8, 'duration_minutes': 50}
    w = {'id': 'w1', 'date': '2026-03-07', 'durationMinutes': 48, 'distance': {'value': 8400, 'unit': 'm'}, 'heartRate': {}}
    e = E('d', 'distance', 'uphill_athlete', scope={'modalities': ['aerobic_base']})
    r = run_primitive(e, _ctx(dist, {}, [w], [{'importedWorkoutId': 'w1', 'sessionKey': '1-Saturday-0', 'matchConfidence': 'auto'}]))
    check('workout metres → km, with pace', r['series'][0]['value'] == 8.4 and r['series'][0]['paceMinPerKm'] == round(48 / 8.4, 2))
    check('against the prescribed km', r['expected'][0]['value'] == 8.0 and r['status'] == 'on_track')


def test_duration_and_zones() -> None:
    print('\nprimitives: duration / zone_minutes / aerobic_efficiency')
    prog = fixture_program(weeks=3)
    for wk in prog['weeks']:
        wk['schedule']['Saturday'][0]['exercises'][0]['load']['pack_load_kg'] = 12
    matched_run = {'id': 'run1', 'date': '2026-03-07', 'durationMinutes': 70, 'activityType': 'running',
                   'heartRate': {'avg': 138, 'max': 160, 'samples': _hr_samples(138, 70, '2026-03-07T09:00:00+00:00')},
                   'elevation': {'gain': 420, 'loss': 400}, 'distance': {'value': 11.2, 'unit': 'km'},
                   'gpsTrack': [{'timestamp': s['timestamp'], 'speed': 2.6 if i < 36 else 2.5}
                                for i, s in enumerate(_hr_samples(0, 70, '2026-03-07T09:00:00+00:00'))]}
    hike = {'id': 'hike', 'date': '2026-03-14', 'durationMinutes': 120, 'activityType': 'hiking',
            'heartRate': {'avg': 128, 'max': 150, 'samples': _hr_samples(128, 120, '2026-03-14T09:00:00+00:00')},
            'elevation': {'gain': 900}, 'gpsTrack': [{'timestamp': s['timestamp'], 'speed': 1.1}
                                                     for s in _hr_samples(0, 120, '2026-03-14T09:00:00+00:00')]}
    lift_with_hr = {'id': 'lift', 'date': '2026-03-02', 'durationMinutes': 60, 'activityType': 'strength',
                    'heartRate': {'avg': 110, 'max': 150, 'samples': _hr_samples(110, 60, '2026-03-02T17:00:00+00:00')}}
    matches = [{'importedWorkoutId': 'run1', 'sessionKey': '1-Saturday-0', 'matchConfidence': 'auto'},
               {'importedWorkoutId': 'hike', 'sessionKey': '2-Saturday-0', 'matchConfidence': 'auto'},
               {'importedWorkoutId': 'lift', 'sessionKey': '1-Monday-0', 'matchConfidence': 'auto'}]
    logs = {'3-Saturday-0': _log('2026-03-21T10:00:00+00:00'),      # completed, unmatched → assumed
            '1-Wednesday-0': _log('2026-03-04T10:00:00+00:00')}
    ctx = _ctx(prog, logs, [matched_run, hike, lift_with_hr], matches, today=START + timedelta(days=21),
               profile={'dateOfBirth': '1990-06-15'})

    e = E('vol', 'duration', 'uphill_athlete', scope={'modalities': ['aerobic_base']}, expected={'load_field': 'duration_minutes'})
    r = run_primitive(e, ctx)
    by_src = {p['source']: p for p in r['series']}
    check('matched sessions measured, unmatched-completed assumed',
          'workout' in by_src and by_src.get('prescribed', {}).get('assumed') is True, str([(p['source'], p['assumed']) for p in r['series']]))
    check('weekly totals separate assumed minutes', r['weeks'][2]['assumed'] == 60 and r['weeks'][0]['assumed'] == 0, str(r['weeks']))
    check('longest planned vs actual', r['longest'] == {'planned': 60.0, 'actual': 120.0})
    check('vertical metres from matched workouts', [p['value'] for p in r['vertical']] == [420.0, 900.0])
    check('pack load surfaced', r['packLoad'][0]['value'] == 12.0)
    check('coverage counts only measured sources', r['coverage'] == {'inScope': 3, 'measured': 2, 'pct': 66.7, 'reason': None}, str(r['coverage']))

    e = E('split', 'zone_minutes', 'uphill_athlete', expected={'framework_field': 'intensity_distribution'})
    ctx.frameworks['test_fw']['intensity_distribution'] = {'zone1_2_pct': 0.8, 'zone3_pct': 0.15, 'zone4_5_pct': 0.05, 'max_effort_pct': 0.0}
    r = run_primitive(e, ctx)
    wk1 = r['weeks'][0]
    check('max HR from DOB (born 1990-06-15, today 2026-03-23 → 35 → 185) when no override', r['maxHr'] == 185.0, str(r['maxHr']))
    check('a 138-bpm run at 185 max is 75% → zone1_2', wk1['zone1_2_pct'] == 70, str(wk1))
    check('a strength session WITH HR goes to max_effort, not the HR buckets (no double count)',
          wk1['max_effort_pct'] == 120 and wk1['zone1_2_pct'] + wk1['zone3_pct'] + wk1['zone4_5_pct'] == 70, str(wk1))
    check('a completed session with no HR and no strength modality is unclassified',
          r['weeks'][2]['unclassified'] == 60, str(r['weeks'][2]))
    check('per-framework deviation against the declared split',
          r['byFramework'][0]['plannedPct']['zone1_2_pct'] == 80.0 and r['byFramework'][0]['deviationPts'] is not None)
    check('coverage: 5 completed, 4 classified (the unmatched Saturday is unclassified)',
          r['coverage'] == {'inScope': 5, 'measured': 4, 'pct': 80.0, 'reason': None}, str(r['coverage']))
    check('methods recorded', r['methods'] == {'samples': 2, 'strength_minutes': 2}, str(r['methods']))

    e = E('eff', 'aerobic_efficiency', 'uphill_athlete', scope={'modalities': ['aerobic_base']})
    r = run_primitive(e, ctx)
    check('efficiency computed for the run only; the hike is skipped with a reason',
          len(r['series']) == 1 and r['series'][0]['activityType'] == 'running' and r['evidence'], str(r['evidence']))
    check('metres per beat', r['series'][0]['value'] == round((2.6 * 36 + 2.5 * 35) / 71 * 60 / 138, 3))
    check('decoupling computed and labelled', r['series'][0]['decouplingLabel'] == 'efficient', str(r['series'][0]))
    check('coverage reason when nothing has GPS+HR',
          run_primitive(e, _ctx(prog, logs, today=START + timedelta(days=21)))['coverage']['reason'] == 'no_gps_hr')

    check('max_hr_for: override wins', max_hr_for(_ctx(prog, profile={'hrConfig': {'maxHROverride': 175}, 'dateOfBirth': '1990-01-01'})) == 175.0)
    check('max_hr_for: default when nothing known', max_hr_for(_ctx(prog)) == 190.0)


def test_unlocks_benchmarks_completion_and_errors() -> None:
    print('\nprimitives: unlocks / benchmark_level / session_completion / errors')
    prog = fixture_program(weeks=3)
    logs = {f'{n}-{d}-0': _log(f'2026-03-{2 + (n-1)*7 + o:02d}T10:00:00+00:00')
            for n in (1, 2, 3) for d, o in (('Monday', 0), ('Wednesday', 2))}
    e = E('u', 'unlocks', 'starting_strength', min_sessions=2)
    r = run_primitive(e, _ctx(prog, logs, today=START + timedelta(days=20)))
    names = {x['exerciseId'] for x in r['practised']}
    check('back_squat and press practised after ≥2 sessions', {'back_squat', 'press'} <= names, str(names))
    check('cumulative series per week', [p['value'] for p in r['series']] == [2, 2, 2] or r['series'][0]['value'] <= r['series'][-1]['value'])
    avail = {a['exerciseId'] for a in r['available']}
    check('box_squat becomes available once back_squat is practised (SS requires graph)',
          'box_squat' in avail, str(sorted(avail)[:8]))
    check('front_squat stays locked: it requires more than the squat', 'front_squat' not in avail)

    perf = {'back_squat_bw_ratio': [{'value': 1.2, 'date': '2026-02-01'}, {'value': 1.55, 'date': '2026-03-10'}],
            'strict_press_bw_ratio': [{'value': 0.6, 'date': '2026-03-10'}],
            'run_3mile_minutes': [{'value': 21.0, 'date': '2026-03-01'}]}
    e = E('std', 'benchmark_level', 'starting_strength',
          benchmarks=['back_squat_bw_ratio', 'deadlift_bw_ratio', 'strict_press_bw_ratio'], target_level='intermediate')
    r = run_primitive(e, _ctx(prog, {}, perf=perf))
    rows = {b['benchmarkId']: b for b in r['benchmarks']}
    check('latest PR and its level', rows['back_squat_bw_ratio']['latest'] == 1.55 and rows['back_squat_bw_ratio']['level'] == 'intermediate')
    check('met the target on the squat, not the press (0.6 < 0.75 intermediate)',
          rows['back_squat_bw_ratio']['met'] is True and rows['strict_press_bw_ratio']['met'] is False)
    check('no PR → level None, met None', rows['deadlift_bw_ratio']['latest'] is None and rows['deadlift_bw_ratio']['met'] is None)
    check('status partial', r['status'] == 'partial')
    check('coverage 2 of 3 with PRs', r['coverage'] == {'inScope': 3, 'measured': 2, 'pct': 66.7, 'reason': None}, str(r['coverage']))
    check('gap to next level', rows['back_squat_bw_ratio']['next'] == 'advanced' and rows['back_squat_bw_ratio']['gapToNext'] == 0.45)
    e2 = E('run', 'benchmark_level', 'uphill_athlete', benchmarks=['run_3mile_minutes'], target_level='advanced')
    check('lower_is_better: 21 min meets advanced', run_primitive(e2, _ctx(prog, {}, perf=perf))['status'] == 'met')

    e = E('c', 'session_completion', 'starting_strength', scope={'modalities': ['max_strength']})
    r = run_primitive(e, _ctx(prog, logs, today=START + timedelta(days=20)))
    check('completion 100% for the scope', r['totals'] == {'planned': 6, 'completed': 6, 'pct': 100.0} and r['status'] == 'on_track')

    bad = E('boom', 'set_load', 'x', scope={'modalities': ['max_strength']}, expected='achieved_plus_increment')
    broken = _ctx(prog, {'1-Monday-0': _log('2026-03-02T10:00:00+00:00', {'back_squat': {'sets': 'not a list'}})})
    r = run_primitive(bad, broken)
    check('a primitive that raises reports status=error instead of taking the document down',
          r['status'] == 'error' and r['evidence'], str(r['evidence'])[:80])
    check('an unknown primitive is an error result too',
          run_primitive(E('z', 'nope', 'x'), _ctx(prog))['status'] == 'error')


# ── sections and the document ────────────────────────────────────────────────

from src.analytics import intensity as intensity_mod, movement as movement_mod
from src.analytics import archetypes as archetypes_mod, benchmarks as benchmarks_mod
from src.analytics.document import compute_program_analytics


def test_sections() -> None:
    print('\nsections: intensity / movement / archetypes / benchmarks')
    prog = fixture_program(weeks=3)
    for wk in prog['weeks']:
        for day in ('Monday', 'Wednesday'):
            wk['schedule'][day][0]['archetype']['slots'] = [{'role': 'primary_squat', 'intensity_pct_1rm': 0.8}]
            wk['schedule'][day][0]['archetype']['category'] = 'strength'
        wk['schedule']['Saturday'][0]['archetype']['category'] = 'conditioning'
    logs = {'1-Monday-0': _log('2026-03-02T10:00:00+00:00', {'back_squat': {'sets': _sets((100, 5), (100, 5), (100, 5))},
                                                              'press': {'sets': _sets((40, 5), (40, 5))}}),
            '1-Wednesday-0': _log('2026-03-04T10:00:00+00:00', {'back_squat': {'sets': _sets((101.25, 5), (101.25, 5), (101.25, 5))}}),
            '2-Saturday-0': _log('2026-03-14T10:00:00+00:00')}
    run = {'id': 'run1', 'date': '2026-03-07', 'durationMinutes': 66, 'activityType': 'running',
           'heartRate': {'avg': 140, 'max': 158}, 'elevation': {'gain': 200}}
    matches = [{'importedWorkoutId': 'run1', 'sessionKey': '1-Saturday-0', 'matchConfidence': 'auto'}]
    perf = {'bodyweight_kg': [{'value': 82.0, 'date': '2026-02-20'}],
            'run_3mile_minutes': [{'value': 24.0, 'date': '2026-03-01'}]}
    ctx = _ctx(prog, logs, [run], matches, perf=perf)
    ctx.frameworks['test_fw']['intensity_distribution'] = {'zone1_2_pct': 0, 'zone3_pct': 0, 'zone4_5_pct': 0, 'max_effort_pct': 1.0}
    specs = spec_mod.compose(ctx.goal)

    it = intensity_mod.build(ctx)
    check('intensity ran over every completed session', it['coverage']['inScope'] == 4, str(it['coverage']))
    check('a pure-strength split gets the %1RM view (one row per logged lift: squat, press, squat)',
          'pct1rm' in it and it['pct1rm']['sessions'] == 3, str(it.get('pct1rm', {}).get('sessions')))
    check('%1RM against the slot target', it['pct1rm']['rows'][0]['targetPct'] == 80.0
          and abs(it['pct1rm']['rows'][0]['pctOf1rm'] - round(100 / (100 * (1 + 0.0333 * 5)) * 100, 1)) < 0.2, str(it['pct1rm']['rows'][0]))

    mv = movement_mod.build(ctx, specs)
    # The fixture's press carries the squat pattern too, so the pattern counts
    # every set of both: (3+3)+3 per week × 3 elapsed weeks = 27 planned; logged
    # 3+2 (Monday) + 3 (Wednesday) = 8 done.
    check('sets table counts every completed set of every exercise carrying the pattern',
          mv['sets']['rollups']['squat'] == {'planned': 27.0, 'done': 8.0}, str(mv['sets']['rollups']))
    check('minutes table separate from sets: locomotion 60 planned × 2 elapsed Saturdays, 2 done (one assumed)',
          mv['minutes']['rollups']['locomotion'] == {'planned': 120, 'done': 120} and mv['minutes']['assumed'] == 60,
          str(mv['minutes']))
    check('default balance ratios are information, not warnings',
          all(b['level'] == 'info' and not b['declared'] for b in mv['balance']))
    check('archetype category rollup', mv['byArchetypeCategory']['strength']['plannedSessions'] == 6
          and mv['byArchetypeCategory']['conditioning']['completedSessions'] == 2, str(mv['byArchetypeCategory']))
    declared = spec_mod.Spec('starting_strength', 'declared', [], [{'a': 'hinge', 'b': 'squat', 'min': 0.5, 'max': 1.5}], True, [])
    mv2 = movement_mod.build(ctx, [declared])
    check('a declared ratio outside its band is a warning (hinge:squat = 0/6)',
          mv2['balance'][0]['level'] == 'warning' and mv2['balance'][0]['outside'], str(mv2['balance']))

    ar = archetypes_mod.build(ctx)
    rows = {r['archetypeId']: r for r in ar}
    check('archetype rows with scheduled/completed', rows['sq']['scheduled'] == 6 and rows['sq']['completed'] == 2
          and rows['z2']['completed'] == 2 and rows['z2']['matched'] == 1, str({k: (v['scheduled'], v['completed']) for k, v in rows.items()}))
    check('duration delta only from measured sessions (66 vs 45 = +46.7%)', rows['z2']['meanDurationDeltaPct'] == 46.7, str(rows['z2']['meanDurationDeltaPct']))
    check('HR profile from matched workouts', rows['z2']['hr'] == {'avg': 140, 'max': 158})
    check('lead lift est-1RM trend on the strength shape',
          rows['sq']['leadLift']['exerciseId'] == 'back_squat' and rows['sq']['leadLift']['sessions'] == 2, str(rows['sq']['leadLift']))

    bm = benchmarks_mod.build(ctx, specs)
    ids = {b['benchmarkId']: b for b in bm['benchmarks']}
    check('standards selected by philosophy source (SS) and priority domain',
          'back_squat_bw_ratio' in ids and 'philosophy' in ids['back_squat_bw_ratio']['why'], str(list(ids)[:6]))
    check('an aerobic_base standard is in via priority_modality',
          'run_3mile_minutes' in ids and 'priority_modality' in ids['run_3mile_minutes']['why'])
    check('a logged PR is levelled', ids['run_3mile_minutes']['level'] == 'intermediate' or ids['run_3mile_minutes']['levelIndex'] >= 1, str(ids['run_3mile_minutes']['level']))
    sq = ids['back_squat_bw_ratio']
    check('squat ratio derived from est-1RM ÷ bodyweight when no PR is logged',
          sq['valueSource'] == 'derived' and sq['derived']['bodyweightKg'] == 82.0
          and sq['derived']['value'] == round(round(101.25 * (1 + 0.0333 * 5), 1) / 82.0, 2), str(sq['derived']))
    check('bodyweight surfaced', bm['bodyweightKg'] == 82.0)
    ctx_nobw = _ctx(prog, logs, [run], matches, perf={})
    sq2 = {b['benchmarkId']: b for b in benchmarks_mod.build(ctx_nobw, specs)['benchmarks']}['back_squat_bw_ratio']
    check('without bodyweight the derivation says why it cannot',
          sq2['derived'] and sq2['derived']['reason'] == 'no_bodyweight_logged' and sq2['value'] is None, str(sq2['derived']))


def test_document() -> None:
    print('\nthe document')
    prog = fixture_program(weeks=3, deload_week=99)      # no deload: a plain loading week
    logs = {'1-Monday-0': _log('2026-03-02T10:00:00+00:00', {'back_squat': {'sets': _sets((100, 5))}})}
    inputs = AnalyticsInputs(prog, START, TODAY, logs, [], [], {}, [], {'dateOfBirth': '1990-06-15'})
    doc = compute_program_analytics(inputs, load={'pmc': [{'date': '2026-03-18', 'ctl': 30, 'atl': 45, 'tsb': -15}],
                                                  'readiness': {'score': 61}}, frameworks=TEST_FW)
    for key in ('frame', 'scorecard', 'intensity', 'methodologies', 'progress', 'movement', 'archetypes', 'benchmarks', 'load'):
        check(f'section {key} present and not errored', key in doc and not (isinstance(doc[key], dict) and doc[key].get('error')),
              str(doc.get(key))[:120])
    check('one methodology, its declared spec, with its declared headline', doc['methodologies'][0]['philosophy'] == 'starting_strength'
          and doc['methodologies'][0]['analytics'] == 'declared' and doc['methodologies'][0]['headlineId'] == 'bar_load')
    check('progress entries carry their philosophy and primitive', doc['progress'][0]['primitive'] == 'set_load'
          and doc['progress'][0]['philosophy'] == 'starting_strength')
    check('load is reframed by phase: TSB −15 in a base block is loading_as_expected',
          doc['load']['reading'] == 'loading_as_expected' and doc['load']['phase'] == 'base', str(doc['load']))
    taper = fixture_program(weeks=3)
    for wk in taper['weeks']:
        wk['phase'] = 'taper'
    doc2 = compute_program_analytics(AnalyticsInputs(taper, START, TODAY), load={'pmc': [{'tsb': -15, 'ctl': 30, 'atl': 45}]}, frameworks=TEST_FW)
    check('the same TSB in a taper is a flag', doc2['load']['reading'] == 'still_fatigued_in_recovery')
    check('frame knows the taper is a deload', doc2['frame']['phase']['isDeload'])
    check('no load inputs → reading None, no crash', compute_program_analytics(AnalyticsInputs(prog, START, TODAY),
                                                                                frameworks=TEST_FW)['load']['reading'] is None)
    check('a PMC that never saw a workout reads no_load_data, not fresh',
          compute_program_analytics(AnalyticsInputs(prog, START, TODAY), load={'pmc': [{'tsb': 0, 'ctl': 0, 'atl': 0, 'trimp': 0}]},
                                    frameworks=TEST_FW)['load']['reading'] == 'no_load_data')


# ── API boundary: routing and fatigue normalisation ──────────────────────────

def test_notes_route_and_fatigue() -> None:
    print('\napi: the iOS notes route, and fatigue on one scale')
    import os
    os.environ.setdefault('SUPABASE_URL', '')
    import api
    adapter = api.app.url_map.bind('localhost')
    ep, args = adapter.match('/api/health/sessions/1-Monday-0/notes', method='PUT')
    check('…/notes reaches the notes handler, not the <path:> catch-all',
          ep == 'health_upsert_session_notes' and args == {'session_key': '1-Monday-0'}, f'{ep} {args}')
    ep2, _ = adapter.match('/api/health/sessions/1-Monday-0', method='PUT')
    check('the plain route still works', ep2 == 'health_upsert_session')
    check('iOS fatigue 8/10 → 4/5', api._normalise_fatigue({'fatigueRating': 8})['fatigueRating'] == 4)
    check('a web 3/5 is untouched', api._normalise_fatigue({'fatigueRating': 3})['fatigueRating'] == 3)
    check('snake_case body is accepted and folded', api._normalise_fatigue({'fatigue_rating': 10}) == {'fatigueRating': 5})
    check('benchmarks endpoint keeps sources and goal relevance now',
          all('sources' in b and 'goalRelevance' in b for b in api._all_benchmarks())
          and 'starting_strength' in {s for b in api._all_benchmarks() for s in b['sources']})


def test_describe() -> None:
    print('\nspecs, described for the Explore tab')
    from src.analytics import describe, spec, vocabulary
    check('every primitive has a vocabulary entry',
          set(vocabulary.PRIMITIVES) == set(spec.PRIMITIVES),
          str(set(vocabulary.PRIMITIVES) ^ set(spec.PRIMITIVES)))
    check('every need a primitive names is defined',
          all(n in vocabulary.NEEDS for p in vocabulary.PRIMITIVES.values() for n in p['needs']))
    doc = describe.describe_all()
    from src import loader
    check('every package is described', set(doc['philosophies']) == {p['id'] for p in loader.load_philosophies()})
    ss = doc['philosophies']['starting_strength']
    check('SS is declared, from its file', ss['source'] == 'declared'
          and ss['file'] == 'data/packages/starting_strength/analytics.yaml')
    check('SS headline is bar_load', ss['headlineId'] == 'bar_load')
    bar = ss['progress'][0]
    check('scope ids resolve to names', bar['scope']['modalities'] == [{'id': 'max_strength', 'name': 'Max Strength'}])
    check('expected is normalised', bar['expected'] == {'kind': 'achieved_plus_increment'})
    check('stall 3 sessions / 1 %', bar['stall'] == {'sessions': 3, 'tolerancePct': 1.0})
    novice = ss['progress'][1]
    check('benchmark names resolve on the entry',
          [b['name'] for b in novice['benchmarks']][0].startswith('Back Squat') and novice['targetLevel'] == 'intermediate')
    why = {b['id']: b['why'] for b in ss['benchmarks']}
    check('benchmark provenance: declared > entry > source',
          why['bench_press_bw_ratio'] == 'declared' and why['back_squat_bw_ratio'] == 'entry'
          and why['pull_up_reps'] == 'source', str(why))
    check('SS declares no balance → defaults, flagged information-only',
          ss['movement']['declared'] is False and ss['movement']['balance'] == spec.DEFAULT_BALANCE)
    check('needs are unioned per field', [n['field'] for n in ss['needs']] == ['sets', 'prs'])

    up = doc['philosophies']['uphill_athlete']
    me = next(e for e in up['progress'] if e['id'] == 'muscular_endurance')
    check('framework scope resolves to two phase names',
          [f['id'] for f in me['scope']['frameworks']] == ['uphill_base_phase', 'uphill_specific_phase']
          and all(f['name'].startswith(('Base', 'Specific')) for f in me['scope']['frameworks']))
    check('load_field expectation', me['expected'] == {'kind': 'load_field', 'field': 'duration_minutes'})
    split = next(e for e in up['progress'] if e['id'] == 'intensity_split')
    check('framework_field expectation', split['expected'] == {'kind': 'framework_field', 'field': 'intensity_distribution'})

    wk = doc['philosophies']['wildman_kettlebell']
    jerk = next(e for e in wk['progress'] if e['id'] == 'jerk_rpm')
    check('rpm target and exercise name', jerk['rpmTarget'] == 20
          and jerk['scope']['exercises'][0]['id'] == 'kb_jerk_single')
    check('Wildman needs timed reps and hold-free', 'timed_reps' in {n['field'] for n in wk['needs']})

    mf = doc['philosophies']['marcus_filly']
    check('a package with no file is default, file None', mf['source'] == 'default' and mf['file'] is None)
    check('default entries carry synthesised labels', all(e['source'] == 'default' for e in mf['progress']))

    declared = {'id': '_zz_test', 'progress': [
        {'id': 'my_metric', 'label': 'My metric', 'primitive': 'rounds',
         'scope': {'modalities': ['aerobic_base']}, 'expected': {'constant': 5, 'unit': 'rounds'},
         'headline': True}]}
    with throwaway_package('_zz_test', declared):
        d2 = describe.describe_all()['philosophies'].get('_zz_test')
        check('a new package with analytics.yaml is described with no src/ change',
              d2 is not None and d2['source'] == 'declared'
              and d2['progress'][0]['expected'] == {'kind': 'constant', 'value': 5, 'unit': 'rounds'}
              and d2['needs'][0]['field'] == 'rounds', str(d2))
    check('and is gone once removed', '_zz_test' not in describe.describe_all()['philosophies'])


if __name__ == '__main__':
    test_families()
    test_zones()
    test_trend()
    test_spec_defaults()
    test_spec_declared_overrides_default()
    test_spec_provenance()
    test_spec_compose_and_scope()
    test_context()
    test_frame()
    test_scorecard()
    test_set_load()
    test_load_at_rpe()
    test_rounds_rate_hold_distance()
    test_duration_and_zones()
    test_unlocks_benchmarks_completion_and_errors()
    test_sections()
    test_document()
    test_notes_route_and_fatigue()
    test_describe()
    if _failures:
        print(f'\n{len(_failures)} failure(s): ' + ', '.join(_failures))
        sys.exit(1)
    print('\nAll program analytics tests passed.')
