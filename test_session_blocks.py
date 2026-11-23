"""A workout as blocks (src/session_blocks.py): what opens it, what repeats in
rounds or every minute, the rests, what closes it — for an archetype and for
a stored session, derived on read and never stored.

    SUPABASE_URL='' .venv/bin/python test_session_blocks.py
"""
from __future__ import annotations

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from src import loader, program_history, session_blocks as sb  # noqa: E402


def arch(*slots):
    return {'id': 'a', 'slots': list(slots)}


def slot(role, slot_type='sets_reps', **kw):
    return {'role': role, 'slot_type': slot_type, **kw}


def child(role, parent, **kw):
    return slot(role, 'amrap_movement', parent_slot_role=parent, **kw)


FRAN = arch(slot('fran', 'for_time', rep_scheme=[21, 15, 9], rounds=3, load='95 lb', standard='wod_fran'),
            child('fran_2', 'fran', rep_scheme=[21, 15, 9]))
CINDY = arch(slot('cindy', 'amrap', reps_per_round=5, duration_sec=1200),
             child('cindy_2', 'cindy', reps_per_round=10), child('cindy_3', 'cindy', reps_per_round=15))
# The complex an athlete's own method wrote: eight movements, six rounds,
# a rest between rounds — one block, not eight lines.
COMPLEX = arch(slot('warm_up', 'skill_practice', duration_minutes=5),
               slot('complex', 'rounds_for_time', rounds=6, reps_per_round=5, rest_sec=150, intensity='heavy',
                    load='moderate-heavy bell'),
               child('clean', 'complex', reps_per_round=5), child('swing', 'complex', reps_per_round=5),
               slot('push_up_finisher', sets=2, reps=15, rest_sec=60))


class Grouping(unittest.TestCase):

    def test_a_piece_holds_its_movements(self):
        blocks = sb.for_archetype(FRAN)
        self.assertEqual(len(blocks), 1)
        self.assertEqual(blocks[0]['roles'], ['fran', 'fran_2'])
        self.assertEqual([m['count'] for m in blocks[0]['movements']], ['21-15-9', '21-15-9'])
        self.assertEqual(blocks[0]['standard'], 'wod_fran')

    def test_a_slot_after_a_piece_stands_alone(self):
        blocks = sb.for_archetype(COMPLEX)
        self.assertEqual([b['roles'] for b in blocks],
                         [['warm_up'], ['complex', 'clean', 'swing'], ['push_up_finisher']])

    def test_every_slot_is_in_one_block(self):
        for a in (FRAN, CINDY, COMPLEX):
            roles = [r for b in sb.for_archetype(a) for r in b['roles']]
            self.assertEqual(roles, [s['role'] for s in a['slots']])

    def test_a_movement_without_a_parent_follows_a_piece(self):
        a = arch(slot('p', 'amrap', duration_sec=600), slot('m', 'amrap_movement', reps_per_round=5),
                 slot('s', sets=3, reps=5), slot('lone', 'amrap_movement', reps_per_round=5))
        self.assertEqual([b['roles'] for b in sb.for_archetype(a)], [['p', 'm'], ['s'], ['lone']])


class Words(unittest.TestCase):

    def headline(self, *slots):
        return sb.for_archetype(arch(*slots))[0]['headline']

    def test_headlines(self):
        self.assertEqual(sb.for_archetype(FRAN)[0]['headline'], '21-15-9 for time')
        self.assertEqual(sb.for_archetype(CINDY)[0]['headline'], '20 min AMRAP')
        self.assertEqual(sb.for_archetype(COMPLEX)[1]['headline'], '6 rounds')
        self.assertEqual(self.headline(slot('h', 'for_time', rounds=1, reps_per_round=100)), 'For time')
        self.assertEqual(self.headline(slot('h', 'rounds_for_time', rounds=3, duration_sec=720)),
                         '3 rounds for time')
        self.assertEqual(self.headline(slot('e', 'emom', rounds=20, reps_per_round=5)), 'Every minute × 20')
        self.assertEqual(self.headline(slot('e', 'emom', duration_sec=960)), 'Every minute × 16')
        self.assertEqual(self.headline(slot('t', 'amrap', sets=8, work_sec=20, rest_sec=10)),
                         '8 × 20 s on / 10 s off')
        self.assertEqual(self.headline(slot('s', sets=3, reps=5)), '3 × 5')
        self.assertEqual(self.headline(slot('s', sets=3, reps='max')), '3 × max')
        self.assertEqual(self.headline(slot('s', sets=3, reps='8 each side')), '3 × 8 each side')
        self.assertEqual(self.headline(slot('z', 'time_domain', duration_minutes=40)), '40 min')
        self.assertEqual(self.headline(slot('d', 'distance', distance_m=5000)), '5 km')
        self.assertEqual(self.headline(slot('d', 'distance', distance_m=400, sets=4)), '4 × 400 m')
        self.assertEqual(self.headline(slot('h', 'static_hold', sets=3, hold_seconds=30)), '3 × 30 s hold')
        self.assertEqual(self.headline(slot('p', 'skill_practice', sets=3, duration_sec=300)), '3 × 5 min')

    def test_a_movement_never_reads_as_many_as_possible(self):
        for a in (FRAN, CINDY, COMPLEX):
            for b in sb.for_archetype(a):
                for text in [b['headline']] + [m['count'] or '' for m in b['movements']]:
                    self.assertNotIn('as many', text)
                    self.assertNotIn('1 rounds', text)

    def test_the_lead_is_a_movement_with_its_own_count(self):
        counts = [m['count'] for m in sb.for_archetype(CINDY)[0]['movements']]
        self.assertEqual(counts, ['5', '10', '15'])

    def test_rest(self):
        self.assertEqual(sb.for_archetype(COMPLEX)[1]['rest'],
                         {'seconds': 150, 'between': 'rounds', 'text': '2 min 30 s rest between rounds'})
        self.assertEqual(sb.for_archetype(COMPLEX)[2]['rest']['between'], 'sets')
        after = sb.for_archetype(arch(slot('z', 'time_domain', duration_minutes=10, rest_sec=120)))[0]['rest']
        self.assertEqual((after['between'], after['text']), ('after', '2 min rest'))
        # An interval's rest is in its headline, said once.
        self.assertIsNone(sb.for_archetype(arch(slot('t', 'amrap', sets=8, work_sec=20, rest_sec=10)))[0]['rest'])

    def test_a_cap(self):
        b = sb.for_archetype(arch(slot('h', 'rounds_for_time', rounds=3, duration_sec=720)))[0]
        self.assertEqual((b['repeat']['capMin'], b['cap']), (12, '12 min cap'))


class Shapes(unittest.TestCase):

    def shape(self, *slots):
        return sb.for_archetype(arch(*slots))[0]['shape']

    def test_ladder_and_pyramid(self):
        self.assertEqual(self.shape(slot('l', sets=4, reps='1-2-3-4-5 each side')), 'ladder')
        ladder = sb.for_archetype(arch(slot('l', sets=4, reps='1-2-3-4-5 each side')))[0]
        self.assertEqual(ladder['headline'], '4 × 1-2-3-4-5 each side')
        self.assertEqual(ladder['repeat'], {'sets': 4, 'scheme': [1, 2, 3, 4, 5]})
        self.assertEqual(self.shape(slot('p', 'rounds_for_time', rounds=5, rest_sec=90, rep_scheme=[3, 4, 5, 4, 3])),
                         'pyramid')
        # A falling scheme is neither, and a raced piece keeps its own shape.
        self.assertEqual(sb.for_archetype(FRAN)[0]['shape'], 'for_time')
        self.assertEqual(self.shape(slot('s', sets=3, rep_scheme=[10, 8, 6])), 'sets')

    def test_rounds_with_a_rest_are_not_raced(self):
        self.assertEqual(sb.for_archetype(COMPLEX)[1]['shape'], 'rounds')
        self.assertEqual(self.shape(slot('h', 'rounds_for_time', rounds=3)), 'for_time')

    def test_the_rest(self):
        self.assertEqual(self.shape(slot('e', 'emom', duration_sec=600)), 'emom')
        self.assertEqual(self.shape(slot('t', 'time_domain', sets=6, duration_sec=30, rest_sec=30)), 'interval')
        self.assertEqual(self.shape(slot('n', 'skill_practice', skip_exercise=True)), 'note')
        self.assertEqual(self.shape(slot('h', 'static_hold', sets=3, hold_seconds=30)), 'hold')


class Stages(unittest.TestCase):

    def test_by_role(self):
        for role, stage in [('warm_up', 'prep'), ('warmup', 'prep'), ('prep', 'prep'), ('joint_mobility', 'prep'),
                            ('cool_down', 'cooldown'), ('cooldown', 'cooldown'), ('cool_down_squat', 'cooldown'),
                            ('recovery', 'cooldown'), ('push_up_finisher', 'finisher'), ('primary_squat', 'main'),
                            ('prepare_to_die', 'main')]:
            self.assertEqual(sb.stage_of(role), stage, role)

    def test_a_written_stage_wins(self):
        self.assertEqual(sb.stage_of('swings', 'finisher'), 'finisher')
        self.assertEqual(sb.stage_of('warm_up', 'main'), 'main')
        self.assertEqual(sb.stage_of('swings', 'nonsense'), 'main')
        b = sb.for_archetype(arch(slot('swings', sets=3, reps=20, stage='finisher')))[0]
        self.assertEqual(b['stage'], 'finisher')

    def test_a_composed_day(self):
        self.assertEqual(sb.stage_of('warm_up__w1__jog'), 'prep')
        self.assertEqual(sb.stage_of('p2__cool_down'), 'cooldown')
        self.assertEqual(sb.stage_of('p2__fran'), 'main')

    def test_the_example(self):
        self.assertEqual([b['stage'] for b in sb.for_archetype(COMPLEX)], ['prep', 'main', 'finisher'])

    def test_every_stage_has_a_label(self):
        for stage in sb.stages():
            self.assertTrue(sb.stage_label(stage))


class Movements(unittest.TestCase):

    def test_a_listed_slot_names_its_movement(self):
        pools = {'fran': {'exercises': [{'id': 'thruster', 'name': 'Thruster'}], 'listed': True},
                 'fran_2': {'exercises': [{'id': f'e{i}', 'name': f'E{i}'} for i in range(9)], 'listed': False}}
        first, second = sb.for_archetype(FRAN, pools)[0]['movements']
        self.assertEqual(first['name'], 'Thruster')
        # A filter has no movement of its own: its role, and what may fill it.
        self.assertEqual((second['name'], len(second['exercises']), second['more']), ('Fran 2', 6, 3))

    def test_a_group_is_carried(self):
        g = {'id': 'a', 'kind': 'superset'}
        blocks = sb.for_archetype(arch(slot('squat', sets=4, reps=6, group=g), slot('row', sets=4, reps=8, group=g)))
        self.assertEqual([b['group'] for b in blocks], [g, g])


def assignment(role, slot_type, load, name=None, **kw):
    return {'slot_role': role, 'slot_type': slot_type, 'load': load,
            'exercise': {'id': role, 'name': name or role.title()}, **kw}


class Sessions(unittest.TestCase):

    SESSION = {'archetype': {'id': 'cf_fran', 'slots': [{'role': 'swings', 'stage': 'finisher'}]}, 'exercises': [
        assignment('warm_up__w1__jog', 'time_domain', {'duration_minutes': 10}, 'Easy jog'),
        assignment('fran', 'for_time', {'target_rounds': 3, 'format': 'FOR TIME', 'rep_scheme': [21, 15, 9]},
                   'Thruster', load_note='43 kg'),
        assignment('fran_2', 'amrap_movement', {'rep_scheme': [21, 15, 9]}, 'Pull-up', parent_slot_role='fran'),
        assignment('squat', 'sets_reps', {'sets': 3, 'reps': 5, 'weight_kg': 100}, 'Back squat', rest_sec=180),
        assignment('swings', 'sets_reps', {'sets': 3, 'reps': 20}, 'Swing'),
    ]}

    def test_a_session_reads_as_its_archetype_does(self):
        blocks = sb.for_session(self.SESSION)
        self.assertEqual([b['stage'] for b in blocks], ['prep', 'main', 'main', 'finisher'])
        self.assertEqual([b['headline'] for b in blocks], ['10 min', '21-15-9 for time', '3 × 5', '3 × 20'])
        self.assertEqual([m['name'] for m in blocks[1]['movements']], ['Thruster', 'Pull-up'])
        self.assertEqual(blocks[1]['load'], '43 kg')
        self.assertEqual(blocks[2]['rest']['text'], '3 min rest between sets')
        self.assertEqual(blocks[0]['title'], 'Jog')

    def test_a_generated_amrap_shows_no_forecast_of_rounds(self):
        s = {'exercises': [assignment('a', 'amrap', {'time_minutes': 12, 'target_rounds': 5, 'format': 'AMRAP'})]}
        self.assertEqual(sb.for_session(s)[0]['headline'], '12 min AMRAP')

    def test_an_interval(self):
        s = {'exercises': [assignment('i', 'emom', {'target_rounds': 10, 'work_sec': 30, 'rest_sec': 30,
                                                    'time_minutes': 10, 'format': 'EMOM'})]}
        b = sb.for_session(s)[0]
        self.assertEqual((b['headline'], b['rest']), ('Every minute × 10', None))

    def test_derived_on_read_never_stored(self):
        weeks = [{'week_number': 1, 'schedule': {'Monday': [dict(self.SESSION)], 'Tuesday': []}}]
        served = sb.with_blocks(weeks)
        self.assertTrue(served[0]['schedule']['Monday'][0]['blocks'])
        self.assertNotIn('blocks', weeks[0]['schedule']['Monday'][0])
        stripped = sb.strip({'weeks': served})
        self.assertNotIn('blocks', stripped['weeks'][0]['schedule']['Monday'][0])
        plain = {'weeks': weeks}
        self.assertIs(sb.strip(plain), plain)
        a = {'currentProgram': {'weeks': served}}
        b = {'currentProgram': {'weeks': weeks}}
        self.assertEqual(program_history.content_hash(a), program_history.content_hash(b))


class RealData(unittest.TestCase):

    def test_every_shipped_archetype(self):
        seen = set()
        for a in loader.load_all_archetypes():
            slots = [s for s in a.get('slots') or [] if s.get('role')]
            blocks = sb.for_archetype(a)
            self.assertEqual([r for b in blocks for r in b['roles']], [s['role'] for s in slots], a['id'])
            for b in blocks:
                seen.add(b['shape'])
                self.assertIn(b['stage'], sb.stages(), a['id'])
                for m in b['movements']:
                    self.assertNotIn('as many', m['count'] or '', a['id'])
        self.assertTrue({'sets', 'for_time', 'amrap', 'emom', 'timed', 'distance', 'hold'} <= seen, seen)

    def test_a_child_always_sits_in_its_parents_block(self):
        for a in loader.load_all_archetypes():
            by_role = {r: b for b in sb.for_archetype(a) for r in b['roles']}
            for s in a.get('slots') or []:
                if s.get('parent_slot_role'):
                    self.assertEqual(by_role[s['role']]['id'], s['parent_slot_role'], a['id'])


if __name__ == '__main__':
    unittest.main(verbosity=1)
