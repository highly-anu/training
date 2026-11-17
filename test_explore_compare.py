"""Explore ▸ Philosophies ▸ Compare: GET /api/philosophies/compare
(src/explore_compare.py) on the shipped packages.

    SUPABASE_URL='' .venv/bin/python test_explore_compare.py
    SUPABASE_URL='' .venv/bin/python test_explore_compare.py --write   # after a shape change

`data/philosophy_compare_fixture.json` is the route's answer for three
philosophies and their for-me columns on a fixed profile: the web's
ExploreCompare.test.tsx and the phone's PhilosophyCompareTests read it, and
`Fixture` fails here when the routes stop answering it.
"""
from __future__ import annotations

import os
import sys
import unittest

os.environ.setdefault('SUPABASE_URL', '')
os.environ.setdefault('DATABASE_URL', '')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from src import explore_compare as ec  # noqa: E402
from src.explore_philosophy import glance_all  # noqa: E402


class ParseIds(unittest.TestCase):
    def test_order_kept_and_duplicates_dropped(self):
        self.assertEqual(ec.parse_ids(' b,a, b ,'), ['b', 'a'])

    def test_one_or_four_is_refused(self):
        for raw in (None, '', 'a', 'a,a', 'a,b,c,d'):
            with self.assertRaises(ec.CompareError) as err:
                ec.parse_ids(raw)
            self.assertEqual(err.exception.status, 422, raw)


class Partition(unittest.TestCase):
    def test_shared_in_first_order_alone_by_owner_and_the_rest_with_holders(self):
        out = ec._partition({'a': [3, 1, 2, 5], 'b': [2, 3, 4, 5], 'c': [3, 2]})
        self.assertEqual(out['shared'], [3, 2])
        self.assertEqual(out['only'], {'a': [1], 'b': [4], 'c': []})
        self.assertEqual(out['some'], [{'item': 5, 'ids': ['a', 'b']}])

    def test_two_lists_have_no_some(self):
        self.assertEqual(ec._partition({'a': [1, 2], 'b': [2, 2]}),
                         {'shared': [2], 'only': {'a': [1], 'b': []}, 'some': []})

    def test_intensity_tolerance(self):
        self.assertTrue(ec._intensity_same([{'z': 0.70, 'm': 0.30}, {'z': 0.74, 'm': 0.26}]))
        self.assertFalse(ec._intensity_same([{'z': 0.70, 'm': 0.30}, {'z': 0.80, 'm': 0.20}]))
        self.assertTrue(ec._intensity_same([{}, {}]))
        self.assertFalse(ec._intensity_same([{'z': 1.0}, {}]))


class Document(unittest.TestCase):
    IDS = ['uphill_athlete', 'gym_jones', 'starting_strength']

    def setUp(self):
        self.doc = ec.compare(self.IDS)
        self.glances = {g['id']: g for g in glance_all()}

    def test_columns_in_the_order_asked_with_their_method_words(self):
        self.assertEqual([g['id'] for g in self.doc['philosophies']], self.IDS)
        for g in self.doc['philosophies']:
            self.assertEqual(g['mix'], self.glances[g['id']]['mix'])
            self.assertIn('intensity', g['models'])
            self.assertIn('progression', g['models'])

    def test_every_pair_once_with_its_likeness(self):
        self.assertEqual([(p['a'], p['b']) for p in self.doc['pairs']],
                         [('uphill_athlete', 'gym_jones'), ('uphill_athlete', 'starting_strength'),
                          ('gym_jones', 'starting_strength')])
        for p in self.doc['pairs']:
            self.assertTrue(0 <= p['score'] <= 1)
            self.assertIn('label', p['primary'])

    def test_scale_covers_every_track(self):
        longest = max(t['weeks'] for i in self.IDS for t in self.glances[i]['tracks'])
        self.assertEqual(self.doc['scale']['trackWeeks'], longest)

    def test_equipment_partitions_what_each_needs(self):
        eq = self.doc['equipment']
        for i in self.IDS:
            mine = {e['id'] for e in self.glances[i]['equipment']}
            some = {s['item']['id'] for s in eq['some'] if i in s['ids']}
            parts = [{e['id'] for e in eq['shared']}, {e['id'] for e in eq['only'][i]}, some]
            self.assertEqual(set().union(*parts), mine)
            self.assertEqual(sum(map(len, parts)), len(mine))

    def test_a_philosophy_compared_with_itself_differs_in_nothing(self):
        # Two ids are required; the same glance twice is the degenerate case of the flags.
        g = self.glances['uphill_athlete']
        self.assertTrue(ec._all_same([g['levels'], list(g['levels'])]))
        self.assertTrue(ec._intensity_same([g['intensity'], dict(g['intensity'])]))

    def test_same_flags_read_the_glances(self):
        days = [(self.glances[i]['daysPerWeek'] or {}).get('ideal') for i in self.IDS]
        self.assertEqual(self.doc['same']['daysPerWeek'], len(set(days)) == 1)

    def test_shared_standards_say_who_tests_them(self):
        doc = ec.compare(['horsemen_gpp', 'uphill_athlete'])
        for s in doc['standards']['shared'] + [e['item'] for e in doc['standards']['some']]:
            self.assertNotIn('tested', s)
            self.assertTrue(set(s['testedBy']) <= {'horsemen_gpp', 'uphill_athlete'})
        for items in doc['standards']['only'].values():
            for s in items:
                self.assertIn('tested', s)

    def test_unknown_id_is_404(self):
        with self.assertRaises(ec.CompareError) as err:
            ec.compare(['uphill_athlete', 'nope'])
        self.assertEqual(err.exception.status, 404)


class Route(unittest.TestCase):
    def setUp(self):
        import api
        self.client = api.app.test_client()

    def test_answers_without_sign_in(self):
        resp = self.client.get('/api/philosophies/compare?ids=crossfit,gym_jones')
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.get_json()['ids'], ['crossfit', 'gym_jones'])

    def test_bad_requests(self):
        self.assertEqual(self.client.get('/api/philosophies/compare?ids=crossfit').status_code, 422)
        self.assertEqual(self.client.get('/api/philosophies/compare?ids=crossfit,nope').status_code, 404)


DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']


def schedule(train: dict) -> dict:
    """day → its first session ('short', 'long', …), every other day rest."""
    return {d: {'session1': train.get(d, 'rest'), 'session2': 'rest', 'session3': 'rest', 'session4': 'rest'}
            for d in DAYS}


class FromProfile(unittest.TestCase):
    def test_an_empty_profile_says_what_it_assumes(self):
        from src import profile_constraints as pc
        constraints, custom, assumed = pc.from_profile({})
        self.assertEqual(constraints, {'injury_flags': []})
        self.assertEqual(custom, [])
        self.assertEqual([a['key'] for a in assumed], ['training_level', 'equipment', 'schedule'])

    def test_a_profile_is_copied_as_the_builder_copies_it(self):
        from src import profile_constraints as pc
        flag = {'id': 'custom_wrist', 'name': 'Wrist', 'excluded_movement_patterns': ['push']}
        sched = schedule({'Monday': 'short', 'Thursday': 'long'})
        constraints, custom, assumed = pc.from_profile({
            'trainingLevel': 'novice', 'equipment': [], 'injuryFlags': ['knee'],
            'customInjuryFlags': [flag], 'weeklySchedule': sched})
        # An empty kit is a choice, as ConstraintsForm copies it.
        self.assertEqual(constraints, {'training_level': 'novice', 'equipment': [],
                                       'injury_flags': ['knee', 'custom_wrist'], 'weekly_schedule': sched})
        self.assertEqual(custom, [flag])
        self.assertEqual(assumed, [])

    def test_the_schedule_normalises_as_the_web_derives_it(self):
        # lib/scheduleToConstraints.ts for the same week: Mon short, Thu long.
        import api
        out = api._normalize_schedule_constraints({'weekly_schedule': schedule({'Monday': 'short', 'Thursday': 'long'})})
        self.assertEqual(out['days_per_week'], 2)
        self.assertEqual(out['preferred_days'], [1, 4])
        self.assertEqual(out['forced_rest_days'], [2, 3, 5, 6, 7])
        self.assertEqual({k: v['minutes'] for k, v in out['day_configs'].items()}, {1: 40, 4: 75})
        self.assertFalse(out['allow_split_sessions'])

    def test_a_contracts_entry_is_assumed_unless_given(self):
        from src import profile_constraints as pc, training_contract
        contract = training_contract.load_contract('wildman_kettlebell', 'pentathlon')
        constraints = {'training_level': 'intermediate'}
        assumed = pc.with_contract_entry(constraints, contract, {})
        if not (constraints.get('mastered_exercises') or constraints.get('kettlebell_count')):
            self.skipTest('the pentathlon contract asks nothing of an intermediate')
        self.assertTrue(assumed)
        again = dict(constraints)
        self.assertEqual(pc.with_contract_entry(again, contract, {}), [])
        self.assertEqual(pc.with_contract_entry({}, None, {}), [])


class ForAthlete(unittest.TestCase):
    GLANCE = {'id': 'p', 'primaryTrackId': 't', 'counts': {'sessions': 9},
              'equipment': [{'id': 'barbell', 'name': 'Barbell'}, {'id': 'box', 'name': 'Box'}],
              'tracks': [{'id': 't', 'name': 'Track', 'weeks': 8}, {'id': 'u', 'name': 'Other', 'weeks': 40}]}

    def program(self, **kw):
        week = {'schedule': {'Monday': [{'modality': 'max_strength'}], 'Wednesday': [{}, {}], 'Friday': []}}
        return {'weeks': [week, week],
                'validation': {'feasible': True, 'errors': [], 'warnings': [
                    {'code': 'EQUIPMENT_MISSING', 'message': 'a'}, {'code': 'EQUIPMENT_MISSING', 'message': 'a'},
                    {'code': 'EQUIPMENT_MISSING', 'message': 'b'}, {'code': 'LEVEL_COVERAGE_GAP', 'message': 'lvl'}]},
                'phase_summary': [
                    {'phase_id': 'a', 'name': 'A', 'kind': 'base', 'weeks': 1,
                     'sessions_per_week': {'max_strength': 2.0}, 'minutes_per_week': {'mean': 100},
                     'intensity': {'zone1_2': 1.0}},
                    {'phase_id': 'b', 'name': 'B', 'kind': 'build', 'weeks': 3,
                     'sessions_per_week': {'max_strength': 2.0, 'aerobic_base': 4.0},
                     'minutes_per_week': {'mean': 200}, 'intensity': {'max_effort': 1.0}}],
                'held_back': {'slots': 1, 'sessions': 1},
                'coverage_report': {'unfilled_sessions': [], 'unfilled_slots': [{}],
                                    'substituted_sessions': [{'week': 2, 'modality': 'mobility',
                                                              'substituted_for': 'power', 'reason': 'x'}],
                                    'placed_tests': [{}], 'skipped_tests': [{'week': 1, 'reason': 'deload'}]},
                **kw}

    def test_a_program_in_the_comparisons_numbers(self):
        track = ec.track_for(self.GLANCE, None)
        out = ec.for_athlete(self.program(), self.GLANCE, track, [], ['barbell'])
        self.assertTrue(out['feasible'])
        self.assertEqual((out['weeks'], out['ofWeeks']), (2, 8))
        self.assertEqual(out['perWeek'], {'days': 2.0, 'sessions': 3.0, 'minutes': 175})
        self.assertEqual(out['intensity'], {'zone1_2_pct': 0.25, 'max_effort_pct': 0.75})
        self.assertEqual(out['mix'], [{'modality': 'aerobic_base', 'perWeek': 3.0},
                                      {'modality': 'max_strength', 'perWeek': 2.0}])
        self.assertEqual(out['missingEquipment'], [{'id': 'box', 'name': 'Box'}])
        self.assertEqual(out['skippedForEquipment'], 2)
        self.assertEqual(out['warnings'], [{'code': 'LEVEL_COVERAGE_GAP', 'message': 'lvl'}])
        self.assertEqual(out['gaps']['slots'], 1)
        self.assertEqual(out['gaps']['substituted'][0]['insteadOf'], 'power')
        self.assertEqual(out['tests'], {'placed': 1, 'skipped': [{'week': 1, 'why': 'it fell on a deload week'}]})
        self.assertEqual([p['sessions'] for p in out['phases']], [2.0, 6.0])

    def test_a_refusal_says_why(self):
        track = ec.track_for(self.GLANCE, 'u')
        out = ec.for_athlete({'weeks': [], 'validation': {'errors': [
            {'code': 'DAYS', 'message': 'needs 6 days', 'suggested_fix': 'train 6'}]}}, self.GLANCE, track, [], None)
        self.assertFalse(out['feasible'])
        self.assertEqual(out['ofWeeks'], ec.MAX_WEEKS)
        self.assertEqual(out['reasons'], [{'code': 'DAYS', 'message': 'needs 6 days'}])
        self.assertNotIn('perWeek', out)
        out = ec.for_athlete({'weeks': [], 'detail': 'no'}, self.GLANCE, track, [], None)
        self.assertEqual(out['reasons'][0]['message'], 'no')

    def test_unknown_track(self):
        self.assertIsNone(ec.track_for(self.GLANCE, 'nope'))


class ForMeRoute(unittest.TestCase):
    def setUp(self):
        import api
        from unittest import mock
        self.api = api
        self.client = api.app.test_client()
        self.profile = {}
        patcher = mock.patch('src.db.get_user_profile', side_effect=lambda uid: self.profile)
        patcher.start()
        self.addCleanup(patcher.stop)
        api._HEAVY_CACHE.clear()

    def post(self, pid, body=None):
        return self.client.post(f'/api/philosophies/{pid}/for-me', json=body or {})

    def test_an_empty_profile_runs_on_defaults_and_says_so(self):
        out = self.post('atg').get_json()
        self.assertTrue(out['feasible'])
        self.assertEqual(out['trackId'], 'zero')
        self.assertEqual([a['key'] for a in out['assumed']], ['training_level', 'equipment', 'schedule'])
        self.assertEqual(out['perWeek']['days'], 3.0)

    def test_a_schedule_the_method_cannot_run_on_says_why(self):
        self.profile = {'trainingLevel': 'intermediate', 'equipment': ['kettlebell'],
                        'weeklySchedule': schedule({d: 'short' for d in DAYS[:3]})}
        out = self.post('gym_jones').get_json()
        self.assertFalse(out['feasible'])
        self.assertIn('days/week', out['reasons'][0]['message'])
        self.assertEqual(out['assumed'], [])

    def test_kit_the_method_needs_is_named(self):
        self.profile = {'trainingLevel': 'intermediate', 'equipment': ['kettlebell', 'pull_up_bar'],
                        'weeklySchedule': schedule({d: 'long' for d in DAYS[:4]})}
        out = self.post('horsemen_gpp').get_json()
        self.assertTrue(out['feasible'])
        self.assertIn('barbell', [e['id'] for e in out['missingEquipment']])
        self.assertGreater(out['skippedForEquipment'], 0)

    def test_the_body_overrides_the_profile_and_drops_its_assumption(self):
        out = self.post('atg', {'constraints': {'training_level': 'novice'}}).get_json()
        self.assertNotIn('training_level', [a['key'] for a in out['assumed']])

    def test_unknown_philosophy_or_track(self):
        self.assertEqual(self.post('nope').status_code, 404)
        self.assertEqual(self.post('atg', {'track_id': 'nope'}).status_code, 404)

    def test_a_second_ask_is_the_kept_answer(self):
        first = self.post('atg').get_json()
        from unittest import mock
        with mock.patch.object(self.api, '_generate_program_inner', side_effect=AssertionError('regenerated')):
            self.assertEqual(self.post('atg').get_json(), first)


FIXTURE = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'data', 'philosophy_compare_fixture.json')
WRITE = '--write' in sys.argv
FIXTURE_IDS = ['uphill_athlete', 'gym_jones', 'horsemen_gpp']
FIXTURE_PROFILE = {'trainingLevel': 'intermediate', 'equipment': ['kettlebell', 'pull_up_bar'], 'injuryFlags': [],
                   'weeklySchedule': schedule({d: 'long' for d in ('Monday', 'Tuesday', 'Thursday', 'Saturday')})}


class Fixture(unittest.TestCase):
    def test_the_recorded_answers_are_the_routes(self):
        import json
        import api
        from unittest import mock
        api._HEAVY_CACHE.clear()
        client = api.app.test_client()
        doc = client.get(f"/api/philosophies/compare?ids={','.join(FIXTURE_IDS)}").get_json()
        with mock.patch('src.db.get_user_profile', return_value=FIXTURE_PROFILE):
            for_me = {pid: client.post(f'/api/philosophies/{pid}/for-me', json={}).get_json() for pid in FIXTURE_IDS}
        now = json.loads(json.dumps({'compare': doc, 'forMe': for_me}))
        if WRITE:
            with open(FIXTURE, 'w', encoding='utf-8') as f:
                json.dump(now, f, indent=1, ensure_ascii=False)
                f.write('\n')
        with open(FIXTURE, encoding='utf-8') as f:
            self.assertEqual(json.load(f), now, 'run with --write and commit data/philosophy_compare_fixture.json')


if __name__ == '__main__':
    if WRITE:
        sys.argv.remove('--write')
    unittest.main(verbosity=1)
