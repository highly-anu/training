"""Regional recovery: where a session's work lands, read from its exercises'
movement patterns (src/recovery_regions.py), and the soft rule the picker and
a contract's placement apply with it. Run:
    SUPABASE_URL='' .venv/bin/python test_recovery_regions.py
"""
import unittest

from src import loader, recovery_regions as rr, selector, training_contract as tc

DATA = loader.load_all_data()
MODS = DATA['modalities']
EX = {
    'squat': {'id': 'squat', 'movement_patterns': ['squat']},
    'press': {'id': 'press', 'movement_patterns': ['vertical_push']},
    'row': {'id': 'row', 'movement_patterns': ['horizontal_pull']},
}


def arch(aid, *exercise_ids, modality='max_strength', intensity='heavy'):
    return {'id': aid, 'modality': modality, 'duration_estimate_minutes': 45, 'required_equipment': [],
            'slots': [{'role': 'warm_up', 'slot_type': 'time_domain', 'exercise_filter': {'exercise_ids': ['row']}}]
            + [{'role': f'main_{i}', 'slot_type': 'sets_reps', 'intensity': intensity,
                'exercise_filter': {'exercise_ids': [e]}} for i, e in enumerate(exercise_ids)]}


class Derivation(unittest.TestCase):
    def test_a_sessions_load_is_its_working_slots(self):
        # The warm-up's row is not the session's work.
        load = rr.archetype_load(arch('legs', 'squat'), EX, MODS)
        self.assertEqual(load, {'lower': 1.25})
        self.assertEqual(rr.heavy(load), {'lower'})
        mixed = rr.archetype_load(arch('mixed', 'squat', 'press'), EX, MODS)
        self.assertEqual(mixed, {'lower': 0.625, 'upper_push': 0.625})

    def test_cost_and_intensity_scale_it(self):
        easy = rr.archetype_load(arch('easy', 'squat', modality='aerobic_base', intensity='zone2'), EX, MODS)
        self.assertEqual(rr.heavy(easy), frozenset())

    def test_a_written_load_overrides(self):
        bjj = next(a for a in DATA['archetypes'] if a['id'] == 'bjj_class')
        self.assertEqual(rr.heavy(rr.archetype_load(bjj, DATA['exercises'], MODS)),
                         {'lower', 'upper_pull', 'trunk', 'upper_push', 'cardio'})

    def test_every_pattern_in_the_library_is_mapped(self):
        cfg = rr.config()
        known = set(cfg['patterns']) | set(cfg['unloaded'])
        used = {p for e in DATA['exercises'].values() for p in e.get('movement_patterns') or []}
        self.assertEqual(used - known, set())
        for weights in cfg['patterns'].values():
            self.assertLessEqual(set(weights), set(cfg['regions']))

    def test_the_penalty_is_per_shared_region_and_capped(self):
        legs = frozenset({'lower'})
        self.assertEqual(rr.penalty(legs, [(24, legs)]), 2)
        self.assertEqual(rr.penalty(legs, [(48, legs)]), 1)
        self.assertEqual(rr.penalty(legs, [(24, frozenset({'upper_push'}))]), 0)
        everything = frozenset(rr.config()['regions'])
        self.assertEqual(rr.penalty(everything, [(24, everything)]), rr.config()['penalty_cap'])


class Picker(unittest.TestCase):
    def pick(self, recent):
        options = [arch('legs', 'squat'), arch('upper', 'press')]
        regions = {a['id']: rr.heavy(rr.archetype_load(a, EX, MODS)) for a in options}
        constraints = {'equipment': [], 'session_time_minutes': 60, 'training_level': 'intermediate'}
        chosen, trace = selector.select_archetype('max_strength', constraints, 'base', False, {}, options,
                                                  return_trace=True, recent_regions=recent, arch_regions=regions)
        return chosen['id'], trace

    def test_the_day_after_heavy_legs_prefers_the_upper_session(self):
        # Otherwise equal, the first authored wins.
        self.assertEqual(self.pick([])[0], 'legs')
        chosen, trace = self.pick([(24, frozenset({'lower'}))])
        self.assertEqual(chosen, 'upper')
        legs = next(c for c in trace['candidates'] if c['id'] == 'legs')
        self.assertEqual(legs['breakdown']['regional'], -2)
        self.assertEqual(legs['heavy_regions'], ['lower'])
        # The trace adds up to the score.
        for c in trace['candidates']:
            self.assertEqual(c['breakdown']['total'], c['score'])

    def test_a_soft_rule_never_empties_the_day(self):
        options = [arch('legs', 'squat')]
        regions = {'legs': frozenset({'lower'})}
        constraints = {'equipment': [], 'session_time_minutes': 60, 'training_level': 'intermediate'}
        chosen = selector.select_archetype('max_strength', constraints, 'base', False, {}, options,
                                           recent_regions=[(24, frozenset({'lower'}))], arch_regions=regions)
        self.assertEqual(chosen['id'], 'legs')


class Placement(unittest.TestCase):
    def test_a_contract_keeps_two_leg_days_apart_when_it_can(self):
        m = lambda mid, mod: {'id': mid, 'modality': mod}
        regions = {'legs': frozenset({'lower'}), 'hinge': frozenset({'lower'}), 'press': frozenset({'upper_push'})}
        together = {1: [m('legs', 'a')], 2: [m('hinge', 'b')], 4: [m('press', 'c')]}
        apart = {1: [m('legs', 'a')], 2: [m('press', 'c')], 4: [m('hinge', 'b')]}
        self.assertGreater(tc._spacing(apart, regions), tc._spacing(together, regions))


if __name__ == '__main__':
    unittest.main()
