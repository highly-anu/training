#!/usr/bin/env python
"""Bring a package folder in: everything it needs outside its folder, in one command.

A package is a folder under data/packages/ (or TRAINING_PACKAGES_DIR) that
needs no code change (test_package_dropin.py). What it does still need is
outside the folder — the push gates keep a record per package: the scorecard,
fidelity and coverage baselines, its row in docs/package-fidelity/status.yaml,
the golden program hashes and the source dossier. This checks the folder and
writes those, for this package only, every other package's rows untouched:

1. the folder's files against their schemas (tools/validate_entities.py);
2. no id another package declares, no id the commons do not define
   (src/portability.py — Dev Lab ▸ Model Interactions shows the same);
3. a dossier stub, docs/package-fidelity/<id>.md, when there is none;
4. its scorecard, recorded (tools/evaluate_packages.py --update-baseline
   --package): refused when it has a fidelity finding, an orphaned exercise
   or, for a package already recorded, a worse grade — fix the package;
5. its golden programs (test_single_lane_golden.py --record --package).

    .venv/bin/python tools/add_package.py <id>           # check and record
    .venv/bin/python tools/add_package.py <id> --check   # check only; write nothing

Then write the dossier and the record (docs/package-fidelity/README.md) and run
the gates (tools/run_checks.py), which the pre-push hook runs anyway.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
os.environ.setdefault('SUPABASE_URL', '')
os.environ.setdefault('DATABASE_URL', '')

from src import loader, package_fidelity as pf, portability  # noqa: E402

DOSSIER_STUB = """# {name} — source dossier

Engine shape: {shapes}. The record (sources, rules with what enforces each, inventions) is
`data/packages/{pkg}/fidelity.yaml`; this page is its prose, under the same ids. The status
is the scorecard's (status.yaml).

Written by `tools/add_package.py` as a stub: until this page names every rule and invention
of the record by its id, the scorecard's S4 says which it lacks
(docs/package-fidelity/README.md, "The method").

## Sources

## Rules and where they live

## Open

## Inventions

## Tests
"""


def _run(label: str, *argv: str) -> bool:
    print(f'— {label}: {" ".join(os.path.relpath(a, ROOT) if os.path.isabs(a) else a for a in argv)}')
    done = subprocess.run([sys.executable, *argv], cwd=ROOT)
    return done.returncode == 0


def _problems(pkg: str, report: dict) -> list[str]:
    row = next((p for p in report['packages'] if p['id'] == pkg), None)
    out = [f"{f['path']} is missing" for f in row['files'] if f['required'] and not f['present']]
    for c in report['collisions']:
        if pkg in c['packages']:
            others = ', '.join(p for p in c['packages'] if p != pkg)
            out.append(f"{c['kind']} '{c['id']}' is also declared by {others} (the loader keeps {c['kept']})")
    for v in row['vocabulary']:
        for u in v['unknown']:
            out.append(f"{v['kind']}: '{u}' is not in the commons")
    return out


def main() -> int:
    sys.stdout.reconfigure(line_buffering=True)   # in order with the tools it runs
    ap = argparse.ArgumentParser(description='Record what a package needs outside its folder.')
    ap.add_argument('package', help='the folder name under the packages directory')
    ap.add_argument('--check', action='store_true', help='check only; write nothing')
    args = ap.parse_args()
    pkg = args.package
    folder = os.path.join(loader._PACKAGES_DIR, pkg)

    if not os.path.exists(os.path.join(folder, 'philosophy.yaml')):
        print(f'{os.path.relpath(folder, ROOT)}: no philosophy.yaml — not a package folder')
        return 2
    phil = loader._load_yaml(os.path.join(folder, 'philosophy.yaml')) or {}
    if phil.get('id') != pkg:
        print(f"philosophy.yaml's id is {phil.get('id')!r}; it must be the folder's name, {pkg!r}")
        return 1

    if not _run('schemas', 'tools/validate_entities.py', '-q', folder):
        return 1

    print('— ids and vocabulary (src/portability.py)')
    report = portability.report()
    problems = _problems(pkg, report)
    for p in problems:
        print(f'  {p}')
    if problems:
        return 1
    row = next(p for p in report['packages'] if p['id'] == pkg)
    shapes = ', '.join(sorted({t['shape'] for t in row['tracks']})) or 'no tracks'
    print(f"  ok: {len(row['tracks'])} track(s) ({shapes}); no collisions; every id in the commons")

    dossier = pf.dossier_path(pkg)
    if not os.path.exists(dossier):
        if args.check:
            print(f'— dossier: {os.path.relpath(dossier, ROOT)} would be stubbed')
        else:
            with open(dossier, 'w', encoding='utf-8') as fh:
                fh.write(DOSSIER_STUB.format(name=phil.get('name', pkg), pkg=pkg, shapes=shapes))
            print(f'— dossier: stubbed {os.path.relpath(dossier, ROOT)}')

    scorecard = ['tools/evaluate_packages.py', '--update-baseline', '--package', pkg]
    if not _run('scorecard', *scorecard, *(['--dry-run'] if args.check else [])):
        return 1
    if not args.check:
        if not _run('golden programs', 'test_single_lane_golden.py', '--record', '--package', pkg):
            return 1

    print()
    if args.check:
        print(f'{pkg} can be brought in: run without --check to record it.')
        return 0
    print(f'{pkg} is recorded. Still to do:')
    if pf.load(pkg) is None:
        print(f'  - write data/packages/{pkg}/fidelity.yaml (docs/schemas/fidelity.schema.json)')
    print(f'  - write {os.path.relpath(dossier, ROOT)} from the sources (docs/package-fidelity/README.md)')
    print('  - run the gates: .venv/bin/python tools/run_checks.py (the pre-push hook runs them too)')
    print('  - commit the folder with tools/scorecard_baseline.json, tools/exercise_coverage_baseline.json,')
    print('    tools/fidelity_baseline.json, docs/package-fidelity/status.yaml, test_single_lane_golden.json')
    print('    and the dossier')
    return 0


if __name__ == '__main__':
    sys.exit(main())
