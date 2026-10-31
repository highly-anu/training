"""tools/add_package.py and the per-package recording it runs.

`evaluate_packages.py --update-baseline --package <id>` writes that package's
records in its own folder (records/: grades, fidelity findings, orphans,
status; src/package_records.py) and touches no other package's — on a copy of
the packages (`TRAINING_PACKAGES_DIR`), never the repository's. Re-recording a
shipped package writes the files it read, byte for byte. add_package's
refusals: a missing file, an id another package declares, an id the commons
lack. (test_package_dropin.py runs `add_package.py --check` on a dropped-in copy.)

    .venv/bin/python test_add_package.py
"""
from __future__ import annotations

import atexit
import json
import os
import shutil
import sys
import tempfile

ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ROOT)
os.environ.setdefault('SUPABASE_URL', '')
os.environ.setdefault('DATABASE_URL', '')


def _stage() -> str:
    folder = tempfile.mkdtemp(prefix='packages-')
    atexit.register(shutil.rmtree, folder, True)
    for name in sorted(os.listdir(os.path.join(ROOT, 'data', 'packages'))):
        if os.path.isdir(os.path.join(ROOT, 'data', 'packages', name)):
            shutil.copytree(os.path.join(ROOT, 'data', 'packages', name), os.path.join(folder, name))
    os.environ['TRAINING_PACKAGES_DIR'] = folder
    return folder


FOLDER = _stage()
FAILURES: list[str] = []
PKG = 'kelly_starrett'
OTHER = 'atg'
NAMES = ('scorecard.json', 'fidelity.json', 'coverage.json', 'status.yaml')


def check(label: str, condition: bool, detail='') -> None:
    if condition:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label} {detail}")
        FAILURES.append(label)


def _text(pkg: str, name: str) -> str:
    with open(os.path.join(FOLDER, pkg, 'records', name), encoding='utf-8') as fh:
        return fh.read()


def test_record_one_package():
    print('recording one package, in its own folder')
    from tools import check_fidelity as cf, evaluate_packages as ep
    scorecard, fid_rows, orphans = ep.run([PKG])
    current = {f"{PKG}/{tid}|{c}": g[0] for tid, crit in scorecard[PKG].items() for c, g in crit.items()}
    gated = cf.gate(fid_rows, [PKG])[0]
    originals = {n: _text(PKG, n) for n in NAMES}
    others = {n: _text(OTHER, n) for n in NAMES}

    ep.record_packages([PKG], scorecard, current, gated, orphans)
    for n in NAMES:
        check(f're-recording {PKG} writes the {n} it read', _text(PKG, n) == originals[n])

    # A stale row of this package's is dropped; another package's file is never opened.
    path = os.path.join(FOLDER, PKG, 'records', 'scorecard.json')
    rows = json.load(open(path))
    rows['gone_track|E1'] = 'pass'
    json.dump(rows, open(path, 'w'))
    ep.record_packages([PKG], scorecard, current, gated, orphans)
    after = json.load(open(path))
    check("this package's stale row is dropped", 'gone_track|E1' not in after)
    check("its rows are this run's, without the package in the key",
          {f'{PKG}/{k}': v for k, v in after.items()} == current)
    check("another package's records are untouched", all(_text(OTHER, n) == others[n] for n in NAMES))
    check('the repository is untouched', not _changed())


def test_refusals():
    print('what add_package refuses')
    from tools.add_package import _problems
    row = {'id': 'new_pkg',
           'files': [{'path': 'exercises.yaml', 'required': True, 'present': False},
                     {'path': 'watch.yaml', 'required': False, 'present': False}],
           'vocabulary': [{'kind': 'modalities', 'unknown': ['not_a_modality']},
                          {'kind': 'equipment', 'unknown': []}]}
    report = {'packages': [row], 'collisions': [
        {'kind': 'archetype', 'id': 'shared_id', 'packages': ['new_pkg', 'older_pkg'], 'kept': 'the first'},
        {'kind': 'framework', 'id': 'elsewhere', 'packages': ['a', 'b'], 'kept': 'the last'}]}
    problems = _problems('new_pkg', report)
    check('a required file missing', 'exercises.yaml is missing' in problems, problems)
    check('an optional file is not asked for', not any('watch.yaml' in p for p in problems), problems)
    check("an id another package declares, naming it", any("'shared_id'" in p and 'older_pkg' in p
                                                            for p in problems), problems)
    check("another pair's collision is not this package's", not any('elsewhere' in p for p in problems), problems)
    check('an id the commons lack', any("'not_a_modality'" in p for p in problems), problems)


def _status() -> str:
    import subprocess
    return subprocess.run(['git', 'status', '--porcelain', '--', 'data/packages'], cwd=ROOT,
                          capture_output=True, text=True).stdout


BEFORE = _status()


def _changed() -> bool:
    return _status() != BEFORE


def main() -> int:
    test_refusals()
    test_record_one_package()
    if FAILURES:
        print(f'{len(FAILURES)} failed')
        return 1
    print('all passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
