"""A package's records, in its own folder.

The push gates keep a record per package: its scorecard grades, the fidelity
findings it is allowed, the catalog exercises no program reaches, its golden
program hashes and its status — and the dossier beside them. They lived outside
the folder (tools/scorecard_baseline.json, tools/fidelity_baseline.json,
tools/exercise_coverage_baseline.json, test_single_lane_golden.json,
docs/package-fidelity/status.yaml and <id>.md), so a new package was a change
to six shared files. Now they are the package's:

    data/packages/<id>/records/scorecard.json   track|criterion -> grade
    data/packages/<id>/records/fidelity.json    [track|profile|finding]
    data/packages/<id>/records/coverage.json    [orphaned exercise ids]
    data/packages/<id>/records/golden.json      track/level/profile (or extra:<case>) -> hash
    data/packages/<id>/records/status.yaml      the package's status entry
    data/packages/<id>/dossier.md               the record in prose

Keys never name the package, so a copied or renamed package needs no rewrite.
The gates read them through the `all_*` functions, which put the package back
in front (`pkg/track|criterion`) as the comparisons always had them. Nothing at
runtime reads them; the API image leaves them out (.dockerignore).
"""
from __future__ import annotations

import json
import os

import yaml

from src import loader

RECORDS = 'records'
DOSSIER = 'dossier.md'


def packages() -> list[str]:
    """Every package folder the loader reads."""
    root = loader._PACKAGES_DIR
    return sorted(p for p in os.listdir(root) if os.path.isfile(os.path.join(root, p, 'philosophy.yaml')))


def path(pkg: str, name: str) -> str:
    return os.path.join(loader._PACKAGES_DIR, pkg, RECORDS, name)


def dossier_path(pkg: str) -> str:
    return os.path.join(loader._PACKAGES_DIR, pkg, DOSSIER)


def _read(pkg: str, name: str, default):
    p = path(pkg, name)
    if not os.path.exists(p):
        return default
    with open(p, encoding='utf-8') as fh:
        return (yaml.safe_load(fh) if name.endswith('.yaml') else json.load(fh)) or default


def _write_json(pkg: str, name: str, data) -> None:
    p = path(pkg, name)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, 'w', encoding='utf-8') as fh:
        json.dump(data, fh, indent=1, sort_keys=isinstance(data, dict), ensure_ascii=False)
        fh.write('\n')


def has(pkg: str, name: str) -> bool:
    return os.path.exists(path(pkg, name))


# ── Scorecard grades ─────────────────────────────────────────────────────────

def grades(pkg: str) -> dict:
    return _read(pkg, 'scorecard.json', {})


def write_grades(pkg: str, rows: dict) -> None:
    _write_json(pkg, 'scorecard.json', dict(sorted(rows.items())))


def all_grades(only: list[str] | None = None) -> dict:
    """`pkg/track|criterion` -> grade, every package's (or `only` these)."""
    return {f'{pkg}/{k}': v for pkg in (only or packages()) for k, v in grades(pkg).items()}


# ── Fidelity findings ────────────────────────────────────────────────────────

def findings(pkg: str) -> list[str]:
    return list(_read(pkg, 'fidelity.json', []))


def write_findings(pkg: str, keys: list[str]) -> None:
    _write_json(pkg, 'fidelity.json', sorted(set(keys)))


def all_findings(only: list[str] | None = None) -> list[str]:
    """`pkg/track|profile|finding`, every package's (or `only` these)."""
    return sorted(f'{pkg}/{k}' for pkg in (only or packages()) for k in findings(pkg))


# ── Exercise coverage ────────────────────────────────────────────────────────

def orphans(pkg: str) -> list[str]:
    return list(_read(pkg, 'coverage.json', []))


def write_orphans(pkg: str, ids: list[str]) -> None:
    _write_json(pkg, 'coverage.json', sorted(set(ids)))


def all_orphans(only: list[str] | None = None) -> dict:
    """package -> orphaned exercise ids, for every package that has a record."""
    return {pkg: orphans(pkg) for pkg in (only or packages()) if has(pkg, 'coverage.json')}


# ── Golden program hashes ────────────────────────────────────────────────────

def golden(pkg: str) -> dict:
    return _read(pkg, 'golden.json', {})


def write_golden(pkg: str, hashes: dict) -> None:
    _write_json(pkg, 'golden.json', dict(sorted(hashes.items())))


def golden_name(pkg: str, key: str) -> str:
    """A package's golden key as the test names its case: `pkg/track/level/profile`,
    or `extra/<case>` for one of the stateful extras (stored as `extra:<case>`)."""
    return f"extra/{key[len('extra:'):]}" if key.startswith('extra:') else f'{pkg}/{key}'


def golden_key(name: str) -> str:
    """The inverse: the key a case is stored under in its package's record."""
    return f"extra:{name[len('extra/'):]}" if name.startswith('extra/') else name.split('/', 1)[1]


def all_golden() -> dict:
    return {golden_name(pkg, k): v for pkg in packages() for k, v in golden(pkg).items()}


# ── Status ───────────────────────────────────────────────────────────────────

def status(pkg: str) -> dict | None:
    return _read(pkg, 'status.yaml', None)


def status_text(pkg: str, entry: dict) -> str:
    """The status entry as its file holds it — generated, never edited."""
    return ('# GENERATED by tools/evaluate_packages.py --update-baseline from this package\'s\n'
            '# fidelity.yaml and its recorded scorecard — do not edit (docs/package-fidelity/README.md).\n'
            + yaml.safe_dump(entry, sort_keys=False, allow_unicode=True, width=100))


def write_status(pkg: str, entry: dict) -> None:
    p = path(pkg, 'status.yaml')
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, 'w', encoding='utf-8') as fh:
        fh.write(status_text(pkg, entry))


def status_current(pkg: str, entry: dict) -> bool:
    p = path(pkg, 'status.yaml')
    return os.path.exists(p) and open(p, encoding='utf-8').read() == status_text(pkg, entry)
