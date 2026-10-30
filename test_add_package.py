#!/usr/bin/env python
"""tools/add_package.py and the per-package recording it runs.

`evaluate_packages.py --update-baseline --package <id>` replaces that
package's rows in the scorecard, fidelity and coverage baselines and its
status.yaml entry, and keeps every other package's as recorded — on copies
of the baselines, never the repository's. Re-recording a shipped package
writes the files it read, byte for byte. add_package's refusals: a missing
file, an id another package declares, an id the commons lack.
(test_package_dropin.py runs `add_package.py --check` on a dropped-in copy.)

    .venv/bin/python test_add_package.py
"""
from __future__ import annotations

import json
import os
import shutil
import sys
import tempfile

ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ROOT)
os.environ.setdefault('SUPABASE_URL', '')
os.environ.setdefault('DATABASE_URL', '')

FAILURES: list[str] = []
PKG = 'kelly_starrett'


def check(label: str, condition: bool, detail='') -> None:
    if condition:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label} {detail}")
        FAILURES.append(label)


def test_record_one_package():
    print('recording one package')
    from tools import check_exercise_coverage as coverage, check_fidelity as cf, evaluate_packages as ep
    from pathlib import Path
    tmp = tempfile.mkdtemp(prefix='baselines-')
    try:
        paths = {'grades': os.path.join(tmp, 'scorecard.json'), 'findings': os.path.join(tmp, 'fidelity.json'),
                 'orphans': os.path.join(tmp, 'coverage.json'), 'status': os.path.join(tmp, 'status.yaml')}
        for key, src in (('grades', ep.BASELINE), ('findings', cf.BASELINE), ('orphans', str(coverage.BASELINE)),
                         ('status', ep.STATUS)):
            shutil.copy(src, paths[key])
        saved = ep.BASELINE, cf.BASELINE, coverage.BASELINE, ep.STATUS
        ep.BASELINE, cf.BASELINE, coverage.BASELINE, ep.STATUS = (
            paths['grades'], paths['findings'], Path(paths['orphans']), paths['status'])
        try:
            scorecard, fid_rows, orphans = ep.run([PKG])
            current = {f"{PKG}/{tid}|{c}": g[0] for tid, crit in scorecard[PKG].items() for c, g in crit.items()}
            gated = cf.gate(fid_rows, [PKG])[0]
            originals = {k: open(p, encoding='utf-8').read() for k, p in paths.items()}

            ep.record_packages([PKG], scorecard, current, gated, orphans)
            for k, p in paths.items():
                check(f're-recording {PKG} writes the {k} it read', open(p, encoding='utf-8').read() == originals[k])

            # Another package's rows stay; this one's are replaced, not added to.
            grades = json.load(open(paths['grades']))
            grades = {k: v for k, v in grades.items() if not k.startswith(f'{PKG}/')}
            grades['zz_other/track|E1'] = 'fail'
            grades[f'{PKG}/gone_track|E1'] = 'pass'
            json.dump(grades, open(paths['grades'], 'w'))
            orphans_doc = json.load(open(paths['orphans']))
            orphans_doc['zz_other'] = ['an_exercise']
            json.dump(orphans_doc, open(paths['orphans'], 'w'))
            ep.record_packages([PKG], scorecard, current, gated, orphans)
            after = json.load(open(paths['grades']))
            check("another package's grade is kept", after.get('zz_other/track|E1') == 'fail')
            check("this package's stale row is dropped", f'{PKG}/gone_track|E1' not in after)
            check("this package's rows are this run's",
                  {k: v for k, v in after.items() if k.startswith(f'{PKG}/')} == current)
            check("another package's orphans are kept", json.load(open(paths['orphans'])).get('zz_other') == ['an_exercise'])
        finally:
            ep.BASELINE, cf.BASELINE, coverage.BASELINE, ep.STATUS = saved
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    check('the repository baselines are untouched', not _changed())


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


def _changed() -> bool:
    import subprocess
    out = subprocess.run(['git', 'status', '--porcelain', '--', 'tools/scorecard_baseline.json',
                          'tools/fidelity_baseline.json', 'tools/exercise_coverage_baseline.json',
                          'docs/package-fidelity/status.yaml'], cwd=ROOT, capture_output=True, text=True).stdout
    return bool(out.strip())


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
