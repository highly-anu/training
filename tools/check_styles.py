#!/usr/bin/env python
"""Every training style a philosophy offers must validate and generate.

Guards the class of bug where a philosophy's framework_groups listed a style that
the synthetic goal never exposed, so the validator rejected it as belonging to
another philosophy (horsemen_gpp/gpp_circuits, wildman_kettlebell/kb_general_practice).

Usage:  .venv/bin/python tools/check_styles.py
Exits non-zero if any philosophy x style combination fails at its own
framework `expectations` minimums.
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from src import goals, loader  # noqa: E402
from src.generator import generate  # noqa: E402
from src.validator import validate  # noqa: E402

# Everything, so equipment is never the reason a style fails here.
ALL_EQUIPMENT = [
    'barbell', 'rack', 'plates', 'kettlebell', 'pull_up_bar', 'ruck_pack',
    'open_space', 'sandbag', 'rower', 'box', 'medicine_ball', 'sled', 'tire',
    'rope', 'dumbbell', 'bench', 'gymnastics_rings', 'jump_rope', 'bike',
    'treadmill', 'trap_bar', 'ghd', 'parallettes', 'sled_harness',
]


def styles_of(goal: dict) -> list:
    fs = goal.get('framework_selection', {})
    return [fs['default_framework']] + [
        alt['framework_id'] for alt in fs.get('alternatives', [])
    ]


def main() -> int:
    frameworks = list(loader.load_all_frameworks().values())
    fw_by_id = {f['id']: f for f in frameworks}
    data = loader.load_all_data()

    failures: list[str] = []
    for phil in sorted(loader.load_philosophies(), key=lambda p: p['id']):
        phil_id = phil['id']
        goal = goals.philosophy_to_goal(phil_id, frameworks)
        archetypes = [a for a in data['archetypes'] if a.get('_package') == phil_id]

        for style_id in styles_of(goal):
            fw = fw_by_id.get(style_id)
            if fw is None:
                failures.append(f"{phil_id}/{style_id}: framework file not found")
                print(f"  {phil_id:20} {style_id:28} MISSING FRAMEWORK")
                continue

            exp = fw.get('expectations', {})
            constraints = {
                'days_per_week': exp.get('ideal_days_per_week')
                or exp.get('min_days_per_week', 4),
                'session_time_minutes': exp.get('ideal_session_minutes')
                or exp.get('min_session_minutes', 60),
                'training_level': 'intermediate',
                'equipment': ALL_EQUIPMENT,
                'injury_flags': [],
                'training_phase': 'base',
                'periodization_week': 1,
                'fatigue_state': 'normal',
                'forced_framework': style_id,
            }

            result = validate(goal, constraints, archetypes,
                              data['modalities'], data['injury_flags'])
            sessions = 0
            if result.feasible:
                raw = generate(goal_id=goal['id'], goal_dict=goal,
                               constraints=constraints, num_weeks=2,
                               output_format='dict')
                sessions = sum(
                    len(day) for week in raw.get('weeks', [])
                    for day in week.get('schedule', {}).values()
                )

            ok = result.feasible and sessions > 0
            codes = [e['code'] for e in result.errors]
            print(f"  {phil_id:20} {style_id:28} "
                  f"sessions={sessions:3} {'ok' if ok else 'FAIL ' + str(codes)}")
            if not ok:
                failures.append(f"{phil_id}/{style_id}: {codes or 'generated 0 sessions'}")

    print()
    if failures:
        print(f"{len(failures)} style combination(s) failed:")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("All philosophy x style combinations validate and generate.")
    return 0


if __name__ == '__main__':
    sys.exit(main())
