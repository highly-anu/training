#!/usr/bin/env python
"""Every phase of every track a philosophy offers must validate and generate,
on the framework that phase names.

Guards two classes of bug. A style the synthetic goal never exposed was
rejected as another philosophy's (horsemen_gpp/gpp_circuits,
wildman_kettlebell/kb_general_practice). And an explicit pick was silently
overridden: the old check forced a framework and only asserted sessions > 0,
so it passed while every week ran a different framework. Each phase here is
generated from its own start and the week's framework is compared with the
one the phase declares.

Usage:  .venv/bin/python tools/check_styles.py
Exits non-zero if any philosophy x track x phase fails at its framework's
`expectations`.
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from src import goals, loader, phases  # noqa: E402
from src.generator import generate  # noqa: E402
from src.validator import validate  # noqa: E402

# Everything, so equipment is never the reason a style fails here.
ALL_EQUIPMENT = [
    'barbell', 'rack', 'plates', 'kettlebell', 'pull_up_bar', 'ruck_pack',
    'open_space', 'sandbag', 'rower', 'box', 'medicine_ball', 'sled', 'tire',
    'rope', 'dumbbell', 'bench', 'gymnastics_rings', 'jump_rope', 'bike',
    'treadmill', 'trap_bar', 'ghd', 'parallettes', 'sled_harness',
]


def _days_for(track: dict, fw_by_id: dict) -> int:
    """A day count every framework in the track accepts, nearest the first
    phase's ideal."""
    first = fw_by_id.get(track['phases'][0]['framework_id'], {})
    exp = first.get('expectations', {})
    want = exp.get('ideal_days_per_week') or exp.get('min_days_per_week', 4)
    lo, hi = 1, 7
    for ph in track['phases']:
        aw = fw_by_id.get(ph['framework_id'], {}).get('applicable_when', {})
        lo = max(lo, aw.get('days_per_week_min', 1))
        hi = min(hi, aw.get('days_per_week_max', 7))
    return min(max(want, lo), hi)


def _test_problems(weeks: list, ph: dict) -> list[str]:
    from src import standard_tests
    problems = []
    for w in weeks:
        entry = {'tests': ph['tests'], 'phase_weeks': ph['weeks'], 'repeatable': ph.get('repeatable'),
                 'week_in_phase': w.get('week_in_phase')}
        want = standard_tests.tests_for_week(entry)
        got = [s for day in (w.get('schedule') or {}).values() for s in day if s.get('test')]
        if len(got) != len(want):
            why = [t.get('reason') for t in w.get('tests_skipped') or []]
            problems.append(f"week {w.get('week_in_phase')}: {len(got)} of {len(want)} tests placed {why or ''}".rstrip())
    return problems


def main() -> int:
    frameworks = list(loader.load_all_frameworks().values())
    fw_by_id = {f['id']: f for f in frameworks}
    data = loader.load_all_data()

    failures: list[str] = []
    for phil in sorted(loader.load_philosophies(), key=lambda p: p['id']):
        phil_id = phil['id']
        archetypes = [a for a in data['archetypes'] if a.get('_package') == phil_id]

        for track in phases.tracks_of(phil):
            goal = goals.philosophy_to_goal(phil_id, frameworks, track_id=track['id'])
            days = _days_for(track, fw_by_id)
            for ph in track['phases']:
                label = f"{phil_id}/{track['id']}/{ph['id']}"
                fw = fw_by_id.get(ph['framework_id'])
                if fw is None:
                    failures.append(f"{label}: framework '{ph['framework_id']}' not found")
                    print(f"  {label:52} MISSING FRAMEWORK")
                    continue
                exp = fw.get('expectations', {})
                constraints = {
                    'days_per_week': days,
                    'session_time_minutes': exp.get('ideal_session_minutes')
                    or exp.get('min_session_minutes', 60),
                    'training_level': 'intermediate',
                    'equipment': ALL_EQUIPMENT,
                    'injury_flags': [],
                    'start_phase': ph['id'],
                    'periodization_week': 1,
                    'fatigue_state': 'normal',
                }
                if goal.get('training_contract'):
                    constraints['kettlebell_count'] = 2
                    constraints['mastered_exercises'] = sorted({eid for m in goal['training_contract']['modules']
                        for eid in m.get('requires_mastery', [])})

                result = validate(goal, constraints, archetypes,
                                  data['modalities'], data['injury_flags'])
                sessions, ran = 0, None
                if result.feasible:
                    raw = generate(goal_id=goal['id'], goal_dict=goal,
                                   constraints=constraints, num_weeks=1,
                                   output_format='dict')
                    weeks = raw.get('weeks', [])
                    sessions = sum(len(day) for w in weeks
                                   for day in w.get('schedule', {}).values())
                    ran = weeks[0].get('framework') if weeks else None

                wrong_fw = ran is not None and ran != ph['framework_id']
                ok = result.feasible and sessions > 0 and not wrong_fw
                codes = [e['code'] for e in result.errors]
                why = codes or ([f"ran {ran}"] if wrong_fw else 'generated 0 sessions')
                print(f"  {label:52} days={days} sessions={sessions:3} "
                      f"{'ok' if ok else 'FAIL ' + str(why)}")
                if not ok:
                    failures.append(f"{label}: {why}")

                # A phase that tests: generated at full length, every declared
                # test must be placed — an intermediate with every piece of
                # equipment can do each one, so a skip here is authoring.
                if ok and ph.get('tests'):
                    raw = generate(goal_id=goal['id'], goal_dict=goal, constraints=constraints,
                                   num_weeks=int(ph['weeks']), output_format='dict')
                    problems = _test_problems(raw.get('weeks', []), ph)
                    print(f"  {label + ' (tests)':52} {'ok' if not problems else 'FAIL ' + '; '.join(problems)}")
                    failures += [f"{label}: {p}" for p in problems]

    print()
    if failures:
        print(f"{len(failures)} phase(s) failed:")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("Every philosophy x track x phase validates and generates on its own framework.")
    return 0


if __name__ == '__main__':
    sys.exit(main())
