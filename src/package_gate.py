"""One package, checked in process: is this folder a package the app can run?

The push gates answer that for every package at once, in tools that print
(validate_entities, check_styles, check_provenance, add_package). A package
written at runtime — by an agent through mcp_server.py today, by the LLM
package builder next (docs/roadmap.md item 20) — needs the same answer for
one folder, as data it can hand back to whoever wrote it. `check_package`
runs the gates' own code, stage by stage:

  files       a philosophy.yaml whose id is the folder's name
  schema      every file against its schema and the checks beside it
              (tools/validate_entities.py)
  ids         the files a package needs, no id another package declares,
              every id in the commons (src/portability.py); for an athlete's
              own package, every id it declares carries its owner's prefix
  smoke       every phase of every track validates and generates on the
              framework it names, and places its tests (src/package_smoke.py)
  provenance  no session or exercise from outside the package and what it
              borrows

A stage runs only when the ones before it found nothing: generating from a
folder whose files do not validate raises wherever the loader trips. `ids`,
`smoke` and `provenance` read through the loader, so they need the folder to
sit in a directory the loader reads for the caller — the shipped packages'
or its overlay (loader.overlay); elsewhere they are listed in `skipped`,
never silently passed.

The result:
  {package, ok, problems: [{stage, code, file, message}],
   warnings: [...same shape], ran: [stage…], skipped: [{stage, why}],
   tracks: [{track, phases}], seconds}

`ok` is true only when every stage ran and found nothing. Not checked here:
the scorecard and the golden programs (tools/add_package.py records them for
a package that ships in the repository).
"""
from __future__ import annotations

import os
import time

import yaml

from src import loader, phases, portability, provenance

STAGES = ('files', 'schema', 'ids', 'smoke', 'provenance')


def _problem(stage: str, code: str, message: str, file: str | None = None) -> dict:
    return {'stage': stage, 'code': code, 'file': file, 'message': message}


def _files(pkg_dir: str, pkg: str) -> list[dict]:
    path = os.path.join(pkg_dir, 'philosophy.yaml')
    if not os.path.isdir(pkg_dir):
        return [_problem('files', 'not_a_folder', f'{pkg_dir} is not a folder')]
    if not os.path.exists(path):
        return [_problem('files', 'no_philosophy', 'no philosophy.yaml — not a package folder', 'philosophy.yaml')]
    try:
        with open(path, encoding='utf-8') as fh:
            phil = yaml.safe_load(fh) or {}
    except yaml.YAMLError as e:
        return [_problem('files', 'yaml', f'philosophy.yaml does not parse: {e}', 'philosophy.yaml')]
    if not isinstance(phil, dict) or phil.get('id') != pkg:
        got = phil.get('id') if isinstance(phil, dict) else None
        return [_problem('files', 'id_not_folder',
                         f"philosophy.yaml's id is {got!r}; it must be the folder's name, {pkg!r}", 'philosophy.yaml')]
    return []


def _schema(pkg_dir: str) -> list[dict]:
    from tools import validate_entities   # the gate's validator; tools/ ships in the image
    out = []
    for path, errors in validate_entities.validate_path(pkg_dir, verbose=False).items():
        rel = os.path.relpath(path, pkg_dir).replace(os.sep, '/')
        out += [_problem('schema', 'invalid', e, rel) for e in errors or []]
    return out


def _scope_warnings(pkg_dir: str) -> list[dict]:
    """A modality the philosophy's scope names that no archetype of the
    package serves: legal (a borrowed package may serve it), worth saying."""
    try:
        with open(os.path.join(pkg_dir, 'philosophy.yaml'), encoding='utf-8') as fh:
            scope = set((yaml.safe_load(fh) or {}).get('scope') or [])
        served = set()
        for root, _dirs, names in os.walk(os.path.join(pkg_dir, 'archetypes')):
            for name in names:
                if name.endswith('.yaml'):
                    with open(os.path.join(root, name), encoding='utf-8') as fh:
                        served.add((yaml.safe_load(fh) or {}).get('modality'))
    except (OSError, yaml.YAMLError, AttributeError):
        return []
    return [_problem('schema', 'scope_unserved',
                     f"modality '{m}' is in scope but has no archetype in this package", 'philosophy.yaml')
            for m in sorted(scope - served)]


def _ids(pkg: str) -> list[dict]:
    out = []
    for message in portability.problems(pkg, portability.report()):
        code = ('missing_file' if message.endswith('is missing')
                else 'collision' if 'is also declared by' in message
                else 'unknown_id' if 'is not in the commons' in message else 'not_a_package')
        out.append(_problem('ids', code, message))
    return out


def _prefix(pkg_dir: str, pkg: str, prefix: str) -> list[dict]:
    """An athlete's own package (docs/roadmap.md 20.3): its id and every id it
    declares for itself — frameworks, archetypes, standards and their
    categories — carry the owner's prefix, so nothing it brings can be taken
    for a shipped id or another athlete's. An exercise id either carries it or
    is one a shipped package declares (an exercise is shared by design, the
    shipped copy the structural one)."""
    out = []

    def want(kind: str, value, file: str):
        if not str(value or '').startswith(prefix):
            out.append(_problem('ids', 'not_prefixed', f"{kind} '{value}' must start with '{prefix}'", file))

    def docs(*parts, recursive=False):
        import glob
        for path in sorted(glob.glob(os.path.join(pkg_dir, *parts), recursive=recursive)):
            with open(path, encoding='utf-8') as fh:
                yield os.path.relpath(path, pkg_dir).replace(os.sep, '/'), yaml.safe_load(fh) or {}

    want('package', pkg, 'philosophy.yaml')
    for rel, doc in docs('frameworks', '*.yaml'):
        want('framework', doc.get('id'), rel)
    for rel, doc in docs('archetypes', '**', '*.yaml', recursive=True):
        want('archetype', doc.get('id'), rel)
    for rel, doc in docs('standards.yaml'):
        for item in doc.get('standards') or []:
            want('standard', item.get('id'), rel)
        for item in doc.get('categories') or []:
            want('standard category', item.get('id'), rel)
    for rel, doc in docs('vocabulary.yaml'):
        for item in doc.get('modalities') or []:
            want('modality', item.get('id'), rel)
        for item in doc.get('movement_patterns') or []:
            want('movement pattern', item.get('id'), rel)
        for item in doc.get('equipment') or []:
            want('equipment', item.get('id'), rel)
    with loader.overlay(None):   # what the shipped packages declare, whoever asks
        shipped, _ = loader.load_all_exercises()
    for rel, doc in docs('exercises.yaml'):
        for item in doc.get('exercises') or []:
            eid = str(item.get('id') or '')
            if not eid.startswith(prefix) and eid not in shipped:
                out.append(_problem('ids', 'not_prefixed',
                                    f"exercise '{eid}' must start with '{prefix}' or be an exercise a shipped "
                                    'package declares', rel))
    return out


def _smoke(pkg: str) -> tuple[list[dict], list[dict]]:
    """→ (problems, the one-week programs that generated, each with its label)."""
    from src import package_smoke
    problems, programs = [], []
    try:
        results = package_smoke.smoke_package(pkg)
    except Exception as e:   # a package the loader or the generator trips on is a finding, not a crash
        return [_problem('smoke', 'raised', f'{type(e).__name__}: {e}')], []
    if not results:
        problems.append(_problem('smoke', 'no_phases', 'no track with a phase: nothing to generate'))
    for r in results:
        if r['missing_framework']:
            problems.append(_problem('smoke', 'missing_framework', f"{r['label']}: {r['why']}"))
        elif not r['ok']:
            code = 'infeasible' if isinstance(r['why'], list) and r['why'] and not str(r['why'][0]).startswith('ran ') \
                else 'wrong_framework' if isinstance(r['why'], list) else 'no_sessions'
            problems.append(_problem('smoke', code, f"{r['label']}: {r['why']}"))
        for p in r['test_problems'] or []:
            problems.append(_problem('smoke', 'test_not_placed', f"{r['label']}: {p}"))
        if r['program']:
            programs.append((r['label'], r['program']))
    return problems, programs


def _coverage_warnings(programs: list) -> list[dict]:
    """What the generated weeks could not cover although the athlete had every
    implement: a session no archetype serves, one that stands in for another
    modality, a slot no exercise fills. Legal — a shipped method may leave a
    level unserved — and nearly always authoring; the app's builder holds its
    own packages to none (src/package_builder.py)."""
    out, seen = [], set()

    def add(code, label, message):
        phase = label.rsplit('/', 1)[0]            # once per track, not per phase
        if (code, phase, message) not in seen:
            seen.add((code, phase, message))
            out.append(_problem('smoke', code, f'{label}: {message}'))
    for label, raw in programs:
        report = raw.get('coverage_report') or {}
        for s in report.get('unfilled_sessions') or []:
            add('unfilled_session', label, f"no archetype of this package serves a '{s.get('modality')}' session")
        for s in report.get('substituted_sessions') or []:
            add('substituted_session', label, f"a '{s.get('substituted_for')}' session was replaced by "
                f"'{s.get('modality')}' ({s.get('reason')})")
        for s in report.get('unfilled_slots') or []:
            add('unfilled_slot', label, f"slot '{s.get('slot_role')}' of archetype '{s.get('archetype')}' is empty"
                + (f" ({s.get('reason')})" if s.get('reason') else ''))
    return out


def _provenance(pkg: str, programs: list) -> list[dict]:
    from src import goals, package_smoke
    frameworks = list(loader.load_all_frameworks().values())
    policy = provenance.resolve_source_policy(goals.philosophy_to_goal(pkg, frameworks))
    if not policy.strict:
        return []
    ex_index = loader.load_all_data()['exercises']
    out, seen = [], set()
    for label, raw in programs:
        for leak in package_smoke.audit_program(raw, policy, ex_index)['foreign']:
            if leak not in seen:
                seen.add(leak)
                out.append(_problem('provenance', 'foreign', f'{label}: {leak}'))
    return out


def _tracks(pkg: str) -> list[dict]:
    phil = next((p for p in loader.load_philosophies() if p['id'] == pkg), None)
    return [{'track': t['id'], 'phases': [ph['id'] for ph in t['phases']]} for t in phases.tracks_of(phil)] if phil else []


def check_package(pkg_dir: str, *, smoke: bool = True, owner_prefix: str | None = None) -> dict:
    """Check one package folder. `smoke=False` stops before generating (the
    schema and id stages take well under a second; a smoke run about a second
    a phase). `owner_prefix`: the folder is an athlete's own package, and every
    id it declares for itself must carry that prefix (`_prefix`)."""
    started = time.monotonic()
    pkg_dir = os.path.abspath(pkg_dir)
    pkg = os.path.basename(pkg_dir.rstrip(os.sep))
    # In a root the loader reads for this caller: the shipped packages, or its overlay.
    roots = [loader._PACKAGES_DIR] + ([loader.overlay_dir()] if loader.overlay_dir() else [])
    in_root = os.path.realpath(os.path.dirname(pkg_dir)) in {os.path.realpath(r) for r in roots}
    problems: list[dict] = []
    warnings: list[dict] = []
    ran: list[str] = []
    skipped: list[dict] = []
    tracks: list[dict] = []

    def skip(stages, why):
        skipped.extend({'stage': s, 'why': why} for s in stages)

    def finish():
        return {'package': pkg, 'ok': not problems and not skipped, 'problems': problems, 'warnings': warnings,
                'ran': ran, 'skipped': skipped, 'tracks': tracks, 'seconds': round(time.monotonic() - started, 2)}

    ran.append('files')
    problems += _files(pkg_dir, pkg)
    if problems:
        skip(STAGES[1:], 'the folder is not a package yet')
        return finish()

    ran.append('schema')
    try:
        problems += _schema(pkg_dir)
    except Exception as e:   # the validator met something it does not expect: a finding, never a crash
        problems.append(_problem('schema', 'raised', f'{type(e).__name__}: {e}'))
    warnings += _scope_warnings(pkg_dir)
    if problems:
        skip(STAGES[2:], 'its files do not validate')
        return finish()

    if not in_root:
        skip(STAGES[2:], "the folder is not in a packages directory the loader reads "
                         f'({os.path.relpath(loader._PACKAGES_DIR, portability.ROOT)}, or the caller\'s overlay)')
        return finish()

    ran.append('ids')
    problems += _ids(pkg)
    if owner_prefix:
        problems += _prefix(pkg_dir, pkg, owner_prefix)
    if problems:
        skip(STAGES[3:], 'its ids collide or are not in the commons')
        return finish()
    tracks += _tracks(pkg)

    if not smoke:
        skip(STAGES[3:], 'not asked for')
        return finish()

    ran.append('smoke')
    found, programs = _smoke(pkg)
    problems += found
    warnings += _coverage_warnings(programs)
    if any(p['code'] == 'raised' for p in found):
        skip(STAGES[4:], 'generation raised')
        return finish()

    ran.append('provenance')
    try:
        problems += _provenance(pkg, programs)
    except Exception as e:
        problems.append(_problem('provenance', 'raised', f'{type(e).__name__}: {e}'))
    return finish()
