"""What each package brings in its own folder, and what it still needs outside it.

The Dev Lab's Model Interactions tab asks of every package the question
test_package_dropin.py answers for three copies: is it a folder that works end
to end when dropped in? The code half is held elsewhere (no code names a
package: tools/check_code_neutral.py). This reads the other half, per package:

- its engine shape per track (a training contract, week templates, or the
  modality scheduler), decided as generation decides it;
- which of the files a package may carry it has;
- the steps that still live outside the folder: the scorecard and coverage
  baselines, the golden program hashes, status.yaml and the dossier — without
  them the push gates fail for a new package;
- the commons vocabulary it references, and any id it names that the commons
  do not define;
- ids another package also declares, and which copy the loader keeps.

The known gaps — what no package can bring in its folder yet — are
tools/portability_gaps.json, served beside it; test_portability.py fails when
a gap's code anchor is gone, so closing one means updating the list. Pure over
the files; nothing here generates a program.
"""
from __future__ import annotations

import glob
import json
import os
from collections import defaultdict

from . import loader, phases

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAPS = os.path.join(ROOT, 'tools', 'portability_gaps.json')

# What a package folder may carry, in the order an author meets them.
FILES = (
    ('philosophy', 'philosophy.yaml', True),
    ('frameworks', 'frameworks', True),
    ('archetypes', 'archetypes', True),
    ('exercises', 'exercises.yaml', True),
    ('media', 'exercise_media.yaml', False),
    ('level_seeds', 'level_seeds.yaml', False),
    ('analytics', 'analytics.yaml', False),
    ('watch', 'watch.yaml', False),
    ('contract', 'training_contract.yaml', False),
    ('fidelity', 'fidelity.yaml', False),
    ('source_weeks', 'source_weeks.yaml', False),
)

# Outside the folder: what each push gate keeps per package, and the command
# that records it.
_SCORECARD = os.path.join(ROOT, 'tools', 'scorecard_baseline.json')
_COVERAGE = os.path.join(ROOT, 'tools', 'exercise_coverage_baseline.json')
_GOLDEN = os.path.join(ROOT, 'test_single_lane_golden.json')
_STATUS = os.path.join(ROOT, 'docs', 'package-fidelity', 'status.yaml')
_DOSSIERS = os.path.join(ROOT, 'docs', 'package-fidelity')
_UPDATE_BASELINE = '.venv/bin/python tools/evaluate_packages.py --update-baseline'
_RECORD_GOLDEN = 'SUPABASE_URL= .venv/bin/python test_single_lane_golden.py --record'

# Which copy wins when two packages declare one id (src/loader.py).
_KEPT = {
    'philosophy': 'both are listed; load_philosophy returns the first',
    'framework': 'load_all_frameworks keeps the last, load_framework the first',
    'archetype': 'the first (by folder name)',
    'media': 'the last (by folder name)',
}


def _json(path: str):
    if not os.path.exists(path):
        return None
    with open(path, encoding='utf-8') as fh:
        return json.load(fh)


def _yaml(path: str):
    if not os.path.exists(path):
        return None
    try:
        return loader._load_yaml(path)
    except Exception:  # noqa: BLE001 — a broken file is validate_entities' finding
        return None


def packages() -> list[str]:
    """Every package folder the loader would read, by its folder name."""
    return sorted(os.path.basename(os.path.dirname(p))
                  for p in glob.glob(os.path.join(loader._PACKAGES_DIR, '*', 'philosophy.yaml')))


def _documents(pkg: str, sub: str) -> list[dict]:
    pattern = os.path.join(loader._PACKAGES_DIR, pkg, sub, '**', '*.yaml')
    return [d for d in (_yaml(p) for p in sorted(glob.glob(pattern, recursive=True))) if isinstance(d, dict)]


def _walk(node, key: str):
    """Every value under `key`, anywhere in a document."""
    if isinstance(node, dict):
        for k, v in node.items():
            if k == key:
                yield v
            yield from _walk(v, key)
    elif isinstance(node, list):
        for v in node:
            yield from _walk(v, key)


def _as_list(value) -> list:
    if value is None:
        return []
    return list(value) if isinstance(value, (list, tuple, set)) else [value]


def _read(pkg: str) -> dict:
    base = os.path.join(loader._PACKAGES_DIR, pkg)
    exercises = (_yaml(os.path.join(base, 'exercises.yaml')) or {}).get('exercises') or []
    return {
        'philosophy': _yaml(os.path.join(base, 'philosophy.yaml')) or {},
        'frameworks': _documents(pkg, 'frameworks'),
        'archetypes': _documents(pkg, 'archetypes'),
        'exercises': [e for e in exercises if isinstance(e, dict)],
        'media': _yaml(os.path.join(base, 'exercise_media.yaml')) or {},
        'analytics': _yaml(os.path.join(base, 'analytics.yaml')) or {},
        'watch': _yaml(os.path.join(base, 'watch.yaml')) or {},
        'contract': _yaml(os.path.join(base, 'training_contract.yaml')) or {},
    }


def _files(pkg: str) -> list[dict]:
    base = os.path.join(loader._PACKAGES_DIR, pkg)
    return [{'id': fid, 'path': name, 'required': required, 'present': os.path.exists(os.path.join(base, name))}
            for fid, name, required in FILES]


def _shapes(pkg: str, docs: dict) -> list[dict]:
    """Each track's engine shape, as goals.philosophy_to_goal and the
    generator decide it: a contract for the track, else week templates on a
    phase, else the modality scheduler."""
    contract_tracks = (docs['contract'].get('tracks') or {}) if docs['contract'] else {}
    out = []
    for track in phases.tracks_of(docs['philosophy']):
        if track.get('id') in contract_tracks:
            shape = 'contract'
        elif any(p.get('week_templates') for p in track.get('phases') or []):
            shape = 'templates'
        else:
            shape = 'scheduler'
        out.append({'track': track.get('id'), 'name': track.get('name'), 'shape': shape})
    return out


def _outside(pkg: str) -> list[dict]:
    """The records a push needs outside the folder, and whether this one has them."""
    scorecard = _json(_SCORECARD) or {}
    coverage = _json(_COVERAGE) or {}
    golden = _json(_GOLDEN) or {}
    status = ((_yaml(_STATUS) or {}).get('packages') or {})
    prefix = f'{pkg}/'
    return [
        {'id': 'scorecard', 'label': 'Scorecard baseline', 'file': 'tools/scorecard_baseline.json',
         'done': any(k.startswith(prefix) for k in scorecard), 'how': _UPDATE_BASELINE},
        {'id': 'coverage', 'label': 'Exercise coverage baseline', 'file': 'tools/exercise_coverage_baseline.json',
         'done': pkg in coverage, 'how': _UPDATE_BASELINE},
        {'id': 'status', 'label': 'status.yaml row', 'file': 'docs/package-fidelity/status.yaml',
         'done': pkg in status, 'how': _UPDATE_BASELINE},
        {'id': 'golden', 'label': 'Golden program hashes', 'file': 'test_single_lane_golden.json',
         'done': any(k.startswith(prefix) for k in golden), 'how': _RECORD_GOLDEN},
        {'id': 'dossier', 'label': 'Source dossier', 'file': f'docs/package-fidelity/{pkg}.md',
         'done': os.path.exists(os.path.join(_DOSSIERS, f'{pkg}.md')),
         'how': 'write it (docs/package-fidelity/README.md)'},
    ]


def _known() -> dict[str, set]:
    from .analytics import benchmarks_data
    schema = _json(os.path.join(ROOT, 'docs', 'schemas', 'constraints.schema.json')) or {}
    # What an athlete can say they have (constraints.schema.json), and `none`:
    # an exercise that needs nothing.
    equipment = set((((schema.get('properties') or {}).get('equipment') or {}).get('items') or {}).get('enum') or [])
    equipment.add('none')
    vocab = _json(os.path.join(loader._COMMONS_DIR, 'watch_vocabulary.json')) or {}
    return {
        'modalities': set(loader.load_all_modalities()),
        'phase_kinds': set(loader.load_phase_kinds()),
        'equipment': equipment,
        'standards': set(benchmarks_data.known_ids()) | {benchmarks_data.BODYWEIGHT_ID},
        'watch_templates': set(vocab.get('templates') or {}),
    }


def _references(docs: dict) -> dict[str, set]:
    phil = docs['philosophy']
    refs: dict[str, set] = defaultdict(set)
    refs['modalities'] |= set(_as_list(phil.get('bias'))) | set(_as_list(phil.get('scope')))
    for fw in docs['frameworks']:
        spw = fw.get('sessions_per_week')
        if isinstance(spw, dict):
            refs['modalities'] |= set(spw)
    for track in phases.tracks_of(phil):
        refs['phase_kinds'] |= {p.get('kind') for p in track.get('phases') or [] if p.get('kind')}
    for arch in docs['archetypes']:
        if arch.get('modality'):
            refs['modalities'].add(arch['modality'])
        refs['phase_kinds'] |= set(_as_list(arch.get('applicable_phases')))
        refs['equipment'] |= set(_as_list(arch.get('required_equipment')))
    for ex in docs['exercises']:
        refs['equipment'] |= set(_as_list(ex.get('equipment')))
    for doc in (*docs['archetypes'], docs['contract'], docs['philosophy']):
        for value in _walk(doc, 'standard'):
            sid = value.get('id') if isinstance(value, dict) else value
            if isinstance(sid, str):
                refs['standards'].add(sid)
    for entry in _as_list(docs['analytics'].get('benchmarks')):
        sid = entry.get('id') if isinstance(entry, dict) else entry
        if isinstance(sid, str):
            refs['standards'].add(sid)
    refs['watch_templates'] |= {t for t in _walk(docs['watch'], 'template') if isinstance(t, str)}
    return refs


def _vocabulary(refs: dict[str, set], known: dict[str, set]) -> list[dict]:
    return [{'kind': kind, 'count': len(refs.get(kind, ())),
             'unknown': sorted(refs.get(kind, set()) - known[kind])}
            for kind in known]


def _owned_ids(docs: dict) -> dict[str, dict[str, object]]:
    """kind -> {id: what the package says for it}; only media compares the value."""
    media = docs['media'] if isinstance(docs['media'], dict) else {}
    return {
        'philosophy': {docs['philosophy']['id']: None} if docs['philosophy'].get('id') else {},
        'framework': {f['id']: None for f in docs['frameworks'] if f.get('id')},
        'archetype': {a['id']: None for a in docs['archetypes'] if a.get('id')},
        'exercise': {e['id']: None for e in docs['exercises'] if e.get('id')},
        'media': {k: json.dumps(v, sort_keys=True, default=str) for k, v in media.items()},
    }


def collisions(owned: dict[str, dict[str, dict]]) -> tuple[list[dict], int]:
    """(ids two packages declare and the loader resolves silently, how many
    exercise ids are shared). Exercises are shared by design — every
    declaring package keeps its own prescription (loader.load_all_exercises)
    — so they are counted, not flagged; so is one exercise's media where every
    package that lists it says the same."""
    holders: dict[tuple[str, str], dict[str, object]] = defaultdict(dict)
    for pkg, kinds in owned.items():
        for kind, ids in kinds.items():
            for i, value in ids.items():
                holders[(kind, i)][pkg] = value
    found, shared = [], 0
    for (kind, i), by_pkg in sorted(holders.items()):
        if len(by_pkg) < 2:
            continue
        if kind == 'exercise':
            shared += 1
            continue
        if kind == 'media' and len(set(by_pkg.values())) == 1:
            continue
        found.append({'kind': kind, 'id': i, 'packages': sorted(by_pkg), 'kept': _KEPT[kind]})
    return found, shared


def gaps() -> dict:
    return _json(GAPS) or {'gaps': []}


def report() -> dict:
    known = _known()
    names = packages()
    read = {pkg: _read(pkg) for pkg in names}
    owned = {pkg: _owned_ids(docs) for pkg, docs in read.items()}
    found, shared = collisions(owned)
    colliding = defaultdict(int)
    for c in found:
        for pkg in c['packages']:
            colliding[pkg] += 1
    rows = []
    for pkg in names:
        docs = read[pkg]
        files = _files(pkg)
        outside = _outside(pkg)
        vocabulary = _vocabulary(_references(docs), known)
        unknown = sum(len(v['unknown']) for v in vocabulary)
        rows.append({
            'id': pkg,
            'name': docs['philosophy'].get('name', pkg),
            'tracks': _shapes(pkg, docs),
            'files': files,
            'outside': outside,
            'vocabulary': vocabulary,
            'collisions': colliding[pkg],
            # Drops in as it stands: every required file, every record outside
            # the folder, no id the commons lack and none another package owns.
            'ready': (all(f['present'] for f in files if f['required'])
                      and all(o['done'] for o in outside) and not unknown and not colliding[pkg]),
        })
    return {
        'packagesDir': os.path.relpath(loader._PACKAGES_DIR, ROOT),
        'packages': rows,
        'collisions': found,
        'sharedExercises': shared,
        **gaps(),
    }
