#!/usr/bin/env python
"""Assert generated programs only contain content their philosophy is allowed to use.

A philosophy package is meant to be self-contained. Every archetype, exercise
and complementary prescription in a generated program must come from the
philosophy's own package or from one it declares in `borrows_from`.

Usage:
  .venv/bin/python tools/check_provenance.py             # generate + assert
  .venv/bin/python tools/check_provenance.py --coverage  # static coverage gaps only
  .venv/bin/python tools/check_provenance.py --quick     # one constraint profile

Exits non-zero when a package marked `self_contained: true` leaks.
"""
from __future__ import annotations

import os
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from src import goals, loader, provenance  # noqa: E402
from src.generator import generate  # noqa: E402

ALL_EQUIPMENT = [
    'barbell', 'rack', 'plates', 'kettlebell', 'pull_up_bar', 'ruck_pack',
    'open_space', 'sandbag', 'rower', 'box', 'medicine_ball', 'sled', 'tire',
    'rope', 'dumbbell', 'bench', 'gymnastics_rings', 'jump_rope', 'bike',
    'treadmill', 'trap_bar', 'ghd', 'parallettes',
]

PROFILES = [
    {'days_per_week': 3, 'session_time_minutes': 45, 'training_level': 'novice'},
    {'days_per_week': 5, 'session_time_minutes': 75, 'training_level': 'intermediate'},
    {'days_per_week': 6, 'session_time_minutes': 120, 'training_level': 'advanced'},
]
QUICK_PROFILES = PROFILES[1:2]


def constraints_for(profile: dict) -> dict:
    return {
        **profile,
        'equipment': list(ALL_EQUIPMENT),
        'injury_flags': [],
        'training_phase': 'base',
        'periodization_week': 1,
        'fatigue_state': 'normal',
    }


def sessions_of(raw: dict):
    for week in raw.get('weeks', []):
        for day in week.get('schedule', {}).values():
            for session in day:
                yield session


def audit_program(raw: dict, policy, ex_index: dict) -> dict:
    """Return {'archetypes': Counter(package), 'exercises': Counter, 'foreign': [...]}"""
    arch_pkgs: Counter = Counter()
    ex_pkgs: Counter = Counter()
    foreign: list = []

    for session in sessions_of(raw):
        arch = session.get('archetype')
        if arch:
            pkg = arch.get('_package')
            arch_pkgs[pkg] += 1
            if not provenance.allows_archetype(arch, policy):
                foreign.append(f"archetype {arch.get('id')} from {pkg}")

        assignments = list(session.get('exercises') or [])
        modality = session.get('modality')
        for assignment in assignments:
            ex = assignment.get('exercise')
            if not ex:
                continue
            full = ex_index.get(ex.get('id'), ex)
            pkgs = provenance.exercise_packages(full)
            ex_pkgs[pkgs[0] if pkgs else None] += 1
            if not provenance.allows_exercise(full, policy, modality):
                foreign.append(f"exercise {ex.get('id')} from {pkgs}")

        # Complementary work drew from the unfiltered global index and is the
        # easiest regression to reintroduce — audit it explicitly.
        for comp in session.get('complementary_work') or []:
            ex = comp.get('exercise') if isinstance(comp, dict) and 'exercise' in comp else comp
            if not isinstance(ex, dict) or 'id' not in ex:
                continue
            full = ex_index.get(ex['id'], ex)
            pkgs = provenance.exercise_packages(full)
            ex_pkgs[pkgs[0] if pkgs else None] += 1
            if not provenance.allows_exercise(full, policy):
                foreign.append(f"complementary {ex['id']} from {pkgs}")

    return {'archetypes': arch_pkgs, 'exercises': ex_pkgs, 'foreign': foreign}


def report_coverage() -> int:
    """Static: modalities a package declares or prescribes but owns no archetype for."""
    frameworks = list(loader.load_all_frameworks().values())
    data = loader.load_all_data()
    total_blocking = 0

    print(f"{'package':22} {'blocking (framework prescribes)':46} other scope gaps")
    print('-' * 110)
    for phil in sorted(loader.load_philosophies(), key=lambda p: p['id']):
        phil_id = phil['id']
        archetypes = [a for a in data['archetypes'] if a.get('_package') == phil_id]
        have = {a.get('modality') for a in archetypes}

        prescribed: set = set()
        for fw in frameworks:
            if fw.get('source_philosophy') == phil_id:
                prescribed |= set((fw.get('sessions_per_week') or {}).keys())

        blocking = sorted(prescribed - have)
        other = sorted(set(phil.get('scope', [])) - have - set(blocking))
        total_blocking += len(blocking)
        print(f"{phil_id:22} {', '.join(blocking) or '-':46} {', '.join(other) or '-'}")

    print(f"\n{total_blocking} blocking coverage gap(s) across all packages.")
    return 0


def main() -> int:
    if '--coverage' in sys.argv:
        return report_coverage()

    profiles = QUICK_PROFILES if '--quick' in sys.argv else PROFILES
    frameworks = list(loader.load_all_frameworks().values())
    data = loader.load_all_data()
    ex_index = data['exercises']

    failures: list = []
    tot_sessions = tot_foreign_sessions = 0
    tot_ex = tot_foreign_ex = 0

    for phil in sorted(loader.load_philosophies(), key=lambda p: p['id']):
        phil_id = phil['id']
        goal = goals.philosophy_to_goal(phil_id, frameworks)
        policy = provenance.resolve_source_policy(goal)

        sessions = foreign_sessions = n_ex = foreign_ex = 0
        leak_samples: list = []
        for profile in profiles:
            raw = generate(goal_id=goal['id'], goal_dict=goal,
                           constraints=constraints_for(profile), num_weeks=4,
                           output_format='dict')
            audit = audit_program(raw, policy, ex_index)
            sessions += sum(audit['archetypes'].values())
            n_ex += sum(audit['exercises'].values())
            arch_leaks = [f for f in audit['foreign'] if f.startswith('archetype')]
            foreign_sessions += len(arch_leaks)
            foreign_ex += len(audit['foreign']) - len(arch_leaks)
            leak_samples.extend(audit['foreign'][:3])

        tot_sessions += sessions
        tot_foreign_sessions += foreign_sessions
        tot_ex += n_ex
        tot_foreign_ex += foreign_ex

        flag = 'strict' if policy.strict else '     '
        status = 'clean' if not (foreign_sessions or foreign_ex) else 'LEAKS'
        print(f"  {phil_id:22} {flag}  sessions {foreign_sessions:3}/{sessions:3} foreign  "
              f"exercises {foreign_ex:4}/{n_ex:4} foreign  {status}")

        if policy.strict and (foreign_sessions or foreign_ex):
            failures.append(
                f"{phil_id}: {foreign_sessions} foreign sessions, "
                f"{foreign_ex} foreign exercises, e.g. {leak_samples[:3]}"
            )

    pct_s = 100 * tot_foreign_sessions / max(tot_sessions, 1)
    pct_e = 100 * tot_foreign_ex / max(tot_ex, 1)
    print(f"\nTOTAL sessions {tot_foreign_sessions}/{tot_sessions} foreign ({pct_s:.0f}%)"
          f" | exercises {tot_foreign_ex}/{tot_ex} foreign ({pct_e:.0f}%)")

    if failures:
        print(f"\n{len(failures)} self_contained package(s) leaked:")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("\nNo self_contained package leaked.")
    return 0


if __name__ == '__main__':
    sys.exit(main())
