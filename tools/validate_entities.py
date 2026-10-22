#!/usr/bin/env python3
"""
Validate training system YAML entity files against their JSON schemas.

Usage:
    python tools/validate_entities.py data/packages/horsemen_gpp/frameworks/gpp_circuits.yaml
    python tools/validate_entities.py data/packages/horsemen_gpp/
    python tools/validate_entities.py --all

Requires: jsonschema  (pip install jsonschema)
"""
import sys
import os
import glob
import json
import argparse

import yaml

try:
    import jsonschema
except ImportError:
    print("ERROR: jsonschema not installed. Run: pip install jsonschema")
    sys.exit(1)

# ---------------------------------------------------------------------------
# Schema detection: infer which schema applies to a file/directory
# ---------------------------------------------------------------------------

_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_SCHEMA_DIR = os.path.join(_ROOT, 'docs', 'schemas')

_PATH_TO_SCHEMA = {
    'philosophies': 'philosophy.schema.json',
    'frameworks':   'framework.schema.json',
    'modalities':   'modality.schema.json',
    'archetypes':   'archetype.schema.json',
    'exercises':    'exercise.schema.json',
    'goals':        'goal_profile.schema.json',
    # benchmarks: detected by path in _detect_schema — the list files against
    # benchmark.schema.json; cell_standards.yaml keeps its nested format
}

# Schemas that wrap a list (exercises file has top-level `exercises:` list)
_LIST_SCHEMAS = {'exercises'}


def _detect_schema(path: str) -> tuple[str | None, bool]:
    """Return (schema_filename, is_list_file) for a given path, or (None, False)."""
    norm = path.replace('\\', '/')
    basename = os.path.basename(norm)
    if basename == 'training_contract.yaml':
        return 'training_contract.schema.json', False
    # Vertical packages name files rather than nesting them in a typed directory.
    if basename == 'philosophy.yaml':
        return 'philosophy.schema.json', False
    if basename == 'exercises.yaml':
        return 'exercise.schema.json', True
    if basename == 'analytics.yaml':
        return 'analytics.schema.json', False
    if basename == 'watch.yaml':
        return 'watch.schema.json', False
    if basename == 'fidelity.yaml':
        return 'fidelity.schema.json', False
    if basename == 'source_weeks.yaml':
        return 'source_weeks.schema.json', False
    # The standards' list files (benchmarks_data.BENCHMARK_FILES); The Cell's
    # file keeps its own nested format and stays unvalidated.
    if '/data/benchmarks/' in norm and basename.endswith('.yaml') and basename != 'cell_standards.yaml':
        return 'benchmark.schema.json', True
    for part in norm.split('/'):
        if part in _PATH_TO_SCHEMA:
            return _PATH_TO_SCHEMA[part], part in _LIST_SCHEMAS
    return None, False


def _load_schema(schema_filename: str) -> dict:
    path = os.path.join(_SCHEMA_DIR, schema_filename)
    with open(path, encoding='utf-8') as f:
        return json.load(f)


# ---------------------------------------------------------------------------
# Extra checks beyond JSON Schema
# ---------------------------------------------------------------------------

def _extra_checks(data: dict, schema_filename: str, path: str | None = None) -> list[str]:
    """Return a list of error strings for checks not covered by JSON Schema."""
    errors = []

    if schema_filename in ('archetype.schema.json', 'exercise.schema.json') and data.get('icon'):
        # A workout icon is one the commons vocabulary lists (src/session_icon.py).
        sys.path.insert(0, _ROOT)
        from src import session_icon
        if data['icon'] not in session_icon.icon_ids():
            errors.append(f"icon '{data['icon']}' is not in data/commons/workout_icons.json")

    if schema_filename == 'philosophy.schema.json' and path:
        # Track and phase ids unique; every phase's framework is this package's.
        sys.path.insert(0, _ROOT)
        from src import phases
        fw_dir = os.path.join(os.path.dirname(path), 'frameworks')
        own = {os.path.splitext(os.path.basename(f))[0]
               for f in glob.glob(os.path.join(fw_dir, '*.yaml'))}
        errors.extend(phases.validate_philosophy_tracks(data, own))
        # Each test a phase declares is one of this package's test archetypes.
        own_tests, pool_only = {}, {}
        for f in glob.glob(os.path.join(os.path.dirname(path), 'archetypes', '**', '*.yaml'), recursive=True):
            with open(f, encoding='utf-8') as fh:
                arch = yaml.safe_load(fh) or {}
            own_tests[arch.get('id')] = 'test' in arch
            pool_only[arch.get('id')] = bool(arch.get('pool_only'))
        frameworks = {}
        for f in glob.glob(os.path.join(fw_dir, '*.yaml')):
            with open(f, encoding='utf-8') as fh:
                fw = yaml.safe_load(fh) or {}
            frameworks[fw.get('id')] = fw
        pooled = set()
        for track in data.get('tracks') or []:
            for ph in track.get('phases') or []:
                # A week template names its framework's day categories, whose
                # pools are this package's pool-only named workouts.
                if not ph.get('week_templates'):
                    continue
                fw = frameworks.get(ph.get('framework_id')) or {}
                cats = fw.get('categories') or {}
                where = f"{track.get('id')}/{ph.get('id')}"
                if not cats:
                    errors.append(f"{where}: week_templates on a framework with no categories")
                named = {c for w in ph['week_templates'] for d in w if d != 'rest'
                         for c in ([d] if isinstance(d, str) else d if isinstance(d, list) else d['categories'])}
                named |= set(ph.get('drop_order') or [])
                if fw.get('warm_up_category'):
                    named.add(fw['warm_up_category'])
                for c in sorted(named - set(cats)):
                    errors.append(f"{where}: day category '{c}' is not in {fw.get('id')}'s categories")
                for cid, cat in cats.items():
                    for other in cat.get('fallback') or []:
                        if other not in cats:
                            errors.append(f"{fw.get('id')}: category '{cid}' falls back to unknown '{other}'")
                    for aid in cat['archetypes']:
                        pooled.add(aid)
                        if aid not in pool_only:
                            errors.append(f"{fw.get('id')}: category '{cid}' names '{aid}', not an archetype of this package")
        for aid, flag in pool_only.items():
            if flag and aid not in pooled and frameworks:
                errors.append(f"'{aid}' is pool_only but no day category of a templated phase names it")
        for track in data.get('tracks') or []:
            for ph in track.get('phases') or []:
                for t in ph.get('tests') or []:
                    for aid in t.get('archetypes') or ([t['archetype']] if t.get('archetype') else []):
                        if aid not in own_tests:
                            errors.append(f"{track.get('id')}/{ph.get('id')}: test '{aid}' is not an archetype of this package")
                        elif not own_tests[aid]:
                            errors.append(f"{track.get('id')}/{ph.get('id')}: '{aid}' is tested but declares no `test:`")

    if schema_filename == 'archetype.schema.json':
        # A standard slot points at a standard that exists, with a result its
        # slot type and the standard's metric agree on, and an exercise it
        # names; a test has at least one.
        sys.path.insert(0, _ROOT)
        from src import standard_tests
        from src.analytics import benchmarks_data
        known = benchmarks_data.by_id()
        scored = 0
        for slot in data.get('slots') or []:
            if not slot.get('standard'):
                continue
            scored += 1
            ref = standard_tests.standard_ref(slot)
            b = known.get(ref['id'])
            if b is None:
                errors.append(f"slot '{slot.get('role')}': unknown standard '{ref['id']}'")
                continue
            kind = ref.get('result')
            spec = standard_tests.RESULTS.get(kind or '')
            if spec is None:
                errors.append(f"slot '{slot.get('role')}': no result kind fits slot type "
                              f"'{slot.get('slot_type')}' and metric '{b['metric_type']}' — say `result:`")
            elif b['metric_type'] not in spec['metrics']:
                errors.append(f"slot '{slot.get('role')}': result '{kind}' cannot be a {b['metric_type']} "
                              f"({ref['id']})")
            if not (slot.get('exercise_filter') or {}).get('exercise_ids'):
                errors.append(f"slot '{slot.get('role')}' measures {ref['id']} but names no exercise_ids")
        if 'test' in data and not scored:
            errors.append("a test archetype with no slot that measures a standard")
        # A rep scheme is one count a round: as long as its piece's rounds, and
        # never beside a single count.
        rounds_of = {s.get('role'): s.get('rounds') for s in data.get('slots') or []}
        for slot in data.get('slots') or []:
            scheme = slot.get('rep_scheme')
            if not scheme:
                continue
            if slot.get('reps_per_round'):
                errors.append(f"slot '{slot.get('role')}': rep_scheme and reps_per_round both given")
            rounds = slot.get('rounds') or rounds_of.get(slot.get('parent_slot_role'))
            if rounds and rounds != len(scheme):
                errors.append(f"slot '{slot.get('role')}': rep_scheme {scheme} in {rounds} rounds")

    if schema_filename == 'framework.schema.json':
        # intensity_distribution must sum to 1.0
        dist = data.get('intensity_distribution') or {}
        if dist:
            total = sum(dist.values())
            if not (0.995 <= total <= 1.005):
                errors.append(
                    f"intensity_distribution sums to {total:.4f}, expected 1.0 "
                    f"(values: {dict(dist)})"
                )

    if schema_filename == 'goal_profile.schema.json':
        # priorities must sum to ~1.0
        priorities = data.get('priorities') or {}
        if priorities:
            total = sum(priorities.values())
            if not (0.95 <= total <= 1.05):
                errors.append(
                    f"priorities sum to {total:.3f}, expected ~1.0 ±0.05 "
                    f"(values: {dict(priorities)})"
                )

    return errors


def _package_catalogs() -> dict[str, set]:
    """Each package's exercise ids, with those of the packages it borrows from."""
    own, borrows = {}, {}
    for pkg_dir in sorted(glob.glob(os.path.join(_ROOT, 'data', 'packages', '*'))):
        pkg = os.path.basename(pkg_dir)
        ex_path = os.path.join(pkg_dir, 'exercises.yaml')
        if not os.path.exists(ex_path):
            continue
        with open(ex_path, encoding='utf-8') as f:
            data = yaml.safe_load(f) or []
        items = data if isinstance(data, list) else (data.get('exercises') or [])
        own[pkg] = {e.get('id') for e in items}
        with open(os.path.join(pkg_dir, 'philosophy.yaml'), encoding='utf-8') as f:
            borrows[pkg] = [b['package'] for b in (yaml.safe_load(f) or {}).get('borrows_from') or []]
    return {pkg: ids.union(*(own.get(b, set()) for b in borrows[pkg])) for pkg, ids in own.items()}


def _injury_flag_errors(data: dict) -> list[str]:
    """Every exercise an injury flag names exists, and each substitution pair
    is declared together in one package: a program draws only on its own
    packages, so a pair split across two could never be given."""
    catalogs = _package_catalogs()
    every = set().union(*catalogs.values())
    errors = []
    for flag in data.get('injury_flags') or []:
        fid = flag.get('id')
        for eid in flag.get('excluded_exercises') or []:
            if eid not in every:
                errors.append(f"{fid}: excluded exercise {eid!r} is in no package")
        for mod in flag.get('modified_exercises') or []:
            was, use = mod.get('instead_of'), mod.get('use')
            if not any(was in ids and use in ids for ids in catalogs.values()):
                errors.append(f"{fid}: {was!r} -> {use!r} are not declared together in any package")
    return errors


# ---------------------------------------------------------------------------
# Validation logic
# ---------------------------------------------------------------------------

def validate_file(path: str, verbose: bool = True) -> list[str]:
    """Validate a single YAML file. Returns list of error strings (empty = OK)."""
    errors = []

    # Load YAML
    try:
        with open(path, encoding='utf-8') as f:
            data = yaml.safe_load(f)
    except Exception as e:
        return [f"YAML parse error: {e}"]

    if data is None:
        return ["File is empty"]

    if os.path.basename(path) == 'injury_flags.yaml':
        return _injury_flag_errors(data)

    schema_filename, is_list_file = _detect_schema(path)
    if schema_filename is None:
        if verbose:
            print(f"  SKIP  {path} (no schema detected for this path)")
        return []

    schema = _load_schema(schema_filename)

    # For exercise files: validate each item in the list individually
    if is_list_file:
        # An exercises file may wrap its list; a standards file is the list.
        items = data if isinstance(data, list) else (data.get('exercises') or [])
        if not isinstance(items, list):
            return [f"Expected top-level 'exercises:' list, got {type(items).__name__}"]
        for i, item in enumerate(items):
            try:
                jsonschema.validate(instance=item, schema=schema)
            except jsonschema.ValidationError as e:
                errors.append(f"[{i}] ({item.get('id', '?')}): {e.message}")
            extra = _extra_checks(item, schema_filename)
            errors.extend(f"[{i}] ({item.get('id', '?')}): {e}" for e in extra)
    else:
        try:
            jsonschema.validate(instance=data, schema=schema)
        except jsonschema.ValidationError as e:
            errors.append(e.message)
        extra = _extra_checks(data, schema_filename, path)
        errors.extend(extra)

    return errors


def validate_path(path: str, verbose: bool = True) -> dict[str, list[str]]:
    """Validate a file or directory. Returns {filepath: [errors]}."""
    results = {}
    path = os.path.abspath(path)

    if os.path.isfile(path):
        results[path] = validate_file(path, verbose)
    elif os.path.isdir(path):
        for yaml_path in sorted(glob.glob(os.path.join(path, '**', '*.yaml'), recursive=True)):
            results[yaml_path] = validate_file(yaml_path, verbose)
    else:
        print(f"ERROR: path not found: {path}")

    return results


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description='Validate training system YAML entity files against JSON schemas.'
    )
    parser.add_argument(
        'paths',
        nargs='*',
        help='YAML file(s) or directories to validate'
    )
    parser.add_argument(
        '--all',
        action='store_true',
        help='Validate all entity files in data/'
    )
    parser.add_argument(
        '-q', '--quiet',
        action='store_true',
        help='Only print errors, suppress OK messages'
    )
    args = parser.parse_args()

    if not args.paths and not args.all:
        parser.print_help()
        sys.exit(0)

    targets = list(args.paths)
    if args.all:
        # Everything lives under data/packages/ since the vertical migration; the
        # old top-level data/<type>/ directories are gone, so --all used to find
        # nothing and report "0/0 files valid".
        packages_dir = os.path.join(_ROOT, 'data', 'packages')
        if os.path.isdir(packages_dir):
            targets.append(packages_dir)
        commons_dir = os.path.join(_ROOT, 'data', 'commons')
        if os.path.isdir(commons_dir):
            targets.append(commons_dir)
        benchmarks_dir = os.path.join(_ROOT, 'data', 'benchmarks')
        if os.path.isdir(benchmarks_dir):
            targets.append(benchmarks_dir)

    all_results: dict[str, list[str]] = {}
    for target in targets:
        all_results.update(validate_path(target, verbose=not args.quiet))

    def _safe_print(msg: str):
        """Print with ASCII fallback for terminals that don't support Unicode."""
        try:
            print(msg)
        except UnicodeEncodeError:
            print(msg.encode('ascii', errors='replace').decode('ascii'))

    # Print results
    total_files = 0
    error_files = 0
    skip_files = 0

    for filepath, errors in all_results.items():
        rel = os.path.relpath(filepath, _ROOT)
        if errors is None:
            skip_files += 1
            continue
        total_files += 1
        if errors:
            error_files += 1
            _safe_print(f"  FAIL  {rel}")
            for e in errors:
                _safe_print(f"        - {e}")
        elif not args.quiet:
            _safe_print(f"  OK    {rel}")

    print()
    ok_files = total_files - error_files
    print(f"Results: {ok_files}/{total_files} files valid"
          + (f", {skip_files} skipped" if skip_files else ""))

    if error_files:
        sys.exit(1)


if __name__ == '__main__':
    main()
