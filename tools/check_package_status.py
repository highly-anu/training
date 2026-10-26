"""The package records against the repository, and status.yaml against them.

Each package's record (data/packages/<id>/fidelity.yaml) names its own tracks
in `currency` and `excluded_tracks`; docs/package-fidelity/status.yaml is
exactly what the records and the recorded scorecard
(tools/scorecard_baseline.json, written by tools/evaluate_packages.py) write —
so a status cannot be typed, and "audited" cannot outlive the grades that
earned it. A package without a record is `not_started`; nothing outside its
folder lists it. And every gate README's table names runs in the local checks
(checks/python_suites.yaml). See
docs/package-fidelity/README.md.

    python tools/check_package_status.py
"""
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from src import package_eval as pe, package_fidelity as pf  # noqa: E402


def _tracks(pkg: str) -> set:
    phil = yaml.safe_load((ROOT / 'data/packages' / pkg / 'philosophy.yaml').read_text())
    return {t['id'] for t in phil.get('tracks') or []}


def gate_problems() -> list[str]:
    """Every command README's gate table names runs in the local checks."""
    from src.package_fidelity import _workflow
    readme = (ROOT / 'docs/package-fidelity/README.md').read_text()
    workflow = _workflow()
    section = readme.split('## The gates', 1)[1].split('\n## ', 1)[0]
    out = []
    for line in section.splitlines():
        m = re.match(r'^\|\s*`([^`]+\.py[^`]*)`', line)
        if m and f'python {m.group(1)}' not in workflow:
            out.append(f'README gate `{m.group(1)}` is not in checks/python_suites.yaml')
    return out


def problems() -> list[str]:
    packages = sorted(p.name for p in (ROOT / 'data/packages').iterdir() if (p / 'philosophy.yaml').exists())
    scorecard = json.loads((ROOT / 'tools/scorecard_baseline.json').read_text())
    grades: dict = defaultdict(lambda: defaultdict(dict))
    for key, grade in scorecard.items():
        where, criterion = key.split('|')
        pkg, track = where.split('/')
        grades[pkg][track][criterion] = (grade, '')
    out = gate_problems()
    entries = {}
    for pkg in packages:
        record = pf.load(pkg)
        tracks = _tracks(pkg)
        for field in ('currency', 'excluded_tracks'):
            for tid in sorted(set((record or {}).get(field) or {}) - tracks):
                out.append(f'{pkg}: {field} names {tid}, which is not one of its tracks')
        weeks_file = ROOT / 'data/packages' / pkg / 'source_weeks.yaml'
        for entry in (yaml.safe_load(weeks_file.read_text()) or []) if weeks_file.exists() else []:
            if entry.get('track') not in tracks:
                out.append(f"{pkg}: source week {entry.get('id')} names {entry.get('track')}, "
                           'which is not one of its tracks')
        if not grades.get(pkg):
            out.append(f'{pkg}: no grades in tools/scorecard_baseline.json (run tools/evaluate_packages.py --update-baseline)')
            continue
        has_dossier = record is not None and pf.dossier(pkg) is not None
        earned = pe.derived_status(grades[pkg], set((record or {}).get('excluded_tracks') or {}), has_dossier)
        entries[pkg] = pf.status_entry(pkg, record, earned)
    if (ROOT / 'docs/package-fidelity/status.yaml').read_text() != pf.status_document(entries):
        out.append('docs/package-fidelity/status.yaml is not what the records and the recorded scorecard write '
                   '(run tools/evaluate_packages.py --update-baseline)')
    return out


if __name__ == '__main__':
    found = problems()
    for line in found:
        print('  -', line)
    if found:
        sys.exit(1)
    print('Package records and status.yaml match the repository.')
