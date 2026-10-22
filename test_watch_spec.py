"""Packages own their watch screens: the vocabulary, the resolver, the payload.

- every package x archetype x slot resolves to a spec the vocabulary knows,
  with a LAP its template allows;
- the slot-type defaults are the screens the watch drew by slot_type before
  packages owned them (the regression table below is the old
  ExerciseScreen.build + renderer mapping);
- the declared overrides land where they are scoped (archetype + slot role);
- a throwaway package with its own watch.yaml reaches the today-session
  payload with no change to src/ or the watch's core;
- a borrowed session shows its owner's screens;
- one session's screens stay small enough for the watch;
- the watch's generated Vocab.mc and the demo programmes are current, and
  garmin/core names no package or archetype.

No database. Run: SUPABASE_URL='' .venv/bin/python test_watch_spec.py
"""
import contextlib
import json
import os
import shutil
import sys
from pathlib import Path

import yaml

os.environ.setdefault('SUPABASE_URL', '')

from src import loader, watch_spec  # noqa: E402

failures: list = []


def check(name, cond, detail=''):
    if not cond:
        failures.append(f'{name} {detail}'.strip())
    print(('  ok   ' if cond else '  FAIL ') + name + (f'  [{detail}]' if detail and not cond else ''))


# What the watch drew per slot type before packages owned their screens.
OLD_RENDERERS = {
    'sets_reps':      ('sets',     'reps',             'rpe_or_set',      'set',            'complete_set'),
    'static_hold':    ('hold',     'hold',             'set',             'hold',           'toggle_hold'),
    'emom':           ('interval', 'interval',         'interval_left',   'interval_round', 'skip'),
    'amrap':          ('rounds',   'rounds',           'cap_left',        'rounds',         'log_round'),
    'amrap_movement': ('rounds',   'rounds',           'cap_left',        'rounds',         'log_round'),
    'for_time':       ('for_time', 'rounds_of_target', 'elapsed',         'rounds_of_target', 'log_round'),
    'distance':       ('distance', 'distance',         'distance_target', 'distance',       'log_round'),
    'time_domain':    ('timed',    'time_left',        'zone_or_time',    'time_left',      'skip'),
    'skill_practice': ('timed',    'time_left',        'zone_or_time',    'time_left',      'skip'),
}


def test_defaults():
    print('\ndefaults reproduce the slot-type renderers')
    for slot_type, (tpl, a, b, gauge, lap) in OLD_RENDERERS.items():
        s = watch_spec.resolve(None, None, None, slot_type)
        got = (s['template'], s['a'], s['b'], s['gauge'], s['lap'])
        check(f'{slot_type}', got == (tpl, a, b, gauge, lap), f'{got}')
    s = watch_spec.resolve(None, None, None, 'something_new')
    check('an unknown slot type falls back to the timed block', s['template'] == 'timed')


def test_every_slot_resolves():
    print('\nevery package x archetype x slot resolves cleanly')
    errors, count, biggest = [], 0, (0, '')
    for arch in loader.load_all_archetypes():
        pkg = arch.get('_package')
        slots = [(s.get('role'), s.get('slot_type')) for s in arch.get('slots') or []]
        for role, slot_type in slots:
            count += 1
            spec = watch_spec.resolve(pkg, arch['id'], role, slot_type)
            errors += watch_spec.resolved_errors(spec, f"{pkg}/{arch['id']}.{role}")
        table, keys = watch_spec.session_screens(pkg, arch['id'], slots)
        size = len(json.dumps({'watch': watch_spec.session_identity(pkg), 'screens': table},
                              separators=(',', ':')))
        if size > biggest[0]:
            biggest = (size, arch['id'])
        if keys and set(keys) != set(table):
            errors.append(f"{arch['id']}: keys {keys} vs table {sorted(table)}")
    check(f'{count} slots, no vocabulary errors', not errors, '; '.join(errors[:5]))
    check('one session\'s screens fit in 1.5 KB of JSON', biggest[0] <= 1536,
          f'{biggest[1]}: {biggest[0]} bytes')


def test_declared_overrides():
    print('\ndeclared overrides are scoped to archetype + slot role')
    r = watch_spec.resolve
    tgu = r('gym_jones', 'gj_of_d04', 'get_ups', 'sets_reps')
    check('Gym Jones get-ups count toward 100, per side',
          tgu['a'] == 'cumulative' and tgu['behaviours'] == {'side_tracked': True, 'cumulative_target': 100})
    ladder = r('gym_jones', 'gj_of_d17', 'ladder', 'time_domain')
    swings = r('gym_jones', 'gj_of_d17', 'practice', 'sets_reps')
    check('the ladder counts rungs, LAP logging each',
          ladder['a'] == 'rung' and ladder['lines'] == 'ladder_total' and ladder['lap'] == 'log_round')
    check('...its warm-up swings stay plain sets', swings['a'] == 'reps' and 'behaviours' not in swings)
    bjj = [r('bjj', 'bjj_class', role, t) for role, t in
           [('warm_up', 'time_domain'), ('technique_drilling', 'skill_practice')]]
    check('a BJJ class is a round timer on every block, with its fields',
          all(s['template'] == 'round_timer' and s['a'] == 'block_left' for s in bjj))
    tgu = r('wildman_kettlebell', 'tgu_practice', 'main', 'skill_practice')
    check('the Wildman get-up block switches sides on LAP and shows the side',
          tgu['template'] == 'timed' and tgu['lap'] == 'next_side' and 'side' in tgu['title'])
    inert = dict(r(None, None, None, 'time_domain'), behaviours={'side_tracked': True})
    check('side_tracked on a step that never alternates is an error',
          any('never alternates' in e for e in watch_spec.resolved_errors(inert, 'x')))
    check('a package with no watch.yaml gets the defaults',
          r('starting_strength', 'anything', 'primary_squat', 'sets_reps')
          == watch_spec.resolve(None, None, None, 'sets_reps'))
    ident = watch_spec.session_identity('starting_strength')
    check('...and its philosophy\'s name as the label', bool(ident['label']), str(ident))


_PKG_ROOT = Path(__file__).parent / 'data' / 'packages'


@contextlib.contextmanager
def throwaway_package(pkg_id: str):
    """A package that exists only for this test: one archetype, one watch.yaml."""
    root = _PKG_ROOT / pkg_id
    if root.exists():
        shutil.rmtree(root)
    (root / 'archetypes' / 'max_strength').mkdir(parents=True)
    (root / 'philosophy.yaml').write_text(yaml.safe_dump({
        'id': pkg_id, 'name': 'Throwaway Method', 'core_principles': ['test'],
        'scope': ['max_strength'], 'bias': ['max_strength'], 'self_contained': True}))
    (root / 'archetypes' / 'max_strength' / f'{pkg_id}_day.yaml').write_text(yaml.safe_dump({
        'id': f'{pkg_id}_day', 'name': 'Throwaway Day', 'modality': 'max_strength',
        'slots': [{'role': 'main_lift', 'slot_type': 'sets_reps', 'sets': 5, 'reps': 5},
                  {'role': 'finisher', 'slot_type': 'static_hold', 'sets': 3}]}))
    (root / 'watch.yaml').write_text(yaml.safe_dump({
        'id': pkg_id, 'spec_version': 1,
        'identity': {'label': 'Throwaway', 'accent': 'violet'},
        'archetypes': {f'{pkg_id}_day': {'slots': {'main_lift': {
            'a': 'cumulative', 'behaviours': {'cumulative_target': 25}}}}},
        'summary': {'pages': ['summary', 'exercises']}}))
    watch_spec.clear_cache()
    try:
        yield root
    finally:
        shutil.rmtree(root, ignore_errors=True)
        watch_spec.clear_cache()


def _assignment(role, slot_type, **load):
    return {'slot_role': role, 'slot_type': slot_type, 'load': load,
            'exercise': {'id': f'{role}_ex', 'name': role.title()}}


def test_throwaway_package_reaches_the_payload():
    print('\na new package with a watch.yaml reaches the watch, no core change')
    import api
    pkg = '_zz_watch_test'
    with throwaway_package(pkg):
        session = {'modality': 'max_strength',
                   'archetype': {'id': f'{pkg}_day', 'name': 'Throwaway Day'},
                   'exercises': [_assignment('main_lift', 'sets_reps', sets=5, reps=5),
                                 _assignment('finisher', 'static_hold', sets=3, hold_seconds=30)]}
        out = api.encode_watch_session(session, '1-Monday-0', spec_level=1)
        check('packageId is the archetype\'s package', out.get('packageId') == pkg, str(out.get('packageId')))
        check('identity from its watch.yaml',
              out['watch']['label'] == 'Throwaway' and out['watch']['accent'] == 'violet')
        check('summary pages from its watch.yaml', out['watch']['summary']['pages'] == ['summary', 'exercises'])
        main, fin = out['exercises']
        check('each exercise names a screen in the table',
              main['screen'] in out['screens'] and fin['screen'] in out['screens'])
        check('the main lift counts toward 25', out['screens'][main['screen']]['a'] == 'cumulative'
              and out['screens'][main['screen']]['behaviours'] == {'cumulative_target': 25})
        check('the finisher keeps the hold default', out['screens'][fin['screen']]['template'] == 'hold')

        legacy = api.encode_watch_session(session, '1-Monday-0')
        check('without spec the session has no spec keys',
              not ({'packageId', 'watch', 'screens'} & set(legacy))
              and all('screen' not in e for e in legacy['exercises']))


def test_borrowed_session_shows_its_owner():
    print('\na borrowed session shows its owner\'s screens')
    import api
    session = {'modality': 'combat_sport',
               'archetype': {'id': 'bjj_class', 'name': 'BJJ Class'},
               'provenance': {'package': 'bjj', 'borrowed': True},
               'exercises': [{'slot_role': 'free_rolling', 'slot_type': 'time_domain', 'meta': True,
                              'load': {'duration_minutes': 25}}]}
    out = api.encode_watch_session(session, '1-Monday-0', spec_level=1)
    check('packageId is bjj', out['packageId'] == 'bjj')
    check('the round timer comes with it',
          out['screens'][out['exercises'][0]['screen']]['template'] == 'round_timer')
    session['archetype'] = {'id': 'gone_from_the_library'}
    out = api.encode_watch_session(session, '1-Monday-0', spec_level=1)
    check('an unknown archetype falls back to the provenance tag', out['packageId'] == 'bjj')


def test_a_test_step_says_its_standard():
    print('\na test step carries its standard, and its screen shows it')
    import api
    session = {'modality': 'conditioning',
               'archetype': {'id': 'gym_jones_row_2k_test', 'name': '2 km Row — Test'},
               'exercises': [
                   {'slot_role': 'warm_up', 'slot_type': 'time_domain',
                    'exercise': {'id': 'row_easy', 'name': 'Easy Row'}, 'load': {'duration_minutes': 10}},
                   {'slot_role': 'row_2k', 'slot_type': 'for_time',
                    'exercise': {'id': 'row_2km_test', 'name': '2000m Row Time Trial'},
                    'load': {'distance_km': 2.0, 'test': True},
                    'standard': {'id': 'row_2km_minutes', 'result': 'duration'}}]}
    out = api.encode_watch_session(session, '1-Friday-0', spec_level=1)
    warm, row = out['exercises']
    check('the scored slot names its standard, its kind and the entry number before a first result',
          row.get('standard') == {'id': 'row_2km_minutes', 'name': '2km Row', 'result': 'duration',
                                  'target': '10:00 for entry'}, str(row.get('standard')))
    check('its screen shows the standard', out['screens'][row['screen']]['lines'] == 'standard_target')
    check('the warm-up neither', 'standard' not in warm and out['screens'][warm['screen']]['lines'] != 'standard_target')
    results = {'row_2km_minutes': {
        'current': {'valueText': '7:45', 'next': 'advanced', 'nextText': '7:00'},
        'best': {'valueText': '7:32'}}}
    out = api.encode_watch_session(session, '1-Friday-0', spec_level=1, results=results)
    std = out['exercises'][1]['standard']
    check('with results: the best, and the number for the next level',
          std.get('best') == '7:32' and std.get('target') == '7:00 for advanced', str(std))
    legacy = api.encode_watch_session(session, '1-Friday-0')
    check('without spec there is no standard (builds before 1.4 parse the payload key for key)',
          all('standard' not in e and '_standard' not in e for e in legacy['exercises']))


def test_watch_side_is_current():
    print('\nthe watch reads the same tables')
    import subprocess
    py = sys.executable
    for args, name in [
        ([py, 'garmin/tools/gen_vocab.py', '--check'],
         'Vocab.mc and WatchVocab.swift are generated from the current vocabulary'),
        ([py, 'garmin/tools/gen_spec_fixtures.py', '--check'],
         'SpecFixtures.mc runs the current data/watch_fixtures.json (as WatchSpecTests does)'),
        ([py, 'garmin/tools/gen_registry.py', '--check'], 'Registry.mc and packages.jungle list the package modules'),
        ([py, 'garmin/tools/gen_watch_demo.py', '--check'], 'the demo programmes carry their packages\' current specs'),
        ([py, 'garmin/tools/check_core_neutral.py'], 'garmin/core names no package or archetype'),
    ]:
        r = subprocess.run(args, cwd=os.path.dirname(os.path.abspath(__file__)),
                           capture_output=True, text=True)
        check(name, r.returncode == 0, (r.stdout + r.stderr).strip()[-300:])


# The IKMF pentathlon's five single-bell events and the reps that score at most
# in six minutes (ikmf-world.com/disciplines/ikmf-pentathlon).
IKMF_CAPS = {'clean': 120, 'long_cycle_press': 60, 'jerk': 120,
             'half_snatch': 108, 'strict_push_press': 120}


def test_pentathlon_pace():
    print('\nthe pentathlon is paced from the IKMF caps, never a default')
    import api
    from src import progression, selector
    exercises, _ = loader.load_all_exercises()
    arch = next(a for a in loader.load_all_archetypes() if a['id'] == 'kb_pentathlon_training')
    main = next(s for s in arch['slots'] if s['role'] == 'main')
    ids = main['exercise_filter']['exercise_ids']
    events = {exercises[i]['competition_pace']['event']: exercises[i]['competition_pace']
              for i in ids if (exercises.get(i) or {}).get('competition_pace')}
    check('the main slot draws the five IKMF events',
          len(ids) == 5 and {e: p['max_reps'] for e, p in events.items()} == IKMF_CAPS, str(events))
    check('the main slot is paced', main.get('paced') is True)
    check('the full snatch cannot fill it',
          not selector._matches_slot_filter(exercises['wk_kb_snatch'], main['exercise_filter'], set()))

    jerk = exercises['kb_jerk_single']
    load = progression.calculate_load(jerk, main, 'linear_load', 1, 'build', 'intermediate', False, 60)
    check('a paced jerk set is 20 RPM', load.get('target_rpm') == 20, str(load))
    lcp = progression.calculate_load(exercises['wk_kb_long_cycle_press'], main, 'linear_load',
                                     1, 'build', 'intermediate', False, 60)
    check('a paced long cycle press is 10 RPM', lcp.get('target_rpm') == 10, str(lcp))
    unpaced = dict(main, paced=False)
    check('an unpaced slot carries no pace',
          'target_rpm' not in progression.calculate_load(jerk, unpaced, 'linear_load', 1, 'build',
                                                          'intermediate', False, 60))

    out = api.encode_watch_session(
        {'modality': 'strength_endurance', 'archetype': {'id': 'kb_pentathlon_training'},
         'exercises': [{'slot_role': 'main', 'slot_type': 'time_domain', 'exercise': jerk,
                        'load': load}]}, '1-Monday-0', spec_level=1)
    ex = out['exercises'][0]
    check('the watch gets targetRpm', ex.get('targetRpm') == 20, str(ex.get('targetRpm')))
    spec = out['screens'][ex['screen']]
    check('the screen shows the pace and has no flat default',
          spec.get('b') == 'rpm' and 'metronome_rpm' not in (spec.get('behaviours') or {}), str(spec))


def test_server_fields_both_watches_use():
    print('\na hand switch, a rest that ends on heart rate and double bells reach both watches')
    import api
    from src import progression
    from src.standard_tests import protocol_load
    exercises, _ = loader.load_all_exercises()
    archetypes = {a['id']: a for a in loader.load_all_archetypes()}

    # The data: where each field may stand.
    for arch in archetypes.values():
        for slot in arch.get('slots') or []:
            where = f"{arch['id']}.{slot.get('role')}"
            if slot.get('rest_until_hr_pct'):
                check(f'{where}: an HR-gated rest is an interval with a cap',
                      slot.get('slot_type') == 'emom' and slot.get('work_sec') and slot.get('rest_sec'),
                      str(slot))
            if slot.get('switch_at_sec'):
                work = slot.get('work_sec') or (slot.get('duration_minutes') or 0) * 60
                check(f'{where}: the hand switch falls inside the work',
                      0 < slot['switch_at_sec'] < work, f"{slot['switch_at_sec']} of {work}")
    doubles = [i for i, e in exercises.items()
               if e.get('category') == 'kettlebell' and ('double' in i.split('_'))]
    check('every double-kettlebell exercise says it holds two bells',
          doubles and all(exercises[i].get('bells') == 2 for i in doubles),
          str({i: exercises[i].get('bells') for i in doubles}))

    # The load: carried there, because the slot does not survive storage.
    ag = archetypes['kb_antiglycolic_session']['slots'][0]
    swing = exercises['wk_kb_half_snatch']
    load = progression.calculate_load(swing, ag, 'time_to_task', 1, 'base', 'intermediate', False, 60)
    check('an HR-gated interval carries its share of max HR and its zone',
          load.get('rest_until_hr_pct') == 68 and load.get('zone_lower') == 1 and load.get('zone_upper') == 2
          and load.get('target_rounds') == 20 and load.get('work_sec') == 15 and load.get('rest_sec') == 90,
          str(load))
    check('and plans the minutes it did as a timed block', load.get('time_minutes') == 35, str(load))
    tabata = progression.calculate_load(swing, {'slot_type': 'emom', 'sets': 8, 'work_sec': 20,
                                                'rest_sec': 10, 'intensity': 'max'},
                                        'time_to_task', 1, 'base', 'intermediate', False, 60)
    check('an interval on the clock is as it was',
          'rest_until_hr_pct' not in tabata and 'zone_lower' not in tabata, str(tabata))
    def rounds(phase, week=1, cap=60, slot=ag):
        return progression.calculate_load(swing, slot, 'time_to_task', week, phase, 'intermediate',
                                          False, cap).get('target_rounds')
    check('its rounds are a volume: they come down in a taper and build in a peak, as minutes do',
          (rounds('taper'), rounds('peak'), rounds('peak', week=4)) == (12, 20, 26),
          str((rounds('taper'), rounds('peak'), rounds('peak', week=4))))
    check('within the session limit', rounds('peak', week=4, cap=30) == 17, str(rounds('peak', week=4, cap=30)))
    tabata_slot = {'slot_type': 'emom', 'sets': 8, 'work_sec': 20, 'rest_sec': 10, 'intensity': 'max'}
    check('a protocol keeps its rounds', rounds('taper', slot=tabata_slot) == 8, str(rounds('taper', slot=tabata_slot)))
    gated_sets = progression.calculate_load(swing, {'slot_type': 'sets_reps', 'sets': 3, 'reps': 5,
                                                    'rest_sec': 90, 'rest_until_hr_pct': 68},
                                            'linear_load', 1, 'base', 'intermediate', False, 60)
    check('only an interval rest is gated', 'rest_until_hr_pct' not in gated_sets, str(gated_sets))
    test = archetypes['kb_pentathlon_test']
    event = next(s for s in test['slots'] if s['role'] == 'half_snatch')
    tload = protocol_load(swing, event)
    check('a test event carries its hand switch, as written',
          tload.get('switch_at_sec') == 180 and tload.get('duration_minutes') == 6 and tload.get('test'),
          str(tload))

    # The payload: bpm on the athlete's max HR, keys only where they apply.
    def encode(ea, max_hr=None, arch='kb_antiglycolic_session'):
        return api.encode_watch_session({'modality': 'aerobic_base', 'archetype': {'id': arch},
                                         'exercises': [ea]}, '1-Monday-0', spec_level=1,
                                        max_hr=max_hr)['exercises'][0]
    ex = encode({'slot_role': 'main', 'slot_type': 'emom', 'exercise': swing, 'load': load}, max_hr=185)
    check('restUntilHr is the share of the athlete\'s max HR', ex.get('restUntilHr') == 126, str(ex.get('restUntilHr')))
    check('the load says it', ex.get('loadDescription') == '20 x 15s, rest to HR 126', str(ex.get('loadDescription')))
    check('the work shows its zone', (ex.get('prescribedZoneLower'), ex.get('prescribedZoneUpper')) == (1, 2))
    ex = encode({'slot_role': 'main', 'slot_type': 'emom', 'exercise': swing, 'load': load})
    check('without a max HR, the shared default\'s', ex.get('restUntilHr') == 129, str(ex.get('restUntilHr')))
    ex = encode({'slot_role': 'half_snatch', 'slot_type': 'time_domain', 'exercise': swing, 'load': tload},
                arch='kb_pentathlon_test')
    check('switchAtSec reaches the watch', ex.get('switchAtSec') == 180, str(ex))
    check('and the load says it', (ex.get('loadDescription') or '').startswith('6 min, switch at 3:00'),
          str(ex.get('loadDescription')))
    out = api.encode_watch_session({'modality': 'strength_endurance', 'archetype': {'id': 'kb_pentathlon_test'},
                                    'exercises': [{'slot_role': 'half_snatch', 'slot_type': 'time_domain',
                                                   'exercise': swing, 'load': tload}]},
                                   '1-Monday-0', spec_level=1)
    spec = out['screens'][out['exercises'][0]['screen']]
    check('a timed block\'s title shows the hand', 'switch_side' in (spec.get('title') or []), str(spec))
    press = dict(exercises['kb_press_double'])
    check('a double sends bells', encode({'slot_role': 'main', 'slot_type': 'sets_reps', 'exercise': press,
                                          'load': {'sets': 5, 'reps': 5, 'weight_kg': 16}}).get('bells') == 2)
    press.pop('bells')
    check('even from a program stored before the field (the library\'s)',
          encode({'slot_role': 'main', 'slot_type': 'sets_reps', 'exercise': press,
                  'load': {'sets': 5, 'reps': 5, 'weight_kg': 16}}).get('bells') == 2)
    plain = encode({'slot_role': 'main', 'slot_type': 'sets_reps', 'exercise': exercises['kb_press_single']
                    if 'kb_press_single' in exercises else swing, 'load': {'sets': 5, 'reps': 5}})
    check('and nothing is sent where nothing applies',
          not ({'bells', 'switchAtSec', 'restUntilHr'} & set(plain)), str(sorted(plain)))

    # A generated program: the sessions the packages now write this way.
    from src import goals
    from src.generator import generate
    from src.progression import calculate_load
    frameworks = list(loader.load_all_frameworks().values())
    goal = goals.philosophy_to_goal('wildman_kettlebell', frameworks, track_id='pentathlon')
    events = sorted({e for m in goal['training_contract']['modules'] for e in m.get('requires_mastery') or []})
    prog = generate(goal_id=goal['id'], goal_dict=goal, num_weeks=12, output_format='dict', constraints={
        'days_per_week': 5, 'session_time_minutes': 75, 'training_level': 'advanced',
        'equipment': ['kettlebell', 'open_space'], 'injury_flags': [], 'periodization_week': 1,
        'fatigue_state': 'normal', 'mastered_exercises': events})
    sessions = [s for w in prog['weeks'] for ss in w['schedule'].values() for s in ss]
    test_s = next((s for s in sessions if (s.get('archetype') or {}).get('id') == 'kb_pentathlon_test'), None)
    check('Pentathlon Prep schedules its test', test_s is not None, str(len(sessions)))
    # Pentathlon Prep schedules no anti-glycolytic work (kettlebell sport needs its
    # glycolytic capacity); the archetype is still the package's, so its slot is
    # prescribed here as the generator would.
    ag_arch = next(a for a in loader.load_all_data()['archetypes'] if a['id'] == 'kb_antiglycolic_session')
    ag_slot = ag_arch['slots'][0]
    ag_s = {'modality': 'aerobic_base', 'archetype': ag_arch, 'exercises': [{
        'slot_role': ag_slot['role'], 'slot_type': ag_slot['slot_type'], 'exercise': swing, 'slot': ag_slot,
        'load': calculate_load(swing, ag_slot, 'density', 1, 'base', 'advanced', False)}]}
    if ag_s and test_s:
        main_ex = [e for e in api.encode_watch_session(ag_s, 'k', max_hr=180)['exercises'] if e['slotRole'] == 'main']
        check('its anti-glycolytic rest waits for the heart rate',
              main_ex and main_ex[0].get('restUntilHr') == 122, str(main_ex))
        events = [e for e in api.encode_watch_session(test_s, 'k')['exercises'] if e.get('switchAtSec')]
        check('its test switches hands at 3:00 in all five events',
              len(events) == 5 and all(e['switchAtSec'] == 180 for e in events), str(len(events)))


def main() -> int:
    test_defaults()
    test_every_slot_resolves()
    test_declared_overrides()
    test_throwaway_package_reaches_the_payload()
    test_borrowed_session_shows_its_owner()
    test_pentathlon_pace()
    test_server_fields_both_watches_use()
    test_a_test_step_says_its_standard()
    test_watch_side_is_current()
    print()
    print('ok' if not failures else f'{len(failures)} failure(s)')
    return 0 if not failures else 1


if __name__ == '__main__':
    sys.exit(main())
