"""Every philosophy x track: which of its analytics measures the generated
program schedules, and which one leads.

    .venv/bin/python tools/check_analytics.py            # table + verdict
    .venv/bin/python tools/check_analytics.py -p crossfit  # one philosophy

A measure that no session of a program is in scope for is `applies: false`
(src/analytics/document.py) — shown as "not in this program". That is right
for a measure of another track (Wildman's cadence outside Pentathlon Prep),
and wrong for one that applies in no track at all: Wildman's Ballistic load
scoped to sets×reps slots no power session had, and measured nothing for
months. This check fails on a declared measure that applies in none of its
philosophy's tracks, and on a philosophy whose headline applies nowhere.

No logs, no database: applicability depends only on the plan.
"""
from __future__ import annotations

import argparse
import os
import sys
from datetime import date, timedelta

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('SUPABASE_URL', '')

from src import generator, goals, loader, phases  # noqa: E402
from src.analytics.context import AnalyticsInputs  # noqa: E402
from src.analytics.document import compute_program_analytics  # noqa: E402

CONSTRAINTS = {
    'training_level': 'intermediate', 'days_per_week': 5, 'session_time_minutes': 75,
    'equipment': ['barbell', 'rack', 'plates', 'kettlebell', 'pull_up_bar', 'ruck_pack', 'rings',
                  'open_space', 'box', 'sandbag', 'dumbbell', 'sled', 'rower', 'bike', 'jump_rope',
                  'bench', 'mat', 'parallettes', 'wall', 'bands'],
    'injury_flags': [], 'periodization_week': 1, 'fatigue_state': 'normal',
}
WEEKS = 12


def run(only: str | None = None) -> int:
    fw_by_id = loader.load_all_frameworks()
    frameworks = list(fw_by_id.values())
    declared = loader.load_analytics_specs()
    problems: list[str] = []
    for phil in loader.load_philosophies():
        pid = phil['id']
        if only and pid != only:
            continue
        applies_anywhere: dict[str, bool] = {}
        headline_anywhere = False
        source = 'declared' if pid in declared else 'default'
        print(f'\n{pid} ({source})')
        for track in phases.tracks_of(phil):
            goal = goals.philosophy_to_goal(pid, frameworks, track_id=track['id'])
            # The track's first framework says what it is built for: a
            # three-day novice method generates nothing at five days.
            first = (track.get('phases') or [{}])[0].get('framework_id')
            exp = (fw_by_id.get(first) or {}).get('expectations') or {}
            cons = dict(CONSTRAINTS,
                        days_per_week=exp.get('ideal_days_per_week') or CONSTRAINTS['days_per_week'],
                        session_time_minutes=exp.get('ideal_session_minutes') or CONSTRAINTS['session_time_minutes'])
            prog = generator.generate(goal_id=goal['id'], goal_dict=goal, constraints=cons,
                                      num_weeks=WEEKS, output_format='dict')
            start = date(2026, 1, 5)
            doc = compute_program_analytics(AnalyticsInputs(
                {'goal': goal, 'constraints': cons, 'weeks': prog['weeks']},
                start, start + timedelta(days=7 * 3 + 2)))
            m = doc['methodologies'][0]
            print(f"  track {track['id']}: headline {m['headlineId']} · "
                  f"{m.get('applicable')} of {m['total']} apply")
            for p in doc['progress']:
                planned = p['programScope']['planned']
                applies_anywhere[p['id']] = applies_anywhere.get(p['id'], False) or p['applies']
                if p['headline'] and p['applies']:
                    headline_anywhere = True
                mark = '*' if p['headline'] else ' '
                print(f"    {mark} {p['id']:<28} {p['primitive']:<16} "
                      f"{'applies' if p['applies'] else 'not in this program':<20} {planned:>3} sessions")
        if source == 'declared':
            for eid, ok in applies_anywhere.items():
                if not ok:
                    problems.append(f'{pid}: {eid} applies in none of its tracks')
        if applies_anywhere and not headline_anywhere:
            problems.append(f'{pid}: its headline applies in none of its tracks')

    print()
    if problems:
        print(f'{len(problems)} problem(s):')
        for p in problems:
            print(f'  - {p}')
        return 1
    print('Every declared measure applies in at least one track; every headline leads somewhere.')
    return 0


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('-p', '--philosophy')
    sys.exit(run(ap.parse_args().philosophy))
