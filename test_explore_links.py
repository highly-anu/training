"""GET /api/explore/links: how Explore's levels connect (src/explore_links.py).

    SUPABASE_URL='' .venv/bin/python test_explore_links.py
"""
from __future__ import annotations

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from src import explore_links, loader


def ex(id, patterns=(), category='kettlebell', pkg='p', **kw):
    return {'id': id, 'name': id, 'category': category, 'movement_patterns': list(patterns),
            '_package': pkg, '_packages': [pkg], **kw}


def arch(id, slots, modality='strength', pkg='p'):
    return {'id': id, 'name': id, 'modality': modality, '_package': pkg, 'slots': slots}


PHILOSOPHIES = [{'id': 'p', 'tracks': [{'id': 't', 'name': 'Track',
                                         'phases': [{'id': 'a', 'name': 'Base', 'framework_id': 'f1'},
                                                    {'id': 'b', 'name': 'Peak', 'framework_id': 'f2'}]}]},
                {'id': 'q', 'tracks': []}]
FRAMEWORKS = {'f1': {'id': 'f1', 'source_philosophy': 'p', 'sessions_per_week': {'strength': 3},
                     'modality_priority': {'committed': ['strength'], 'core': ['mobility']}},
              'f2': {'id': 'f2', 'source_philosophy': 'p', 'sessions_per_week': {'strength': 2, 'nope': 1}}}
MODALITIES = {'strength': {'id': 'strength'}, 'mobility': {'id': 'mobility'}}
EXERCISES = {e['id']: e for e in [
    ex('press', ['vertical_push']),
    ex('bench', ['horizontal_push'], requires=['press', 'bracing_mechanics']),
    ex('jerk', ['vertical_push', 'ballistic'], unlocks=['bench', 'missing']),
    ex('named', ['vertical_push'], named_only=True),
    ex('other_pkg', ['vertical_push'], pkg='q'),
    ex('row', ['horizontal_pull'], requires=['press'], unlocks=['press_again']),
]}
ARCHETYPES = [
    arch('listed', [{'role': 'main', 'exercise_filter': {'exercise_ids': ['press', 'named', 'ghost']}},
                    {'role': 'second', 'exercise_filter': {'exercise_ids': ['press']}}]),
    arch('by_alias', [{'role': 'push', 'exercise_filter': {'movement_pattern': 'press'}},
                      {'role': 'skip', 'skip_exercise': True, 'exercise_filter': {'movement_pattern': 'pull'}}]),
]


def build():
    return explore_links.build(PHILOSOPHIES, FRAMEWORKS, MODALITIES, ARCHETYPES, EXERCISES)


class BuildTests(unittest.TestCase):
    def setUp(self):
        self.doc = build()
        self.links = self.doc['links']

    def edges(self, kind, **match):
        return [e for e in self.links[kind] if all(e[k] == v for k, v in match.items())]

    def test_listed_slot_links_what_it_names(self):
        got = {e['exercise']: e for e in self.edges('archetypeExercise', archetype='listed')}
        self.assertEqual(set(got), {'press', 'named'})        # a dangling id links nothing
        self.assertEqual(got['press']['slots'], ['main', 'second'])
        self.assertEqual(got['press']['via'], 'listed')

    def test_filter_slot_links_through_the_alias(self):
        got = {e['exercise'] for e in self.edges('archetypeExercise', archetype='by_alias')}
        # press = horizontal_push or vertical_push; a named_only movement only by name,
        # another package's never, a skipped slot links nothing.
        self.assertEqual(got, {'press', 'bench', 'jerk'})
        self.assertTrue(all(e['via'] == 'filter' for e in self.edges('archetypeExercise', archetype='by_alias')))

    def test_progression_is_the_union_of_both_sides(self):
        pairs = {(e['from'], e['to']): e['declaredBy'] for e in self.links['exerciseProgression']}
        self.assertEqual(pairs, {('press', 'bench'): ['requires'], ('jerk', 'bench'): ['unlocks'],
                                 ('press', 'row'): ['requires']})
        self.assertEqual(self.links['exerciseConcepts'], [{'exercise': 'bench', 'concept': 'bracing_mechanics'}])

    def test_both_sides_fold_into_one_edge(self):
        exercises = dict(EXERCISES, press=ex('press', ['vertical_push'], unlocks=['bench']))
        doc = explore_links.build(PHILOSOPHIES, FRAMEWORKS, MODALITIES, ARCHETYPES, exercises)
        pairs = {(e['from'], e['to']): e['declaredBy'] for e in doc['links']['exerciseProgression']}
        self.assertEqual(pairs[('press', 'bench')], ['requires', 'unlocks'])

    def test_philosophy_frameworks_in_phase_order(self):
        f1, f2 = (self.edges('philosophyFramework', framework=f)[0] for f in ('f1', 'f2'))
        self.assertTrue(f1['owner'])
        self.assertEqual([(p['phaseName'], p['trackIndex'], p['order']) for p in f2['phases']], [('Peak', 0, 1)])

    def test_framework_modalities_with_count_and_tier(self):
        got = {(e['framework'], e['modality']): (e['sessionsPerWeek'], e['tier'])
               for e in self.links['frameworkModality']}
        self.assertEqual(got, {('f1', 'strength'): (3, 'committed'), ('f1', 'mobility'): (None, 'core'),
                               ('f2', 'strength'): (2, None)})   # an unknown modality is dropped

    def test_movements(self):
        moves = {m['id']: m for m in self.doc['movements']}
        self.assertEqual(moves['vertical_push']['exerciseCount'], 4)
        self.assertEqual(moves['vertical_push']['name'], 'Vertical push')
        self.assertEqual(moves['vertical_push']['rollup'], 'push')
        self.assertIn('press', moves['vertical_push']['filterGroups'])
        self.assertNotIn('vertical_push', moves['vertical_push']['filterGroups'])


class RealDataTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.doc = explore_links.build_from_loader()
        cls.exercises, _ = loader.load_all_exercises()
        cls.archetypes = {a['id']: a for a in loader.load_all_archetypes()}

    def test_every_edge_resolves(self):
        links, ex_ids = self.doc['links'], set(self.exercises)
        fw_ids, mod_ids = set(loader.load_all_frameworks()), set(loader.load_all_modalities())
        phil_ids = {p['id'] for p in loader.load_philosophies()}
        moves = {m['id'] for m in self.doc['movements']}
        for e in links['philosophyFramework']:
            self.assertIn(e['philosophy'], phil_ids); self.assertIn(e['framework'], fw_ids)
        for e in links['frameworkModality']:
            self.assertIn(e['framework'], fw_ids); self.assertIn(e['modality'], mod_ids)
        for e in links['modalityArchetype']:
            self.assertIn(e['archetype'], self.archetypes); self.assertIn(e['modality'], mod_ids)
        for e in links['archetypeExercise']:
            self.assertIn(e['archetype'], self.archetypes); self.assertIn(e['exercise'], ex_ids)
        for e in links['exerciseMovement']:
            self.assertIn(e['exercise'], ex_ids); self.assertIn(e['movement'], moves)
        for e in links['exerciseProgression']:
            self.assertIn(e['from'], ex_ids); self.assertIn(e['to'], ex_ids)
        for e in links['exerciseConcepts']:
            self.assertNotIn(e['concept'], ex_ids)

    def test_listed_slots_link_almost_every_archetype(self):
        # The web's old matcher read only movement_pattern and category, which
        # 26 slots use; nearly every archetype names its exercises.
        linked = {e['archetype'] for e in self.doc['links']['archetypeExercise']}
        self.assertGreater(len(linked), 0.95 * len(self.archetypes))

    def test_movement_counts_match_their_edges(self):
        counts: dict = {}
        for e in self.doc['links']['exerciseMovement']:
            counts[e['movement']] = counts.get(e['movement'], 0) + 1
        self.assertEqual({m['id']: m['exerciseCount'] for m in self.doc['movements']}, counts)

    def test_no_duplicate_edges(self):
        links = self.doc['links']
        for kind, key in (('archetypeExercise', ('archetype', 'exercise')),
                          ('exerciseProgression', ('from', 'to')),
                          ('exerciseMovement', ('exercise', 'movement')),
                          ('philosophyFramework', ('philosophy', 'framework')),
                          ('frameworkModality', ('framework', 'modality'))):
            keys = [tuple(e[k] for k in key) for e in links[kind]]
            self.assertEqual(len(keys), len(set(keys)), kind)


class EquipmentTests(unittest.TestCase):
    """The equipment block says what the generator needs, so a client that only
    tests coverage agrees with it on every set."""

    @classmethod
    def setUpClass(cls):
        cls.doc = explore_links.build_from_loader()
        cls.exercises, _ = loader.load_all_exercises()
        cls.archetypes = loader.load_all_archetypes()
        import json
        with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'docs', 'schemas',
                               'constraints.schema.json')) as f:
            cls.enum = json.load(f)['properties']['equipment']['items']['enum']
        sets = [set(), set(cls.enum)]
        sets += [set(p['equipment']) for p in loader.load_equipment_profiles()]
        # One item at a time, and each profile less its first item.
        sets += [{e} for e in cls.enum] + [set(p['equipment'][1:]) for p in loader.load_equipment_profiles()]
        cls.sets = sets

    def test_vocabulary_is_the_schema_enum(self):
        self.assertEqual(self.doc['equipment']['vocabulary'], self.enum)

    def test_free_items_are_never_needed(self):
        eq = self.doc['equipment']
        for needs in [*eq['exercises'].values(), *eq['archetypes'].values()]:
            self.assertFalse({'open_space', 'none'} & set(needs), needs)

    def test_exercise_coverage_is_the_selectors_rule(self):
        from src.selector import _equipment_ok
        needs = self.doc['equipment']['exercises']
        self.assertEqual(set(needs), set(self.exercises))
        for s in self.sets:
            for ex in self.exercises.values():
                self.assertEqual(set(needs[ex['id']]) <= s, _equipment_ok(ex, s), (ex['id'], sorted(s)))

    def test_archetype_coverage_is_the_generators_rule(self):
        from src.generator import _fits_as_written
        needs = self.doc['equipment']['archetypes']
        whole = {'archetype': True, 'exercises': []}
        for s in self.sets:
            for arch in self.archetypes:
                level = (arch.get('training_levels') or ['intermediate'])[0]
                phase = (arch.get('applicable_phases') or ['base'])[0]
                fits = _fits_as_written(arch, {'equipment': sorted(s), 'training_level': level}, phase,
                                        lambda _a: whole)
                self.assertEqual(set(needs[arch['id']]) <= s, fits, (arch['id'], sorted(s)))


class RouteTests(unittest.TestCase):
    def test_route(self):
        import api
        body = api.app.test_client().get('/api/explore/links').get_json()
        self.assertEqual(set(body), {'movements', 'equipment', 'links'})
        self.assertIn('squat', {m['id'] for m in body['movements']})


if __name__ == '__main__':
    unittest.main(verbosity=1)
