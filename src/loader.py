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


def load_goal(goal_id: str) -> dict:
    for path in glob.glob(_data_path('goals', '**', '*.yaml'), recursive=True):
        if os.path.splitext(os.path.basename(path))[0] == goal_id:
            return _load_yaml(path)
    available = [os.path.splitext(os.path.basename(p))[0]
                 for p in glob.glob(_data_path('goals', '**', '*.yaml'), recursive=True)]
    raise FileNotFoundError(
        f"Goal '{goal_id}' not found. Available: {', '.join(sorted(available))}"
    )


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


def load_all_modalities() -> dict:
    """Return dict of modality_id -> modality data."""
    result = {}
    for path in glob.glob(os.path.join(_COMMONS_DIR, 'modalities', '*.yaml')):
        mod = _load_yaml(path)
        result[mod['id']] = mod
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
    goal_dir = _data_path('goals')

    fw_map: dict = {}
    for path in glob.glob(os.path.join(_PACKAGES_DIR, '*', 'frameworks', '*.yaml')):
        fw = _load_yaml(path)
        sp = fw.get('source_philosophy')
        if sp:
            fw_map.setdefault(sp, []).append(fw['id'])

    goal_map: dict = {}
    for path in glob.glob(os.path.join(goal_dir, '*.yaml')):
        g = _load_yaml(path)
        for src in g.get('primary_sources', []):
            goal_map.setdefault(src, []).append(g['id'])

    result = []
    for path in sorted(glob.glob(os.path.join(_PACKAGES_DIR, '*', 'philosophy.yaml'))):
        p = _load_yaml(path)
        p['system_connections'] = {
            'frameworks': fw_map.get(p['id'], []),
            'goals':      goal_map.get(p['id'], []),
        }
        result.append(p)
    return result


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
