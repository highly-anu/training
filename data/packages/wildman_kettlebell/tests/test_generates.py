#!/usr/bin/env python
"""Wildman Kettlebell's default track generates at an ordinary athlete's
constraints — one kettlebell, four days, an hour — and validates feasible.
(Every track at the constraints its contract asks for: tools/check_styles.py.) A
package's own test (data/packages/<id>/tests/; the package is this folder's,
`PKG`); it was test_wildman.py at the root, a script that printed week one.

    .venv/bin/python data/packages/wildman_kettlebell/tests/test_generates.py
"""
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
PKG = HERE.parents[1].name                      # the package these tests are about: its folder
sys.path.insert(0, str(HERE.parents[4]))        # the checkout (data/packages/<id>/tests/)
os.environ.setdefault('SUPABASE_URL', '')

from src import goals, loader  # noqa: E402
from src.generator import generate  # noqa: E402
from src.validator import validate  # noqa: E402

CONSTRAINTS = {
    'equipment': ['kettlebell'],
    'days_per_week': 4,
    'session_time_minutes': 60,
    'training_level': 'intermediate',
}


def test_default_track_generates_at_ordinary_constraints():
    data = loader.load_all_data()
    archetypes = [a for a in data['archetypes'] if a.get('_package') == PKG]
    goal = goals.philosophy_to_goal(PKG, list(loader.load_all_frameworks().values()))
    validation = validate(goal, CONSTRAINTS, archetypes, data['modalities'], data['injury_flags'])
    assert validation.feasible, validation.errors
    result = generate(goal_id=None, constraints=CONSTRAINTS, num_weeks=4, output_format='dict', goal_dict=goal)
    assert len(result['weeks']) == 4, len(result['weeks'])
    sessions = sum(len(s) for s in result['weeks'][0]['schedule'].values())
    assert sessions > 0, 'no sessions in week one'
    print(f"  ok   {goal['track']['id']}: 4 weeks, {sessions} sessions in week one")


if __name__ == '__main__':
    test_default_track_generates_at_ordinary_constraints()
    print('all passed')
