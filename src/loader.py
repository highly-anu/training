"""Load and cache training data from YAML files."""
import logging
import os
import glob
import yaml

_log = logging.getLogger(__name__)

_DATA_DIR     = os.path.join(os.path.dirname(__file__), '..', 'data')
_COMMONS_DIR  = os.path.join(_DATA_DIR, 'commons')
# Every package is a folder here, found by globbing, never by name. A test may
# point it elsewhere (TRAINING_PACKAGES_DIR) to add a package without touching
# the repository: test_package_dropin.py proves one needs no code change.
_PACKAGES_DIR = os.environ.get('TRAINING_PACKAGES_DIR') or os.path.join(_DATA_DIR, 'packages')


# libyaml's C parser when PyYAML was built with it (the Linux wheels are):
# ten times faster than the pure-Python one on the package data, with the same
# result for every file. The reference routes re-read the packages, and on the
# shared-CPU machine the pure-Python parser made the Explore tab time out.
_SAFE_LOADER = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)


def safe_load(stream):
    """yaml.safe_load, on the C parser when there is one."""
    return yaml.load(stream, Loader=_SAFE_LOADER)


def _load_yaml(path: str) -> dict:
    with open(path, encoding='utf-8') as f:
        return safe_load(f)


def _data_path(*parts) -> str:
    return os.path.join(_DATA_DIR, *parts)


def load_framework(framework_id: str) -> dict:
    for path in sorted(glob.glob(os.path.join(_PACKAGES_DIR, '*', 'frameworks', f'{framework_id}.yaml'))):
        return _load_yaml(path)
    raise FileNotFoundError(f"Framework '{framework_id}' not found")


def load_all_frameworks() -> dict:
    """Return dict of framework_id -> framework data for all installed packages."""
    result = {}
    for path in sorted(glob.glob(os.path.join(_PACKAGES_DIR, '*', 'frameworks', '*.yaml'))):
        fw = _load_yaml(path)
        result[fw['id']] = fw
    return result


def load_all_modalities() -> dict:
    """Return dict of modality_id -> modality data. A modality's file says its
    `priority_tier` (kept when days are scarce, 1 first; 3 without one) and its
    `typical_duration_minutes` (60 without one) — a table in this module used to
    set them over the file."""
    result = {}
    for path in sorted(glob.glob(os.path.join(_COMMONS_DIR, 'modalities', '*.yaml'))):
        mod = _load_yaml(path)
        mod.setdefault('priority_tier', 3)
        mod.setdefault('typical_duration_minutes', 60)
        result[mod['id']] = mod
    return result


def load_all_archetypes() -> list:
    """Return list of all archetype dicts, each annotated with _package."""
    result = []
    seen_ids: set = set()
    # Sorted: the selector breaks ties by load order ("first authored"), and an
    # unsorted listing is the filesystem's order — production (Linux) and a
    # Mac generated different programs from the same request.
    for path in sorted(glob.glob(
        os.path.join(_PACKAGES_DIR, '*', 'archetypes', '**', '*.yaml'),
        recursive=True,
    )):
        arch = _load_yaml(path)
        arch_id = arch.get('id')
        if arch_id not in seen_ids:
            seen_ids.add(arch_id)
            arch['_package'] = os.path.relpath(path, _PACKAGES_DIR).replace('\\', '/').split('/')[0]
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
        for raw_ex in data.get('exercises', []):
            ex_id = raw_ex['id']

            # Package-scoped copy — carries this package's prescription fields.
            pkg_ex = dict(raw_ex)
            pkg_ex['_package'] = pkg_id
            pkg_ex['_packages'] = [pkg_id]
            pkg_exercises[ex_id] = pkg_ex

            # Global copy — structural fields are first-seen-wins, but _packages
            # accumulates EVERY package that declares this id. 76 exercise ids are
            # declared by more than one package; using the first declarer as the
            # owner mislabels 33/79 horsemen_gpp and 8/13 starting_strength ids.
            # Provenance decisions must read _packages, never _package.
            existing = global_index.get(ex_id)
            if existing is None or (existing.get('named_only') and not raw_ex.get('named_only')):
                # A named workout's movement (`named_only`, Horsemen's) never
                # stands for an id another package declares for open slots:
                # that package's copy is the global one, whatever sorts first.
                global_ex = dict(raw_ex)
                global_ex['_package'] = pkg_id      # display back-compat only
                global_ex['_packages'] = (existing['_packages'] if existing else []) + [pkg_id]
                global_index[ex_id] = global_ex
            elif pkg_id not in existing['_packages']:
                existing['_packages'].append(pkg_id)
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
    """Return {package_id: {level: set(concept or exercise ids)}}.

    A package declares what an athlete at each level is assumed to already know,
    which unlocks exercises whose `requires` list those concepts. Package-scoped
    rather than merged globally: Starting Strength teaches a novice to brace and
    hinge in the first session, but that says nothing about whether a novice in
    another philosophy has those prerequisites.
    """
    by_package: dict = {}
    for path in sorted(glob.glob(os.path.join(_PACKAGES_DIR, '*', 'level_seeds.yaml'))):
        pkg_id = os.path.basename(os.path.dirname(path))
        data = _load_yaml(path) or {}
        by_package[pkg_id] = {
            level: set(ids or ())
            for level, ids in (data.get('seeds') or {}).items()
        }
    return by_package


def load_analytics_specs() -> dict:
    """Return {package_id: analytics spec} for every package that declares one.

    A package's analytics.yaml says what progress means for its methodology
    (docs/schemas/analytics.schema.json). Package-scoped like level_seeds: a
    package that ships none gets a spec synthesised from its frameworks by
    src/analytics/spec.py, so declaring one is an override, not a requirement.
    """
    specs: dict = {}
    for path in sorted(glob.glob(os.path.join(_PACKAGES_DIR, '*', 'analytics.yaml'))):
        pkg_id = os.path.basename(os.path.dirname(path))
        data = _load_yaml(path) or {}
        data['_package'] = pkg_id
        specs[pkg_id] = data
    return specs


def load_watch_specs() -> dict:
    """Return {package_id: watch spec} for every package that declares one.

    A package's watch.yaml says how its sessions look on the watch
    (docs/schemas/watch.schema.json); src/watch_spec.py resolves it against
    data/commons/watch_vocabulary.json. Optional, like analytics.yaml: a
    package without one gets the vocabulary's slot-type defaults.
    """
    specs: dict = {}
    for path in sorted(glob.glob(os.path.join(_PACKAGES_DIR, '*', 'watch.yaml'))):
        pkg_id = os.path.basename(os.path.dirname(path))
        data = _load_yaml(path) or {}
        data['_package'] = pkg_id
        specs[pkg_id] = data
    return specs


_phase_kinds_cache: dict | None = None


def load_phase_kinds() -> dict:
    """Return kind_id -> semantics from data/commons/phase_kinds.yaml (cached)."""
    global _phase_kinds_cache
    if _phase_kinds_cache is None:
        _phase_kinds_cache = _load_yaml(os.path.join(_COMMONS_DIR, 'phase_kinds.yaml')) or {}
    return _phase_kinds_cache


def load_philosophies() -> list:
    """Return list of philosophy dicts, each with a system_connections key."""
    fw_map: dict = {}
    for path in sorted(glob.glob(os.path.join(_PACKAGES_DIR, '*', 'frameworks', '*.yaml'))):
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


_media_cache: dict | None = None


def load_exercise_media() -> dict:
    """Return dict of exercise_id -> media descriptor, merged from all packages/*/exercise_media.yaml.

    Never called by the training engine — only by the API layer.
    """
    global _media_cache
    if _media_cache is None:
        merged: dict = {}
        for path in sorted(glob.glob(os.path.join(_PACKAGES_DIR, '*/exercise_media.yaml'))):
            data = _load_yaml(path)
            if data:
                merged.update(data)
        _media_cache = merged
    return _media_cache


def load_all_data() -> dict:
    """Load all library data in one call."""
    exercises, exercises_by_package = load_all_exercises()
    return {
        'modalities':           load_all_modalities(),
        'archetypes':           load_all_archetypes(),
        'exercises':            exercises,
        'exercises_by_package': exercises_by_package,
        'injury_flags':         load_injury_flags(),
        'level_seeds':          load_level_seeds(),
    }
