"""docs/package-fidelity/status.yaml against the repository.

Every package is listed (and nothing that is not a package). A dossier or
source test that is named exists; `sources_kind` is one of the kinds; the
tracks `currency` and `excluded_tracks` name are the package's own. And the
declared `status` is the one the recorded scorecard earns
(tools/scorecard_baseline.json, written by tools/evaluate_packages.py):
`audited` when every criterion but hygiene passes on every track not excluded,
`partial` once a dossier exists, else `not_started` — so "audited" cannot
outlive the grades that earned it. See docs/package-fidelity/README.md.

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
from src import package_eval as pe  # noqa: E402

STATUSES = {'audited', 'partial', 'not_started'}
SHAPES = {'contract', 'templates', 'scheduler'}
SOURCE_KINDS = {'primary', 'consensus', 'secondary'}


def _tracks(pkg: str) -> set:
    phil = yaml.safe_load((ROOT / 'data/packages' / pkg / 'philosophy.yaml').read_text())
    return {t['id'] for t in phil.get('tracks') or []}


def gate_problems() -> list[str]:
    """Every command README's gate table names runs in the CI workflow."""
    readme = (ROOT / 'docs/package-fidelity/README.md').read_text()
    workflow = (ROOT / '.github/workflows/training-contract.yml').read_text()
    section = readme.split('## The gates', 1)[1].split('\n## ', 1)[0]
    out = []
    for line in section.splitlines():
        m = re.match(r'^\|\s*`([^`]+\.py[^`]*)`', line)
        if m and f'python {m.group(1)}' not in workflow:
            out.append(f'README gate `{m.group(1)}` does not run in .github/workflows/training-contract.yml')
    return out


def problems() -> list[str]:
    status = yaml.safe_load((ROOT / 'docs/package-fidelity/status.yaml').read_text())['packages']
    packages = {p.name for p in (ROOT / 'data/packages').iterdir() if (p / 'philosophy.yaml').exists()}
    scorecard = json.loads((ROOT / 'tools/scorecard_baseline.json').read_text())
    grades: dict = defaultdict(lambda: defaultdict(dict))
    for key, grade in scorecard.items():
        where, criterion = key.split('|')
        pkg, track = where.split('/')
        grades[pkg][track][criterion] = (grade, '')
    out = gate_problems()
    for pkg in sorted(packages - status.keys()):
        out.append(f'{pkg}: not listed')
    for pkg in sorted(status.keys() - packages):
        out.append(f'{pkg}: listed, but no such package')
    for pkg, entry in sorted(status.items()):
        if pkg not in packages:
            continue
        if entry.get('status') not in STATUSES:
            out.append(f"{pkg}: status {entry.get('status')!r} is not one of {sorted(STATUSES)}")
        if entry.get('shape') not in SHAPES:
            out.append(f"{pkg}: shape {entry.get('shape')!r} is not one of {sorted(SHAPES)}")
        if entry.get('sources_kind') and entry['sources_kind'] not in SOURCE_KINDS:
            out.append(f"{pkg}: sources_kind {entry['sources_kind']!r} is not one of {sorted(SOURCE_KINDS)}")
        tracks = _tracks(pkg)
        for field in ('currency', 'excluded_tracks'):
            for tid in sorted(set(entry.get(field) or {}) - tracks):
                out.append(f'{pkg}: {field} names {tid}, which is not one of its tracks')
        has_dossier = bool(entry.get('dossier')) and (ROOT / entry['dossier']).exists()
        if entry.get('dossier') and not has_dossier:
            out.append(f"{pkg}: dossier {entry['dossier']} does not exist")
        for ref in entry.get('source_tests') or []:
            file, _, name = ref.partition('::')
            path = ROOT / file
            if not path.exists():
                out.append(f'{pkg}: source test file {file} does not exist')
                continue
            if name and f'def {name}(' not in path.read_text():
                out.append(f'{pkg}: {file} has no test {name}')
        if not grades.get(pkg):
            out.append(f'{pkg}: no grades in tools/scorecard_baseline.json (run tools/evaluate_packages.py --update-baseline)')
            continue
        earned = pe.derived_status(grades[pkg], set(entry.get('excluded_tracks') or {}), has_dossier)
        if entry.get('status') != earned:
            out.append(f"{pkg}: status.yaml says {entry.get('status')}, the recorded scorecard earns {earned}")
    return out


if __name__ == '__main__':
    found = problems()
    for line in found:
        print('  -', line)
    if found:
        sys.exit(1)
    print('Package status matches the repository.')
