"""Load and cache training data from YAML files."""
import logging
import os
import glob
import yaml

_log = logging.getLogger(__name__)

_DATA_DIR     = os.path.join(os.path.dirname(__file__), '..', 'data')
_COMMONS_DIR  = os.path.join(_DATA_DIR, 'commons')
_PACKAGES_DIR = os.path.join(_DATA_DIR, 'packages')


def _load_yaml(path: str) -> dict:
    with open(path, encoding='utf-8') as f:
        return yaml.safe_load(f)


def _data_path(*parts) -> str:
    return os.path.join(_DATA_DIR, *parts)


def load_framework(framework_id: str) -> dict:
    for path in glob.glob(os.path.join(_PACKAGES_DIR, '*', 'frameworks', f'{framework_id}.yaml')):
        return _load_yaml(path)
    raise FileNotFoundError(f"Framework '{framework_id}' not found")


def load_all_frameworks() -> dict:
    """Return dict of framework_id -> framework data for all installed packages."""
    result = {}
    for path in glob.glob(os.path.join(_PACKAGES_DIR, '*', 'frameworks', '*.yaml')):
        fw = _load_yaml(path)
        result[fw['id']] = fw
    return result


# Modality priority tiers for intelligent dropping when availability is limited
# Lower tier number = higher priority (kept when days are scarce)
MODALITY_PRIORITY_TIERS = {
    # Tier 1: Foundational - never drop (aerobic capacity, progressive overload)
    'aerobic_base': 1,
    'max_strength': 1,

    # Tier 2: Progressive overload - drop only if <3 days
    'power': 2,
    'relative_strength': 2,
    'strength_endurance': 2,
    'anaerobic_intervals': 2,

    # Tier 3: Supportive - drop if <4 days
    'durability': 3,
    'mixed_modal_conditioning': 3,

    # Tier 4: Accessory - drop if <5 days
    'mobility': 4,
    'movement_skill': 4,
    'rehab': 4,
    'skill_work': 4,
}

# Typical session durations per modality (for matching to user's long/short slots)
MODALITY_TYPICAL_DURATIONS = {
    'aerobic_base': 75,          # Long endurance sessions
    'anaerobic_intervals': 45,   # Time-efficient conditioning
    'max_strength': 60,          # Moderate gym sessions
    'power': 45,                 # Shorter explosive work
    'relative_strength': 50,     # Bodyweight strength
    'strength_endurance': 50,    # Moderate endurance work
    'durability': 60,            # Loaded carries, rucks
    'mixed_modal_conditioning': 50,  # Mixed work
    'mobility': 30,              # Accessory work
    'movement_skill': 30,        # Skill practice
    'rehab': 20,                 # Prehab/recovery
    'skill_work': 30,            # Technical practice
}


def load_all_modalities() -> dict:
    """Return dict of modality_id -> modality data with priority_tier and typical_duration_minutes."""
    result = {}
    for path in glob.glob(os.path.join(_COMMONS_DIR, 'modalities', '*.yaml')):
        mod = _load_yaml(path)
        mod_id = mod['id']

        # Add priority tier (default to 3 if not specified)
        mod['priority_tier'] = MODALITY_PRIORITY_TIERS.get(mod_id, 3)

        # Add typical duration (default to 60min if not specified)
        mod['typical_duration_minutes'] = MODALITY_TYPICAL_DURATIONS.get(mod_id, 60)

        result[mod_id] = mod
    return result


def load_all_archetypes() -> list:
    """Return list of all archetype dicts, each annotated with _package."""
    result = []
    seen_ids: set = set()
    for path in glob.glob(
        os.path.join(_PACKAGES_DIR, '*', 'archetypes', '**', '*.yaml'),
        recursive=True,
    ):
        arch = _load_yaml(path)
        arch_id = arch.get('id')
        if arch_id not in seen_ids:
            seen_ids.add(arch_id)
            parts = path.replace('\\', '/').split('/')
            try:
                pkg_idx = parts.index('packages') + 1
                arch['_package'] = parts[pkg_idx]
            except ValueError:
                arch['_package'] = None
            result.append(arch)
    return result


def load_all_exercises() -> tuple[dict, dict]:
    """Return (global_index, exercises_by_package).

    global_index: exercise_id -> exercise data (first-seen wins for structural fields).
    exercises_by_package: package_id -> {exercise_id -> exercise data} with
        package-specific prescription fields (starting_load_kg, etc.).
    """
    global_index: dict = {}
    by_package: dict = {}
    for path in sorted(glob.glob(os.path.join(_PACKAGES_DIR, '*', 'exercises.yaml'))):
        pkg_id = os.path.basename(os.path.dirname(path))
        pkg_exercises: dict = {}
        data = _load_yaml(path)
        for ex in data.get('exercises', []):
            ex = dict(ex)
            ex['_package'] = pkg_id
            pkg_exercises[ex['id']] = ex
            if ex['id'] not in global_index:
                global_index[ex['id']] = ex
        by_package[pkg_id] = pkg_exercises
    return global_index, by_package


def load_injury_flags() -> dict:
    """Return dict of flag_id -> flag data."""
    raw = _load_yaml(os.path.join(_COMMONS_DIR, 'constraints', 'injury_flags.yaml'))
    return {flag['id']: flag for flag in raw.get('injury_flags', [])}


def load_equipment() -> list[dict]:
    """Return list of all equipment items (from constraints schema)."""
    # Equipment is centrally defined in constraints.schema.json
    # This list matches the schema enum
    equipment_ids = [
        'barbell', 'rack', 'plates', 'kettlebell', 'dumbbell',
        'pull_up_bar', 'rings', 'parallettes', 'rower', 'bike',
        'ski_erg', 'ruck_pack', 'sandbag', 'sled', 'tire',
        'medicine_ball', 'resistance_band', 'rope', 'box',
        'ghd', 'jump_rope', 'open_space'
    ]
    return [{'id': eq_id} for eq_id in equipment_ids]


def load_equipment_profiles() -> list:
    """Return list of equipment profile dicts."""
    raw = _load_yaml(os.path.join(_COMMONS_DIR, 'constraints', 'equipment_profiles.yaml'))
    return raw.get('profiles', raw.get('equipment_profiles', []))


def load_level_seeds() -> dict:
    """Merge per-package level seed sets into a single dict of level -> set of exercise IDs."""
    base: dict = {'novice': set(), 'intermediate': set(), 'advanced': set(), 'elite': set()}
    for path in glob.glob(os.path.join(_PACKAGES_DIR, '*', 'level_seeds.yaml')):
        data = _load_yaml(path)
        for level, ids in data.get('seeds', {}).items():
            base.setdefault(level, set()).update(ids)
    return base


def load_philosophies() -> list:
    """Return list of philosophy dicts, each with a system_connections key."""
    fw_map: dict = {}
    for path in glob.glob(os.path.join(_PACKAGES_DIR, '*', 'frameworks', '*.yaml')):
        fw = _load_yaml(path)
        sp = fw.get('source_philosophy')
        if sp:
            fw_map.setdefault(sp, []).append(fw['id'])

    result = []
    for path in sorted(glob.glob(os.path.join(_PACKAGES_DIR, '*', 'philosophy.yaml'))):
        p = _load_yaml(path)
        p['system_connections'] = {
            'frameworks': fw_map.get(p['id'], []),
        }
        result.append(p)
    return result


def load_philosophy(philosophy_id: str) -> dict:
    """Return a single philosophy dict by ID (with system_connections)."""
    for p in load_philosophies():
        if p['id'] == philosophy_id:
            return p
    raise FileNotFoundError(f'Philosophy not found: {philosophy_id}')


def load_all_data() -> dict:
    """Load all library data in one call."""
    exercises, exercises_by_package = load_all_exercises()
    return {
        'modalities':           load_all_modalities(),
        'archetypes':           load_all_archetypes(),
        'exercises':            exercises,
        'exercises_by_package': exercises_by_package,
        'injury_flags':         load_injury_flags(),
    }
