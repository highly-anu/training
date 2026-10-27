"""GET /api/philosophies/<id>/describe: a philosophy as its package writes it
(src/explore_philosophy.py).

    SUPABASE_URL='' .venv/bin/python test_explore_philosophy.py
"""
from __future__ import annotations

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from src import explore_links, explore_philosophy as ep, loader, phases, training_contract  # noqa: E402


def ex(id, patterns=(), category='kettlebell', pkg='p', **kw):
    return {'id': id, 'name': id.title(), 'category': category, 'movement_patterns': list(patterns),
            '_package': pkg, '_packages': [pkg], **kw}


EXERCISES = {e['id']: e for e in [
    ex('swing', ['hip_hinge', 'ballistic']),
    ex('squat', ['squat']),
    ex('run', ['locomotion'], category='aerobic'),
    ex('other', ['squat'], pkg='q'),
]}

FRAMEWORKS = {
    'tpl': {'id': 'tpl', 'name': 'Template', 'source_philosophy': 'p', 'warm_up_category': 'warm',
            'intensity_distribution': {'zone1_2_pct': 0.8, 'zone4_5_pct': 0.2},
            'deload_protocol': {'frequency_weeks': 4, 'volume_reduction_pct': 0.6},
            'expectations': {'min_weeks': 4, 'ideal_weeks': 8},
            'categories': {
                'warm': {'name': 'Warm-up', 'modality': 'mobility', 'warm_up': False, 'archetypes': ['w1']},
                'heavy': {'name': 'Heavy', 'modality': 'max_strength', 'archetypes': ['h1', 'h2']},
                'easy': {'name': 'Easy', 'modality': 'aerobic_base', 'warm_up': False, 'archetypes': ['e1']},
            }},
    'fw': {'id': 'fw', 'name': 'Plain', 'source_philosophy': 'p', 'sessions_per_week': {'aerobic_base': 2}},
}


def arch(id, modality, slots, **kw):
    return {'id': id, 'name': id.upper(), 'modality': modality, '_package': 'p', 'slots': slots, **kw}


ARCHETYPES = [
    arch('w1', 'mobility', [{'role': 'flow', 'slot_type': 'time_domain', 'duration_sec': 300,
                             'exercise_filter': {'exercise_ids': ['squat']}}], pool_only=True),
    arch('h1', 'max_strength', [{'role': 'main', 'slot_type': 'sets_reps', 'sets': 5, 'reps': 5,
                                 'exercise_filter': {'movement_pattern': 'squat'}}], pool_only=True),
    arch('h2', 'max_strength', [{'role': 'main', 'slot_type': 'sets_reps', 'rep_scheme': [21, 15, 9],
                                 'exercise_filter': {'exercise_ids': ['swing']}}], pool_only=True),
    arch('e1', 'aerobic_base', [{'role': 'run', 'slot_type': 'time_domain', 'duration_minutes': 40,
                                 'intensity': 'zone2', 'exercise_filter': {'exercise_ids': ['run']}}]),
    arch('t1', 'aerobic_base', [{'role': 'mile', 'slot_type': 'for_time', 'standard': 'mile_run',
                                 'exercise_filter': {'exercise_ids': ['run']}}], test=True),
    arch('loose', 'power', [{'role': 'swing', 'slot_type': 'sets_reps', 'sets': 10, 'reps': 10,
                             'exercise_filter': {'movement_pattern': 'swing'}}]),
    arch('c1', 'power', [{'role': 'swing', 'slot_type': 'emom', 'exercise_filter': {'exercise_ids': ['swing']}}]),
]

PHIL = {
    'id': 'p', 'name': 'P', 'notes': 'What it is.', 'bias': ['max_strength'], 'core_principles': ['lift_heavy'],
    'intensity_model': 'hard_easy', 'required_equipment': ['barbell', 'open_space'],
    'primary_track_id': 'templ',
    'tracks': [
        {'id': 'templ', 'name': 'Templated', 'phases': [
            {'id': 'a', 'name': 'A', 'kind': 'base', 'weeks': 6, 'framework_id': 'tpl',
             'week_templates': [['heavy', 'easy', 'rest', {'categories': ['heavy', 'easy'], 'light': True},
                                 'rest', 'rest', 'rest'],
                                ['heavy', 'rest', 'rest', 'rest', 'rest', 'rest', 'rest']],
             'tests': [{'archetype': 't1', 'week': 'last'}]},
            {'id': 'b', 'name': 'B', 'kind': 'build', 'weeks': 2, 'framework_id': 'fw'},
        ]},
        {'id': 'contract', 'name': 'Contract', 'phases': [
            {'id': 'c', 'name': 'C', 'kind': 'build', 'weeks': 4, 'framework_id': 'fw'}]},
    ],
}

CONTRACT = {'training_levels': ['novice', 'intermediate'], 'notes': 'Clean reps only.\n', 'modules': [
    {'id': 'swings', 'name': 'Swings', 'modality': 'power', 'archetype_id': 'c1', 'training_levels': ['novice'],
     'exposures_per_week': 2, 'progression': {'model': 'density_cycle'},
     'blocks': [{'role': 'swing', 'exercise_id': 'swing', 'slot_type': 'emom', 'sets': 10, 'reps': 10,
                 'notes': 'On the minute.'}]},
    {'id': 'extra', 'name': 'Extra', 'modality': 'aerobic_base', 'optional': True, 'training_levels': ['novice'],
     'exposures_per_week': 1, 'progression': {'model': 'weekly_volume'},
     'blocks': [{'role': 'run', 'exercise_id': 'run', 'slot_type': 'time_domain', 'duration_sec': 1800}]},
    {'id': 'elsewhere', 'name': 'Elsewhere', 'modality': 'max_strength', 'phases': ['zz'],
     'training_levels': ['novice'], 'exposures_per_week': 3, 'progression': {'model': 'load_per_exposure'},
     'blocks': []},
]}

RECORD = {'sources': [{'id': 'book', 'title': 'The Book', 'author': 'A. Author', 'where': 'https://x'}],
          'rules': [{'id': 'R1', 'text': 'Lift heavy twice a week.',
                     'cites': [{'source': 'book', 'at': '"twice a week"'}], 'enforced_by': []}],
          'inventions': [{'id': 'I1', 'text': 'Six weeks.', 'implemented_by': []}],
          'open': ['No novice track.']}


def build(**kw):
    args = dict(philosophies=[PHIL], frameworks=FRAMEWORKS, modalities={}, archetypes=ARCHETYPES,
                exercises=EXERCISES, contracts={'contract': CONTRACT}, record=RECORD,
                standards={'mile_run': {'name': 'Mile run'}})
    args.update(kw)
    return ep.build(PHIL, **args)


class PrescriptionTests(unittest.TestCase):
    def test_lines(self):
        self.assertEqual(ep.prescription({'sets': 3, 'reps': 5, 'rest_sec': 300}), '3 × 5 · 5 min rest')
        self.assertEqual(ep.prescription({'rep_scheme': [21, 15, 9], 'slot_type': 'for_time'}), '21-15-9 · for time')
        self.assertEqual(ep.prescription({'duration_minutes': 40, 'intensity': 'zone2'}), '40 min · zone2')
        self.assertEqual(ep.prescription({'sets': 3, 'reps': 'max'}), '3 × max')
        self.assertEqual(ep.prescription({'distance_m': 5000}), '5 km')
        self.assertEqual(ep.prescription({'slot_type': 'time_domain', 'duration_sec': 5400}), '1 h 30 min')
        self.assertEqual(ep.prescription({'rounds': 5, 'reps_per_round': 10, 'load': '24 kg'}),
                         '5 rounds × 10 · 24 kg')
        self.assertEqual(ep.prescription({}), '')


class TemplateTests(unittest.TestCase):
    def setUp(self):
        self.doc = build()
        self.track = self.doc['tracks'][0]
        self.a = self.track['phases'][0]

    def test_days_are_the_templates(self):
        week = self.a['week']
        self.assertEqual(week['kind'], 'template')
        self.assertEqual(len(week['weeks']), 2)
        first = week['weeks'][0]
        self.assertEqual([d['day'] for d in first][:2], ['Monday', 'Tuesday'])
        self.assertEqual([p['name'] for p in first[0]['pieces']], ['Heavy'])
        self.assertTrue(first[2]['rest'])
        self.assertEqual(week['warmUp'], 'Warm-up')

    def test_warm_up_follows_the_engine(self):
        first = self.a['week']['weeks'][0]
        self.assertTrue(first[0]['warmUp'])       # Heavy: no say, so warmed up
        self.assertFalse(first[1]['warmUp'])      # Easy says warm_up: false
        self.assertTrue(first[3]['light'])

    def test_mix_averages_template_weeks_and_splits_shared_days(self):
        mix = {m['modality']: m['perWeek'] for m in self.a['mix']}
        # Week 1: heavy 1 + 0.5, easy 1 + 0.5; week 2: heavy 1 → averaged.
        self.assertAlmostEqual(mix['max_strength'], 1.25)
        self.assertAlmostEqual(mix['aerobic_base'], 0.75)

    def test_track_mix_is_weighted_by_phase_weeks(self):
        mix = {m['modality']: m['perWeek'] for m in self.track['mix']}
        # A: 6 weeks of 0.75 aerobic; B (framework): 2 weeks of 2.
        self.assertAlmostEqual(mix['aerobic_base'], round((6 * 0.75 + 2 * 2) / 8, 2))
        self.assertAlmostEqual(mix['max_strength'], round(6 * 1.25 / 8, 2))
        self.assertEqual(self.doc['mix'], self.track['mix'])  # the primary track's

    def test_framework_phase_reads_sessions_per_week(self):
        b = self.track['phases'][1]
        self.assertEqual(b['week'], {'kind': 'framework', 'sessions': [{'modality': 'aerobic_base', 'perWeek': 2}]})
        self.assertIsNone(b['deload'])  # its framework declares no deload protocol

    def test_phase_words_tests_and_deload(self):
        self.assertEqual(self.a['tests'], [{'when': 'the last week', 'sessions': ['T1'],
                                             'standards': ['Mile run'], 'onDeload': False}])
        self.assertEqual(self.a['deload'], 'Every 4 weeks an easier week, keeping 60 % of the volume.')
        self.assertEqual(self.a['intensitySplit'], {'zone1_2_pct': 0.8, 'zone4_5_pct': 0.2})
        self.assertEqual(self.track['builtBy'], 'template')


class ContractTests(unittest.TestCase):
    def setUp(self):
        self.track = build()['tracks'][1]
        self.week = self.track['phases'][0]['week']

    def test_modules_running_in_the_phase(self):
        self.assertEqual([m['id'] for m in self.week['modules']], ['swings', 'extra'])
        swings = self.week['modules'][0]
        self.assertEqual(swings['perWeek'], 2)
        self.assertEqual(swings['items'][0]['name'], 'Swing')
        self.assertEqual(swings['items'][0]['prescription'], '10 × 10')
        self.assertIn('more rounds', swings['progression'])

    def test_optional_modules_stay_out_of_the_mix(self):
        self.assertEqual(self.track['mix'], [{'modality': 'power', 'perWeek': 2, 'share': 1.0}])

    def test_track_carries_the_contract(self):
        self.assertEqual(self.track['builtBy'], 'contract')
        self.assertEqual(self.track['levels'], ['novice', 'intermediate'])
        self.assertEqual(self.track['notes'], 'Clean reps only.')
        self.assertIsNone(self.track['phases'][0]['deload'])


class SessionTests(unittest.TestCase):
    def setUp(self):
        self.doc = build()

    def test_every_archetype_in_exactly_one_group(self):
        grouped = [s for g in self.doc['groups'] for s in g['sessions']]
        self.assertEqual(sorted(grouped), sorted(a['id'] for a in ARCHETYPES))
        self.assertEqual(len(grouped), len(set(grouped)))

    def test_group_order(self):
        kinds = [(g['kind'], g['id']) for g in self.doc['groups']]
        self.assertEqual(kinds, [('category', 'warm'), ('category', 'heavy'), ('category', 'easy'),
                                 ('module', 'swings'), ('modality', 'power'), ('tests', 'tests')])
        self.assertTrue(self.doc['groups'][0]['warmUp'])

    def test_slots_take_exercises_by_the_selectors_rule(self):
        s = self.doc['sessions']
        self.assertEqual([e['id'] for e in s['h2']['slots'][0]['exercises']], ['swing'])  # listed
        self.assertEqual([e['id'] for e in s['h1']['slots'][0]['exercises']], ['squat'])  # filter, own package
        self.assertTrue(s['h2']['slots'][0]['listed'])
        self.assertEqual(s['h2']['slots'][0]['prescription'], '21-15-9')
        self.assertEqual(s['t1']['slots'][0]['standard'], 'mile_run')


class IdentityTests(unittest.TestCase):
    def test_identity_and_record(self):
        doc = build()
        self.assertEqual(doc['summary'], 'What it is.')
        self.assertEqual(doc['accent'], 'max_strength')
        self.assertEqual(doc['principles'], ['Lift heavy'])
        self.assertEqual(doc['models'], {'intensity': 'Hard easy', 'progression': None})
        self.assertEqual(doc['equipment'], [{'id': 'barbell', 'name': 'Barbell'}])
        self.assertEqual(doc['levels'], ['novice', 'intermediate'])
        self.assertEqual(doc['rules'], [{'id': 'R1', 'text': 'Lift heavy twice a week.',
                                         'cites': [{'source': 'The Book — A. Author', 'quote': '"twice a week"'}]}])
        self.assertEqual(doc['inventions'], [{'id': 'I1', 'text': 'Six weeks.'}])
        self.assertEqual(doc['open'], ['No novice track.'])
        self.assertEqual(doc['sources'][0]['where'], 'https://x')
        self.assertEqual(doc['expectations'], {'min_weeks': 4, 'ideal_weeks': 8})

    def test_without_a_record_the_philosophys_sources(self):
        phil = {**PHIL, 'sources': ['A book (2001)']}
        doc = ep.build(phil, philosophies=[phil], frameworks=FRAMEWORKS, modalities={}, archetypes=ARCHETYPES,
                       exercises=EXERCISES, contracts={}, record=None, standards={})
        self.assertEqual(doc['rules'], [])
        self.assertEqual([s['title'] for s in doc['sources']], ['A book (2001)'])


class RealDataTests(unittest.TestCase):
    """Every shipped package describes completely."""

    @classmethod
    def setUpClass(cls):
        cls.philosophies = loader.load_philosophies()
        cls.docs = {p['id']: ep.describe(p['id']) for p in cls.philosophies}
        cls.links = explore_links.build_from_loader()['links']['archetypeExercise']

    def test_every_phase_has_a_week(self):
        for pid, doc in self.docs.items():
            for t in doc['tracks']:
                for p in t['phases']:
                    self.assertTrue(p['mix'], f'{pid}/{t["id"]}/{p["id"]}: an empty week')

    def test_the_week_is_read_from_what_builds_it(self):
        for phil in self.philosophies:
            for track in phases.tracks_of(phil):
                built = next(t for t in self.docs[phil['id']]['tracks'] if t['id'] == track['id'])['builtBy']
                contract = training_contract.load_contract(phil['id'], track['id'])
                want = 'contract' if contract else (
                    'template' if any(p.get('week_templates') for p in track['phases']) else 'framework')
                self.assertEqual(built, want, f"{phil['id']}/{track['id']}")

    def test_every_archetype_grouped_once(self):
        archetypes = loader.load_all_archetypes()
        for pid, doc in self.docs.items():
            grouped = [s for g in doc['groups'] for s in g['sessions']]
            self.assertEqual(sorted(grouped), sorted(a['id'] for a in archetypes if a.get('_package') == pid), pid)

    def test_slot_exercises_are_explore_links_edges(self):
        edges: dict = {}
        for e in self.links:
            edges.setdefault(e['archetype'], set()).add(e['exercise'])
        for pid, doc in self.docs.items():
            for aid, s in doc['sessions'].items():
                found = {x['id'] for slot in s['slots'] for x in slot['exercises']}
                self.assertEqual(found, edges.get(aid, set()), f'{pid}/{aid}')

    def test_almost_every_slot_has_exercises(self):
        slots = [sl for d in self.docs.values() for s in d['sessions'].values() for sl in s['slots']
                 if not sl['technique']]
        empty = [sl for sl in slots if not sl['exercises']]
        # The web's old matcher left 1,748 of 1,769 empty.
        self.assertLess(len(empty), 5, [(sl['role']) for sl in empty])

    def test_every_record_rule_is_there(self):
        for pid, doc in self.docs.items():
            rec = ep._record(pid)
            self.assertEqual(len(doc['rules']), len((rec or {}).get('rules') or []), pid)


class RouteTests(unittest.TestCase):
    def test_route(self):
        import api
        client = api.app.test_client()
        pid = loader.load_philosophies()[0]['id']
        body = client.get(f'/api/philosophies/{pid}/describe').get_json()
        self.assertEqual(body['id'], pid)
        self.assertIn('tracks', body)
        self.assertEqual(client.get('/api/philosophies/nope/describe').status_code, 404)


if __name__ == '__main__':
    unittest.main(verbosity=1)
