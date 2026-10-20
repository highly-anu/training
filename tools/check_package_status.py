"""docs/package-fidelity/status.yaml against the repository.

Every package is listed (and nothing that is not a package). A dossier or
source test that is named exists. An `audited` package also has a dossier,
at least one source test that CI runs (.github/workflows/training-contract.yml),
no finding in tools/fidelity_baseline.json and no orphan in
tools/exercise_coverage_baseline.json — so "audited" cannot outlive the state
that earned it. See docs/package-fidelity/README.md.

    python tools/check_package_status.py
"""
import json
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
STATUSES = {'audited', 'partial', 'not_started'}
SHAPES = {'contract', 'templates', 'scheduler'}


def problems() -> list[str]:
    status = yaml.safe_load((ROOT / 'docs/package-fidelity/status.yaml').read_text())['packages']
    packages = {p.name for p in (ROOT / 'data/packages').iterdir() if (p / 'philosophy.yaml').exists()}
    workflow = (ROOT / '.github/workflows/training-contract.yml').read_text()
    fidelity = json.loads((ROOT / 'tools/fidelity_baseline.json').read_text())
    fidelity_items = fidelity if isinstance(fidelity, list) else list(fidelity)
    orphans = json.loads((ROOT / 'tools/exercise_coverage_baseline.json').read_text())
    out = []
    for pkg in sorted(packages - status.keys()):
        out.append(f'{pkg}: not listed')
    for pkg in sorted(status.keys() - packages):
        out.append(f'{pkg}: listed, but no such package')
    for pkg, entry in sorted(status.items()):
        if entry.get('status') not in STATUSES:
            out.append(f"{pkg}: status {entry.get('status')!r} is not one of {sorted(STATUSES)}")
        if entry.get('shape') not in SHAPES:
            out.append(f"{pkg}: shape {entry.get('shape')!r} is not one of {sorted(SHAPES)}")
        if entry.get('dossier') and not (ROOT / entry['dossier']).exists():
            out.append(f"{pkg}: dossier {entry['dossier']} does not exist")
        run_in_ci = False
        for ref in entry.get('source_tests') or []:
            file, _, name = ref.partition('::')
            path = ROOT / file
            if not path.exists():
                out.append(f'{pkg}: source test file {file} does not exist')
                continue
            if name and f'def {name}(' not in path.read_text():
                out.append(f'{pkg}: {file} has no test {name}')
            run_in_ci |= f'python {file}' in workflow
        if entry.get('status') != 'audited':
            continue
        if not entry.get('dossier'):
            out.append(f'{pkg}: audited without a dossier')
        if not run_in_ci:
            out.append(f'{pkg}: audited, but CI runs none of its source tests')
        findings = [f for f in fidelity_items if str(f).startswith(pkg + '/')]
        if findings:
            out.append(f'{pkg}: audited with {len(findings)} fidelity finding(s) in the baseline')
        if orphans.get(pkg):
            out.append(f'{pkg}: audited with orphaned exercises {orphans[pkg]}')
    return out


if __name__ == '__main__':
    found = problems()
    for line in found:
        print('  -', line)
    if found:
        sys.exit(1)
    print('Package status matches the repository.')
