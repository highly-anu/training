"""
Migrate exercises from data/exercises/*.yaml to data/packages/<id>/exercises.yaml.

Each philosophy package is fully self-contained: every exercise a philosophy trains
gets a complete entry in that package's exercises.yaml. An exercise with N sources
appears in N packages as an independent full entry, with package-specific prescription
fields (starting_load_kg, weekly_increment_kg) where applicable.

The global index in loader.py uses first-seen for structural deduplication — this is
only an implementation detail of the flat lookup, not an architectural ownership claim.
"""
from __future__ import annotations
import os
import glob
import yaml
from collections import defaultdict

# ---------------------------------------------------------------------------
# Source string → package ID mapping
# ---------------------------------------------------------------------------
_SOURCE_TO_PKG = {
    'Starting Strength': 'starting_strength',
    'Gym Jones':         'gym_jones',
    'Horsemen':          'horsemen_gpp',
    'Dan John':          'horsemen_gpp',
    'CrossFit':          'crossfit',
    'CrossFit Endurance': 'crossfit',
    'Wildman':           'wildman_kettlebell',
    'Pavel':             'wildman_kettlebell',
    'Uphill Athlete':    'uphill_athlete',
    'Ido Portal':        'ido_portal',
    'ATG':               'atg',
    'plan.md section 10': 'atg',   # rehab exercises — ATG owns the rehab protocol
}

# ---------------------------------------------------------------------------
# Starting loads and increments from src/progression.py (hardcoded fallbacks).
# These will be embedded in the starting_strength package's exercise entries
# since that's the canonical barbell philosophy.
# Other packages may override prescription for their specific context.
# ---------------------------------------------------------------------------
_STARTING_LOADS = {
    'back_squat':         {'novice': 40,  'intermediate': 70,  'advanced': 100, 'elite': 130},
    'front_squat':        {'novice': 30,  'intermediate': 55,  'advanced': 80,  'elite': 110},
    'deadlift':           {'novice': 50,  'intermediate': 90,  'advanced': 130, 'elite': 170},
    'strict_press':       {'novice': 25,  'intermediate': 40,  'advanced': 60,  'elite': 80},
    'bench_press':        {'novice': 35,  'intermediate': 60,  'advanced': 90,  'elite': 120},
    'power_clean':        {'novice': 30,  'intermediate': 50,  'advanced': 75,  'elite': 100},
    'hang_power_clean':   {'novice': 25,  'intermediate': 45,  'advanced': 70,  'elite': 95},
    'romanian_deadlift':  {'novice': 40,  'intermediate': 75,  'advanced': 110, 'elite': 140},
    'trap_bar_deadlift':  {'novice': 50,  'intermediate': 90,  'advanced': 130, 'elite': 170},
    'sumo_deadlift':      {'novice': 50,  'intermediate': 90,  'advanced': 130, 'elite': 170},
    'floor_press':        {'novice': 35,  'intermediate': 50,  'advanced': 75,  'elite': 100},
}

_LINEAR_INCREMENTS = {
    'back_squat':         2.5,
    'front_squat':        2.5,
    'deadlift':           5.0,
    'romanian_deadlift':  2.5,
    'trap_bar_deadlift':  5.0,
    'strict_press':       1.25,
    'bench_press':        2.5,
    'power_clean':        2.5,
    'hang_power_clean':   2.5,
    'floor_press':        2.5,
}

# Per-package prescription overrides.
# Any package that trains an exercise differently from the defaults above can
# add its values here. The migration script writes these fields into that
# package's exercises.yaml entry.
# Format: {package_id: {exercise_id: {starting_load_kg: {...}, weekly_increment_kg: N}}}
_PKG_PRESCRIPTION_OVERRIDES: dict[str, dict[str, dict]] = {
    # Wildman Kettlebell — sport-specific KB loads, RKC standards
    'wildman_kettlebell': {
        'kb_swing_two_hand':  {'starting_load_kg': {'novice': 16, 'intermediate': 24, 'advanced': 32, 'elite': 40}, 'weekly_increment_kg': 0},
        'kb_swing_single_arm':{'starting_load_kg': {'novice': 12, 'intermediate': 16, 'advanced': 24, 'elite': 32}, 'weekly_increment_kg': 0},
        'kb_snatch':          {'starting_load_kg': {'novice': 16, 'intermediate': 24, 'advanced': 32, 'elite': 40}, 'weekly_increment_kg': 0},
        'kb_clean_single':    {'starting_load_kg': {'novice': 12, 'intermediate': 16, 'advanced': 24, 'elite': 32}, 'weekly_increment_kg': 0},
        'kb_clean_double':    {'starting_load_kg': {'novice': 16, 'intermediate': 24, 'advanced': 32, 'elite': 40}, 'weekly_increment_kg': 0},
        'kb_press_single':    {'starting_load_kg': {'novice': 8,  'intermediate': 12, 'advanced': 16, 'elite': 24}, 'weekly_increment_kg': 0},
        'kb_press_double':    {'starting_load_kg': {'novice': 12, 'intermediate': 16, 'advanced': 24, 'elite': 32}, 'weekly_increment_kg': 0},
        'kb_push_press_single':{'starting_load_kg':{'novice': 12, 'intermediate': 16, 'advanced': 24, 'elite': 32}, 'weekly_increment_kg': 0},
        'kb_jerk_single':     {'starting_load_kg': {'novice': 12, 'intermediate': 16, 'advanced': 24, 'elite': 32}, 'weekly_increment_kg': 0},
        'kb_jerk_double':     {'starting_load_kg': {'novice': 16, 'intermediate': 24, 'advanced': 32, 'elite': 40}, 'weekly_increment_kg': 0},
        'kb_squat_double':    {'starting_load_kg': {'novice': 16, 'intermediate': 24, 'advanced': 32, 'elite': 40}, 'weekly_increment_kg': 0},
        'kb_tgu':             {'starting_load_kg': {'novice': 8,  'intermediate': 12, 'advanced': 16, 'elite': 24}, 'weekly_increment_kg': 0},
        'kb_deadlift':        {'starting_load_kg': {'novice': 16, 'intermediate': 24, 'advanced': 32, 'elite': 48}, 'weekly_increment_kg': 0},
        'kb_windmill':        {'starting_load_kg': {'novice': 8,  'intermediate': 12, 'advanced': 16, 'elite': 24}, 'weekly_increment_kg': 0},
    },
    # Horsemen GPP — heavier KB baseline (tactical/operator context); standard barbell loads
    'horsemen_gpp': {
        'kb_swing_two_hand':  {'starting_load_kg': {'novice': 24, 'intermediate': 32, 'advanced': 40, 'elite': 48}, 'weekly_increment_kg': 0},
        'kb_swing_single_arm':{'starting_load_kg': {'novice': 16, 'intermediate': 24, 'advanced': 32, 'elite': 40}, 'weekly_increment_kg': 0},
        'kb_snatch':          {'starting_load_kg': {'novice': 24, 'intermediate': 32, 'advanced': 40, 'elite': 48}, 'weekly_increment_kg': 0},
        'kb_tgu':             {'starting_load_kg': {'novice': 12, 'intermediate': 16, 'advanced': 24, 'elite': 32}, 'weekly_increment_kg': 0},
        'kb_clean_single':    {'starting_load_kg': {'novice': 16, 'intermediate': 24, 'advanced': 32, 'elite': 40}, 'weekly_increment_kg': 0},
        'kb_press_single':    {'starting_load_kg': {'novice': 12, 'intermediate': 16, 'advanced': 24, 'elite': 32}, 'weekly_increment_kg': 0},
        'kb_deadlift':        {'starting_load_kg': {'novice': 24, 'intermediate': 32, 'advanced': 40, 'elite': 56}, 'weekly_increment_kg': 0},
        'back_squat':         {'starting_load_kg': {'novice': 40, 'intermediate': 70, 'advanced': 100, 'elite': 130}},
        'deadlift':           {'starting_load_kg': {'novice': 50, 'intermediate': 90, 'advanced': 130, 'elite': 170}},
    },
    # Gym Jones uses heavier starting loads — more experienced athlete baseline
    'gym_jones': {
        'back_squat':       {'starting_load_kg': {'novice': 60, 'intermediate': 90, 'advanced': 120, 'elite': 150}},
        'deadlift':         {'starting_load_kg': {'novice': 70, 'intermediate': 110, 'advanced': 150, 'elite': 190}},
        'bench_press':      {'starting_load_kg': {'novice': 50, 'intermediate': 75, 'advanced': 105, 'elite': 135}},
        'strict_press':     {'starting_load_kg': {'novice': 30, 'intermediate': 50, 'advanced': 70, 'elite': 90}},
        'power_clean':      {'starting_load_kg': {'novice': 40, 'intermediate': 60, 'advanced': 85, 'elite': 110}},
    },
}


def _resolve_packages(sources: list[str]) -> list[str]:
    """Return deduplicated list of package IDs for the given source strings."""
    pkgs = []
    seen = set()
    for s in sources:
        pkg = _SOURCE_TO_PKG.get(s)
        if pkg and pkg not in seen:
            pkgs.append(pkg)
            seen.add(pkg)
    return pkgs


def _enrich_exercise(ex: dict, pkg_id: str) -> dict:
    """Return a copy of ex enriched with prescription fields for this package."""
    ex = dict(ex)
    ex_id = ex.get('id', '')

    # Check package-specific prescription override first
    pkg_overrides = _PKG_PRESCRIPTION_OVERRIDES.get(pkg_id, {})
    ex_override = pkg_overrides.get(ex_id, {})

    if ex_override.get('starting_load_kg'):
        ex.setdefault('starting_load_kg', ex_override['starting_load_kg'])
    if ex_override.get('weekly_increment_kg'):
        ex.setdefault('weekly_increment_kg', ex_override['weekly_increment_kg'])

    # Fall through to global defaults if no package-specific values set yet
    if 'starting_load_kg' not in ex and ex_id in _STARTING_LOADS:
        ex['starting_load_kg'] = _STARTING_LOADS[ex_id]
    if 'weekly_increment_kg' not in ex and ex_id in _LINEAR_INCREMENTS:
        ex['weekly_increment_kg'] = _LINEAR_INCREMENTS[ex_id]

    return ex


def main() -> None:
    data_dir = os.path.join(os.path.dirname(__file__), '..', 'data')
    exercises_dir = os.path.join(data_dir, 'exercises')
    packages_dir = os.path.join(data_dir, 'packages')

    # Collect all exercises, grouped by target package
    pkg_exercises: dict[str, list[dict]] = defaultdict(list)
    unknown_sources: set[str] = set()
    total = 0
    unassigned = []

    for fpath in sorted(glob.glob(os.path.join(exercises_dir, '*.yaml'))):
        with open(fpath) as f:
            data = yaml.safe_load(f)
        for ex in data.get('exercises', []):
            total += 1
            sources = ex.get('sources', [])
            pkgs = _resolve_packages(sources)

            # Track unknown source strings for reporting
            for s in sources:
                if s not in _SOURCE_TO_PKG:
                    unknown_sources.add(s)

            if not pkgs:
                unassigned.append(ex['id'])
                continue

            for pkg_id in pkgs:
                enriched = _enrich_exercise(ex, pkg_id)
                pkg_exercises[pkg_id].append(enriched)

    # Write one exercises.yaml per package
    written = 0
    for pkg_id, exercises in sorted(pkg_exercises.items()):
        pkg_dir = os.path.join(packages_dir, pkg_id)
        os.makedirs(pkg_dir, exist_ok=True)
        out_path = os.path.join(pkg_dir, 'exercises.yaml')
        with open(out_path, 'w') as f:
            yaml.dump(
                {'exercises': exercises},
                f,
                default_flow_style=False,
                allow_unicode=True,
                sort_keys=False,
            )
        print(f'  {pkg_id}: {len(exercises)} exercises -> {out_path}')
        written += len(exercises)

    print(f'\nDone. {total} input exercises -> {written} package entries across {len(pkg_exercises)} packages.')
    if unassigned:
        print(f'WARNING: {len(unassigned)} exercises had no resolvable package: {unassigned}')
    if unknown_sources:
        print(f'WARNING: Unrecognized source strings: {sorted(unknown_sources)}')


if __name__ == '__main__':
    main()
