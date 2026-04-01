"""Load and cache training data from YAML files."""
import logging
import os
import glob
import yaml

_log = logging.getLogger(__name__)

_DATA_DIR = os.path.join(os.path.dirname(__file__), '..', 'data')


def _load_yaml(path: str) -> dict:
    with open(path, encoding='utf-8') as f:
        return yaml.safe_load(f)


def _data_path(*parts) -> str:
    return os.path.join(_DATA_DIR, *parts)


def load_goal(goal_id: str) -> dict:
    path = _data_path('goals', f'{goal_id}.yaml')
    if not os.path.exists(path):
        available = [os.path.splitext(os.path.basename(p))[0]
                     for p in glob.glob(_data_path('goals', '*.yaml'))]
        raise FileNotFoundError(
            f"Goal '{goal_id}' not found. Available: {', '.join(sorted(available))}"
        )
    return _load_yaml(path)


def load_framework(framework_id: str) -> dict:
    return _load_yaml(_data_path('frameworks', f'{framework_id}.yaml'))


def load_all_modalities() -> dict:
    """Return dict of modality_id -> modality data."""
    result = {}
    for path in glob.glob(_data_path('modalities', '*.yaml')):
        mod = _load_yaml(path)
        result[mod['id']] = mod
    return result


def load_all_archetypes() -> list:
    """Return list of all archetype dicts."""
    result = []
    for path in glob.glob(_data_path('archetypes', '**', '*.yaml'), recursive=True):
        arch = _load_yaml(path)
        result.append(arch)
    return result


def load_all_exercises() -> dict:
    """Return dict of exercise_id -> exercise data."""
    result = {}
    for path in glob.glob(_data_path('exercises', '*.yaml')):
        data = _load_yaml(path)
        for ex in data.get('exercises', []):
            if ex['id'] in result:
                _log.warning('Duplicate exercise id %r in %s — previous definition overwritten', ex['id'], path)
            result[ex['id']] = ex
    return result


def load_injury_flags() -> dict:
    """Return dict of flag_id -> flag data."""
    raw = _load_yaml(_data_path('constraints', 'injury_flags.yaml'))
    return {flag['id']: flag for flag in raw.get('injury_flags', [])}


def load_philosophies() -> list:
    """Return list of philosophy dicts, each with a system_connections key."""
    phil_dir      = _data_path('philosophies')
    framework_dir = _data_path('frameworks')
    goal_dir      = _data_path('goals')

    fw_map: dict = {}
    for path in glob.glob(os.path.join(framework_dir, '*.yaml')):
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
    for path in sorted(glob.glob(os.path.join(phil_dir, '*.yaml'))):
        p = _load_yaml(path)
        p['system_connections'] = {
            'frameworks': fw_map.get(p['id'], []),
            'goals':      goal_map.get(p['id'], []),
        }
        result.append(p)
    return result


def load_all_data() -> dict:
    """Load all library data in one call."""
    return {
        'modalities': load_all_modalities(),
        'archetypes': load_all_archetypes(),
        'exercises': load_all_exercises(),
        'injury_flags': load_injury_flags(),
    }
