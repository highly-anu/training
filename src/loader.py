"""Load and cache training data from YAML files."""
import contextlib
import contextvars
import logging
import os
import glob
import threading
from collections import OrderedDict

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


# ── Which packages a caller sees ──────────────────────────────────────────────
#
# Two roots. The shipped one (_PACKAGES_DIR) is everyone's, and fail-fast: a
# file there that does not load raises, so the image build fails. The overlay
# is one athlete's own packages (written at runtime: docs/roadmap.md item 20),
# a directory the caller names for the length of its work — a request, a job —
# through a context variable, so no loader call takes a parameter and a thread
# that serves another athlete next sees nothing of the last one.
#
# The overlay only ever adds:
#   - a folder named as a shipped package is ignored;
#   - a framework, archetype, philosophy or media id the shipped packages
#     declare keeps the shipped copy (an exercise id two packages declare is
#     shared by design, the shipped copy the structural one);
#   - a folder that does not load is set aside whole (`quarantined()`), so one
#     broken package breaks nobody else's — nor its owner's shipped programs.
# An overlay directory is immutable: a changed set of packages is a new
# directory (`forget_overlay` drops what was learned about an old one).

_OVERLAY: contextvars.ContextVar = contextvars.ContextVar('training_packages_overlay', default=None)
_VIEW_LOCK = threading.RLock()
_OVERLAY_PACKAGES: dict[str, tuple[list, list]] = {}   # overlay dir → (loadable, quarantined)


class _Later:
    """An overlay named by a function, asked once, the first time a loader
    needs it: most requests read no package, and naming an athlete's overlay
    may cost a query (src/package_store.py)."""
    __slots__ = ('resolve', 'path', 'asked')

    def __init__(self, resolve):
        self.resolve, self.path, self.asked = resolve, None, False

    def get(self) -> str | None:
        if not self.asked:
            self.asked = True
            try:
                path = self.resolve()
            except Exception as e:   # naming it failed: the shipped packages alone, never an error
                _log.warning('overlay not resolved: %s', e)
                path = None
            self.path = os.path.abspath(path) if path else None
        return self.path


def overlay_dir() -> str | None:
    """The overlay the caller sees, or None: the shipped packages alone."""
    value = _OVERLAY.get()
    return value.get() if isinstance(value, _Later) else value


def set_overlay(path):
    """Name the caller's overlay — a directory, or a function that returns one
    (or None) when first asked; returns the token `reset_overlay` takes.
    A server thread is reused, so every set is reset (see `overlay`)."""
    if callable(path):
        return _OVERLAY.set(_Later(path))
    return _OVERLAY.set(os.path.abspath(path) if path else None)


def reset_overlay(token) -> None:
    _OVERLAY.reset(token)


@contextlib.contextmanager
def overlay(path: str | None):
    """Run a block seeing `path`'s packages beside the shipped ones."""
    token = set_overlay(path)
    try:
        yield
    finally:
        reset_overlay(token)


def _shipped_dirs() -> list[tuple[str, str]]:
    return [(os.path.basename(d), d) for d in sorted(glob.glob(os.path.join(_PACKAGES_DIR, '*')))
            if os.path.isdir(d)]


def _probe(folder: str, pkg: str) -> str | None:
    """Why an overlay package cannot be loaded, or None. Exactly what the
    loaders below index without a guard: every file parses, the philosophy is
    the folder's, each framework, archetype and exercise has an id. (Whether
    it generates is the install gate's question: src/package_gate.py.)"""
    try:
        phil = _load_yaml(os.path.join(folder, 'philosophy.yaml'))
        if not isinstance(phil, dict) or phil.get('id') != pkg:
            return "philosophy.yaml's id is not the folder's name"
        for path in sorted(glob.glob(os.path.join(folder, '**', '*.yaml'), recursive=True)):
            rel = os.path.relpath(path, folder).replace(os.sep, '/')
            doc = _load_yaml(path)
            if rel.startswith(('frameworks/', 'archetypes/')):
                if not isinstance(doc, dict) or not doc.get('id'):
                    return f'{rel} has no id'
            elif rel == 'exercises.yaml':
                items = doc.get('exercises') if isinstance(doc, dict) else None
                if not isinstance(items, list) or not all(isinstance(e, dict) and e.get('id') for e in items):
                    return 'exercises.yaml: every exercise needs an id'
            elif rel in ('analytics.yaml', 'watch.yaml', 'level_seeds.yaml', 'exercise_media.yaml',
                         'standards.yaml', 'training_contract.yaml') and doc is not None and not isinstance(doc, dict):
                return f'{rel} is not a mapping'
    except (OSError, yaml.YAMLError) as e:
        return f'{type(e).__name__}: {e}'
    return None


def _overlay_packages(path: str) -> tuple[list, list]:
    with _VIEW_LOCK:
        known = _OVERLAY_PACKAGES.get(path)
        if known is not None:
            return known
        shipped = {name for name, _ in _shipped_dirs()}
        loadable, set_aside = [], []
        for folder in sorted(glob.glob(os.path.join(path, '*'))):
            pkg = os.path.basename(folder)
            if not os.path.isdir(folder) or not os.path.exists(os.path.join(folder, 'philosophy.yaml')):
                continue
            problem = 'a shipped package has this name' if pkg in shipped else _probe(folder, pkg)
            if problem:
                _log.warning('package %s in %s set aside: %s', pkg, path, problem)
                set_aside.append({'package': pkg, 'dir': folder, 'problem': problem})
            else:
                loadable.append((pkg, folder))
        _OVERLAY_PACKAGES[path] = (loadable, set_aside)
        return _OVERLAY_PACKAGES[path]


def package_dirs() -> list[tuple[str, str]]:
    """[(package id, folder)] the caller sees: the shipped packages, sorted,
    then its overlay's loadable ones."""
    path = overlay_dir()
    return _shipped_dirs() + (list(_overlay_packages(path)[0]) if path else [])


def overlay_packages() -> list[str]:
    """The ids of the caller's own (overlay) packages that load."""
    path = overlay_dir()
    return [pkg for pkg, _ in _overlay_packages(path)[0]] if path else []


def quarantined() -> list[dict]:
    """The caller's overlay packages that were set aside: [{package, dir, problem}]."""
    path = overlay_dir()
    return list(_overlay_packages(path)[1]) if path else []


def package_dir(pkg: str) -> str:
    """The folder of a package the caller sees; for an id it does not see,
    where a shipped package of that name would be."""
    for name, folder in package_dirs():
        if name == pkg:
            return folder
    return os.path.join(_PACKAGES_DIR, pkg)


def package_files(*parts: str, recursive: bool = False) -> list[tuple[str, str]]:
    """[(package id, path)] matching `parts` inside each package the caller
    sees — package by package, sorted within one, which for the shipped root
    is the order one sorted glob over it gave."""
    out = []
    for pkg, folder in package_dirs():
        out += [(pkg, path) for path in sorted(glob.glob(os.path.join(folder, *parts), recursive=recursive))]
    return out


def _is_overlay(pkg: str) -> bool:
    path = overlay_dir()
    return bool(path) and any(pkg == name for name, _ in _overlay_packages(path)[0])


# ── Answers kept per view ─────────────────────────────────────────────────────
#
# Anything a module computes from the packages and keeps is kept per view: the
# shipped view's for the life of the process, an overlay's among the few most
# recent. `view_store(name)` is a module's dict for the caller's view;
# `scoped_cache` memoises a function on it; `invalidate_package_data()` is the
# one call that forgets everything (an authoring write, a package installed).

_MAX_OVERLAY_VIEWS = 4
_SHIPPED_STORES: dict[str, dict] = {}
_OVERLAY_STORES: 'OrderedDict[str, dict[str, dict]]' = OrderedDict()


def view_store(name: str) -> dict:
    path = overlay_dir()
    with _VIEW_LOCK:
        if path is None:
            return _SHIPPED_STORES.setdefault(name, {})
        stores = _OVERLAY_STORES.get(path)
        if stores is None:
            stores = _OVERLAY_STORES[path] = {}
            while len(_OVERLAY_STORES) > _MAX_OVERLAY_VIEWS:
                _OVERLAY_STORES.popitem(last=False)
        else:
            _OVERLAY_STORES.move_to_end(path)
        return stores.setdefault(name, {})


def scoped_cache(fn):
    """Memoise `fn` (hashable positional arguments) per view. `cache_clear()`
    forgets it for every view."""
    import functools
    name = f'{fn.__module__}.{fn.__qualname__}'

    @functools.wraps(fn)
    def wrapper(*args):
        store = view_store(name)
        if args not in store:
            store[args] = fn(*args)
        return store[args]

    def cache_clear():
        with _VIEW_LOCK:
            _SHIPPED_STORES.pop(name, None)
            for stores in _OVERLAY_STORES.values():
                stores.pop(name, None)
    wrapper.cache_clear = cache_clear
    return wrapper


def forget_overlay(path: str | None) -> None:
    """Drop what is known of one overlay directory (it was replaced or removed)."""
    if not path:
        return
    path = os.path.abspath(path)
    with _VIEW_LOCK:
        _OVERLAY_PACKAGES.pop(path, None)
        _OVERLAY_STORES.pop(path, None)


def invalidate_package_data() -> None:
    """Forget every answer computed from the packages, in every view."""
    with _VIEW_LOCK:
        _SHIPPED_STORES.clear()
        _OVERLAY_STORES.clear()
        _OVERLAY_PACKAGES.clear()


def load_framework(framework_id: str) -> dict:
    for _pkg, path in package_files('frameworks', f'{framework_id}.yaml'):
        return _load_yaml(path)
    raise FileNotFoundError(f"Framework '{framework_id}' not found")


def load_all_frameworks() -> dict:
    """Return dict of framework_id -> framework data for all installed packages."""
    result = {}
    for pkg, path in package_files('frameworks', '*.yaml'):
        fw = _load_yaml(path)
        if fw['id'] in result and _is_overlay(pkg):
            continue   # an overlay never replaces a shipped framework
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
    # A package's own (its vocabulary.yaml), tagged with it; never a commons id.
    for mod_id, mod in load_vocabulary()['modalities'].items():
        if mod_id not in result:
            mod = dict(mod)
            mod.setdefault('priority_tier', 3)
            mod.setdefault('typical_duration_minutes', 60)
            result[mod_id] = mod
    return result


@scoped_cache
def load_vocabulary() -> dict:
    """What the packages the caller sees add to the commons' vocabulary
    (`vocabulary.yaml`, docs/schemas/vocabulary.schema.json), kept per view:
    {'modalities': {id: modality, with `_package`}, 'patterns': {id: {regions,
    excluded_by, `_package`}}, 'equipment': {id: {id, label, `package`}},
    'by_package': {package: {'modalities': [ids], 'patterns': [ids],
    'equipment': [ids]}}}. The first package to declare an id keeps it
    (validate_entities refuses a second, and a commons id)."""
    out = {'modalities': {}, 'patterns': {}, 'equipment': {}, 'by_package': {}}
    for pkg, path in package_files('vocabulary.yaml'):
        doc = _load_yaml(path)
        if not isinstance(doc, dict):
            continue
        mine = out['by_package'].setdefault(pkg, {'modalities': [], 'patterns': [], 'equipment': []})
        for mod in doc.get('modalities') or []:
            if isinstance(mod, dict) and mod.get('id'):
                mine['modalities'].append(mod['id'])
                out['modalities'].setdefault(mod['id'], {**mod, '_package': pkg})
        for pat in doc.get('movement_patterns') or []:
            if isinstance(pat, dict) and pat.get('id'):
                mine['patterns'].append(pat['id'])
                out['patterns'].setdefault(pat['id'], {'regions': pat.get('regions') or {},
                                                       'excluded_by': pat.get('excluded_by') or [], '_package': pkg})
        for item in doc.get('equipment') or []:
            if isinstance(item, dict) and item.get('id'):
                mine['equipment'].append(item['id'])
                out['equipment'].setdefault(item['id'], {'id': item['id'], 'label': item.get('label') or item['id'],
                                                         'package': pkg})
    return out


def load_all_archetypes() -> list:
    """Return list of all archetype dicts, each annotated with _package."""
    result = []
    seen_ids: set = set()
    # Sorted: the selector breaks ties by load order ("first authored"), and an
    # unsorted listing is the filesystem's order — production (Linux) and a
    # Mac generated different programs from the same request.
    for pkg, path in package_files('archetypes', '**', '*.yaml', recursive=True):
        arch = _load_yaml(path)
        arch_id = arch.get('id')
        if arch_id not in seen_ids:
            seen_ids.add(arch_id)
            arch['_package'] = pkg
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
    for pkg_id, path in package_files('exercises.yaml'):
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
            if existing is None or (existing.get('named_only') and not raw_ex.get('named_only')
                                    and not _is_overlay(pkg_id)):
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
    flags = {flag['id']: flag for flag in raw.get('injury_flags', [])}
    # A package's movement pattern says which flags rule it out
    # (vocabulary.yaml `excluded_by`): it joins those flags' excluded patterns,
    # so an exercise that names only package patterns is still filtered.
    for pat_id, pat in load_vocabulary()['patterns'].items():
        for flag_id in pat['excluded_by']:
            flag = flags.get(flag_id)
            if flag is not None and pat_id not in (flag.get('excluded_movement_patterns') or []):
                flag['excluded_movement_patterns'] = list(flag.get('excluded_movement_patterns') or []) + [pat_id]
    return flags


def load_equipment() -> list[dict]:
    """Every equipment item, [{id, label}], from the one list
    (data/commons/constraints/equipment.yaml; src/equipment.py). It used to be
    a copy here, eight ids short of the constraints schema."""
    from . import equipment
    return [{'id': e['id'], 'label': e['label'], **({'package': e['package']} if e.get('package') else {})}
            for e in equipment.items()]


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
    for pkg_id, path in package_files('level_seeds.yaml'):
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
    for pkg_id, path in package_files('analytics.yaml'):
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
    for pkg_id, path in package_files('watch.yaml'):
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
    seen_fw: set = set()
    for pkg, path in package_files('frameworks', '*.yaml'):
        fw = _load_yaml(path)
        sp = fw.get('source_philosophy')
        if _is_overlay(pkg) and (fw['id'] in seen_fw or sp != pkg):
            continue   # an overlay framework is its own package's, never a shipped philosophy's
        seen_fw.add(fw['id'])
        if sp:
            fw_map.setdefault(sp, []).append(fw['id'])

    result = []
    for _pkg, path in package_files('philosophy.yaml'):
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


@scoped_cache
def load_exercise_media() -> dict:
    """Return dict of exercise_id -> media descriptor, merged from all packages/*/exercise_media.yaml
    (kept per view; among the shipped packages the last declaration of an id
    wins, and an overlay's never replaces a shipped one).

    Never called by the training engine — only by the API layer.
    """
    merged: dict = {}
    for pkg, path in package_files('exercise_media.yaml'):
        data = _load_yaml(path)
        if not data:
            continue
        if _is_overlay(pkg):
            for key, value in data.items():
                merged.setdefault(key, value)
        else:
            merged.update(data)
    return merged


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
