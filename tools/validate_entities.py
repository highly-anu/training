#!/usr/bin/env python3
"""
Validate training system YAML entity files against their JSON schemas.

Usage:
    python tools/validate_entities.py data/frameworks/theragun_recovery.yaml
    python tools/validate_entities.py data/philosophies/ data/frameworks/
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
    # benchmarks: skipped — cell_standards.yaml uses a custom nested format
    # that predates the benchmark.schema.json individual-entry format
}

# Schemas that wrap a list (exercises file has top-level `exercises:` list)
_LIST_SCHEMAS = {'exercises'}


def _detect_schema(path: str) -> tuple[str | None, bool]:
    """Return (schema_filename, is_list_file) for a given path, or (None, False)."""
    parts = path.replace('\\', '/').split('/')
    for i, part in enumerate(parts):
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

def _extra_checks(data: dict, schema_filename: str) -> list[str]:
    """Return a list of error strings for checks not covered by JSON Schema."""
    errors = []

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

    schema_filename, is_list_file = _detect_schema(path)
    if schema_filename is None:
        if verbose:
            print(f"  SKIP  {path} (no schema detected for this path)")
        return []

    schema = _load_schema(schema_filename)

    # For exercise files: validate each item in the list individually
    if is_list_file:
        items = data.get('exercises') or []
        if not isinstance(items, list):
            return [f"Expected top-level 'exercises:' list, got {type(items).__name__}"]
        for i, item in enumerate(items):
            try:
                jsonschema.validate(instance=item, schema=schema)
            except jsonschema.ValidationError as e:
                errors.append(f"exercises[{i}] ({item.get('id', '?')}): {e.message}")
            extra = _extra_checks(item, schema_filename)
            errors.extend(f"exercises[{i}] ({item.get('id', '?')}): {e}" for e in extra)
    else:
        try:
            jsonschema.validate(instance=data, schema=schema)
        except jsonschema.ValidationError as e:
            errors.append(e.message)
        extra = _extra_checks(data, schema_filename)
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
        data_dir = os.path.join(_ROOT, 'data')
        for subdir in _PATH_TO_SCHEMA:
            candidate = os.path.join(data_dir, subdir)
            if os.path.isdir(candidate):
                targets.append(candidate)

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
