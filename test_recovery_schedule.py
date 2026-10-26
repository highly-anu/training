"""The scheduler's recovery windows hold both ways and across the week.

Modalities are placed hardest first, not in day order, so a check that looked
only at earlier days let a session land the day before another already there;
and nothing crossed the week, so a rotating cadence could put this Monday's
heavy day straight after last Sunday's. Run:
    SUPABASE_URL='' .venv/bin/python test_recovery_schedule.py
"""
import unittest
from unittest.mock import patch

from src import goals, loader, scheduler
from src.generator import generate
from src.package_eval import ALL_EQUIPMENT

MODS = loader.load_all_data()['modalities']


class RecoveryWindows(unittest.TestCase):
    def test_a_later_day_counts(self):
        # Power on Monday would sit a day before Tuesday's max strength.
        self.assertFalse(scheduler._recovery_safe(1, 'power', MODS['power'], {2: ['max_strength']}, MODS))
        self.assertTrue(scheduler._recovery_safe(1, 'power', MODS['power'], {3: ['max_strength']}, MODS))

    def test_last_weeks_end_counts(self):
        sunday = {7: ['max_strength']}
        self.assertFalse(scheduler._recovery_safe(1, 'max_strength', MODS['max_strength'], {}, MODS, prev_week=sunday))
        self.assertTrue(scheduler._recovery_safe(2, 'max_strength', MODS['max_strength'], {}, MODS, prev_week=sunday))
        placed = scheduler.assign_to_days({'max_strength': 1, 'aerobic_base': 2}, MODS, 3, [1, 3, 5],
                                          prev_week=sunday)
        self.assertEqual(placed[3], ['max_strength'])

    def test_a_framework_allowance_reaches_across_the_week(self):
        allowed = frozenset({frozenset({'strength_endurance'})})
        mod = MODS['strength_endurance']
        self.assertTrue(scheduler._recovery_safe(1, 'strength_endurance', mod, {}, MODS, allowed,
                                                 prev_week={7: ['strength_endurance']}))

    def test_a_session_placed_inside_its_window_says_so(self):
        notes: list = []
        placed = scheduler.assign_to_days({'max_strength': 3}, MODS, 3, [1, 2, 3], compromises=notes)
        self.assertEqual(sum(len(v) for v in placed.values()), 3)
        self.assertEqual(notes, ['max strength placed inside its recovery window (not enough days apart)'])

    def test_the_generator_passes_last_week_on(self):
        frameworks = list(loader.load_all_frameworks().values())
        # A blend led by a training contract runs on the scheduler.
        goal = goals.blend_philosophy_goals(['uphill_athlete', 'horsemen_gpp'],
                                            {'uphill_athlete': 0.7, 'horsemen_gpp': 0.3}, frameworks)
        constraints = {'days_per_week': 6, 'session_time_minutes': 60, 'training_level': 'intermediate',
                       'equipment': ALL_EQUIPMENT, 'injury_flags': [], 'periodization_week': 1,
                       'fatigue_state': 'normal'}
        seen = []
        real = scheduler.schedule_week

        def spy(*args, **kwargs):
            seen.append(kwargs.get('prev_week'))
            return real(*args, **kwargs)

        with patch('src.generator.schedule_week', spy):
            program = generate(None, constraints, num_weeks=2, goal_dict=goal, output_format='dict')
        self.assertIsNone(seen[0])
        first = {d: [s['modality'] for s in ss] for d, ss in program['weeks'][0]['schedule'].items()}
        self.assertEqual({d: m for d, m in seen[1].items() if m}, {d: m for d, m in first.items() if m})


if __name__ == '__main__':
    unittest.main()
