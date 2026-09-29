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


def _valid_exercise_categories() -> set:
    import json
    schema_path = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        'docs', 'schemas', 'exercise.schema.json')
    with open(schema_path) as f:
        schema = json.load(f)
    items = schema.get('items', schema)
    return set(items.get('properties', {}).get('category', {}).get('enum', []))


def report_authoring() -> list:
    """Cross-file checks a per-file schema pass cannot make.

    Each of these caught a real defect: gym_jones filtered a slot on a movement
    pattern no exercise carries, ido_portal filtered on a category that is not in
    the enum, and ido_portal declared a phase no archetype supports.
    """
    from src import selector

    problems: list = []
    data = loader.load_all_data()
    installed = {p['id'] for p in loader.load_philosophies()}
    valid_categories = _valid_exercise_categories()

    # Resolve slot patterns exactly the way select_exercise does: an alias from
    # data/commons/movement_patterns.yaml, or a raw pattern some exercise carries.
    known_patterns: set = set(selector._PATTERN_ALIASES)
    for ex in data['exercises'].values():
        known_patterns.update(ex.get('movement_patterns') or [])

    # 1. borrows_from must reference an installed package, and never itself.
    for phil in loader.load_philosophies():
        for entry in phil.get('borrows_from', []) or []:
            pkg = entry.get('package') if isinstance(entry, dict) else entry
            if pkg == phil['id']:
                problems.append(f"{phil['id']}: borrows_from references itself")
            elif pkg not in installed:
                problems.append(f"{phil['id']}: borrows_from references unknown package {pkg!r}")

    # 2/3. Slot filters must be satisfiable in principle.
    for arch in data['archetypes']:
        for slot in arch.get('slots', []) or []:
            ex_filter = slot.get('exercise_filter') or {}
            pattern = ex_filter.get('movement_pattern')
            if pattern and pattern not in known_patterns:
                problems.append(
                    f"{arch.get('_package')}/{arch['id']}: slot "
                    f"{slot.get('role')!r} filters on movement_pattern {pattern!r}, "
                    f"which no exercise carries")
            category = ex_filter.get('category')
            if category and valid_categories and category not in valid_categories:
                problems.append(
                    f"{arch.get('_package')}/{arch['id']}: slot "
                    f"{slot.get('role')!r} filters on category {category!r}, "
                    f"not a valid exercise category")

    # 4. Every phase a philosophy schedules needs an archetype that claims it.
    for phil in loader.load_philosophies():
        phil_id = phil['id']
        archetypes = [a for a in data['archetypes'] if a.get('_package') == phil_id]
        claimed: set = set()
        for arch in archetypes:
            claimed.update(arch.get('applicable_phases') or [])
        declared: set = set()
        for group in phil.get('framework_groups', []) or []:
            for entry in group.get('canonical_phase_sequence', []) or []:
                declared.add(entry.get('phase'))
        for entry in phil.get('canonical_phase_sequence', []) or []:
            declared.add(entry.get('phase'))
        for phase in sorted(p for p in declared if p):
            if claimed and phase not in claimed:
                problems.append(
                    f"{phil_id}: declares phase {phase!r} but no archetype in the "
                    f"package lists it in applicable_phases")

    # 5. A package's analytics.yaml may only name what the package owns or
    #    borrows. The self-containment rule for programs, applied to the
    #    declarations that measure them: a philosophy that ships its own
    #    analytics cannot quietly reach into another package's exercises.
    problems.extend(_report_analytics_specs(data, installed))

    return problems


def _report_analytics_specs(data: dict, installed: set) -> list:
    from src.provenance import SourcePolicy, _parse_borrows

    problems: list = []
    arch_owner = {a['id']: a.get('_package') for a in data['archetypes']}
    benchmark_ids = _known_benchmark_ids()
    modality_ids = set(data['modalities'])
    frameworks = loader.load_all_frameworks()

    for pkg, spec in loader.load_analytics_specs().items():
        if spec.get('id') != pkg:
            problems.append(f"{pkg}/analytics.yaml: id {spec.get('id')!r} must equal the package")
        if pkg not in installed:
            problems.append(f"{pkg}/analytics.yaml: no philosophy.yaml beside it")
            continue
        phil = loader.load_philosophy(pkg)
        policy = SourcePolicy(owner_packages=frozenset({pkg}), borrows=_parse_borrows(phil))
        allowed = policy.allowed_packages

        def owned_exercise(ex_id: str) -> bool:
            ex = data['exercises'].get(ex_id)
            return bool(ex) and bool(set(ex.get('_packages') or []) & allowed)

        for entry in spec.get('progress') or []:
            scope = entry.get('scope') or {}
            where = f"{pkg}/analytics.yaml: {entry.get('id')!r}"
            for ex_id in scope.get('exercises') or []:
                if not owned_exercise(ex_id):
                    problems.append(f"{where} scopes exercise {ex_id!r}, which the package "
                                    f"neither owns nor borrows")
            for arch_id in scope.get('archetypes') or []:
                if arch_owner.get(arch_id) not in allowed:
                    problems.append(f"{where} scopes archetype {arch_id!r}, which the package "
                                    f"neither owns nor borrows")
            for mod in scope.get('modalities') or []:
                if mod not in modality_ids:
                    problems.append(f"{where} scopes unknown modality {mod!r}")
            for fw_id in scope.get('frameworks') or []:
                fw = frameworks.get(fw_id)
                if not fw or fw.get('source_philosophy') != pkg:
                    problems.append(f"{where} scopes framework {fw_id!r}, not this package's")
            for b in entry.get('benchmarks') or []:
                if b not in benchmark_ids:
                    problems.append(f"{where} names unknown benchmark {b!r}")
        for b in spec.get('benchmarks') or []:
            if b not in benchmark_ids:
                problems.append(f"{pkg}/analytics.yaml: names unknown benchmark {b!r}")
    return problems


def _known_benchmark_ids() -> set:
    """Every benchmark id the API can serve, read from data/benchmarks directly."""
    import yaml
    root = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                        'data', 'benchmarks')
    ids: set = {'bodyweight_kg'}
    for name in ('strength_standards.yaml', 'conditioning_standards.yaml'):
        path = os.path.join(root, name)
        if os.path.exists(path):
            with open(path, encoding='utf-8') as f:
                for item in yaml.safe_load(f) or []:
                    if isinstance(item, dict) and item.get('id'):
                        ids.add(item['id'])
    cell = os.path.join(root, 'cell_standards.yaml')
    if os.path.exists(cell):
        with open(cell, encoding='utf-8') as f:
            for domain, entries in ((yaml.safe_load(f) or {}).get('standards') or {}).items():
                for ex in (entries or {}):
                    ids.add(f'cell_{domain}_{ex}')
    return ids


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

    problems = report_authoring()
    print()
    if problems:
        print(f"{len(problems)} authoring problem(s):")
        for p in problems:
            print(f"  - {p}")
        return 1
    print('No authoring problems.')
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
