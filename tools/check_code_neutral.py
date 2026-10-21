#!/usr/bin/env python
"""No code names a package: a new package needs no code change.

garmin/tools/check_core_neutral.py holds the watch's core to this; this holds
the rest — the server (src/, api.py), the web (frontend/src), the iOS and
Apple Watch apps (ios/) and the Garmin core — to it as well. It reads the
string literals of each file, never its comments or docstrings (prose may name
a method; a branch may not), and flags one that is

- an id only one package owns: the package id, its frameworks, archetypes,
  tracks and phases (ids with an underscore, so `strength` stays a word), and
  the exercises no other package's catalog has; or
- a prefix of two or more parts ending in `_` that three or more of one
  package's ids, and none of another's, start with (`wk_kb_`: stripping
  Wildman's prefix is knowing it).

An id the commons also define (a modality, a phase kind, a movement pattern,
equipment, an injury flag, a standard or The Cell's keys, a value a schema
enumerates — `rpe_autoregulation` is a progression model before it is Marcus
Filly's framework) is shared vocabulary, not a package's. Tests, mocks and
fixtures are out of scope; so are regular-expression literals, which it does
not parse.

Any literal it finds fails: there is no baseline, because on 2026-10-21 the
last ones went (the scheduler's BJJ mobility branch and Kelly Starrett's
archetype ids, the selector's level concepts, the tracker's family copy, the
`gym_jones` exercise category, the builders' `wk_kb_` stripping). The
scorecard's X1 is this, per package (tools/evaluate_packages.py).

    .venv/bin/python tools/check_code_neutral.py [-v]
"""
from __future__ import annotations

import ast
import glob
import json
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

import yaml  # noqa: E402

SCOPES = (
    ('src/**/*.py', 'py'), ('api.py', 'py'), ('mcp_server.py', 'py'),
    ('frontend/src/**/*.ts', 'c'), ('frontend/src/**/*.tsx', 'c'),
    ('ios/TrainingCompanion/**/*.swift', 'c'), ('ios/Shared/**/*.swift', 'c'),
    ('ios/TrainingCompanionWatch Watch App/**/*.swift', 'c'),
    ('ios/TrainingWidgets/**/*.swift', 'c'), ('ios/TrainingWatchWidgets/**/*.swift', 'c'),
    ('garmin/core/source/**/*.mc', 'c'),
)
OUT_OF_SCOPE = re.compile(r'(\.test\.tsx?$|/mocks/|/fixtures/|/__tests__/|Tests?/|/test/)')
PREFIX_MIN = 3


# ── What each package owns ───────────────────────────────────────────────────

def _yaml(path: str):
    with open(path, encoding='utf-8') as fh:
        return yaml.safe_load(fh)


def _commons() -> set:
    """Vocabulary the commons define: no package owns it."""
    out = set()
    commons = os.path.join(ROOT, 'data', 'commons')
    for path in glob.glob(os.path.join(commons, 'modalities', '*.yaml')):
        out.add((_yaml(path) or {}).get('id'))
    for name in ('phase_kinds.yaml', 'movement_patterns.yaml'):
        doc = _yaml(os.path.join(commons, name)) or {}
        out |= set(doc) if isinstance(doc, dict) else set()
        for v in (doc.values() if isinstance(doc, dict) else []):
            if isinstance(v, dict):
                out |= set(v)
    profiles = _yaml(os.path.join(commons, 'constraints', 'equipment_profiles.yaml')) or []
    for p in profiles if isinstance(profiles, list) else profiles.get('profiles', []):
        out |= set(p.get('equipment') or []) | {p.get('id')}
    flags = _yaml(os.path.join(commons, 'constraints', 'injury_flags.yaml')) or []
    out |= {f.get('id') for f in (flags if isinstance(flags, list) else flags.get('injury_flags', []))}
    for path in glob.glob(os.path.join(ROOT, 'data', 'benchmarks', '*.yaml')):
        out |= _words(_yaml(path))   # standards, and The Cell's own test keys
    for path in glob.glob(os.path.join(ROOT, 'docs', 'schemas', '*.json')):
        with open(path, encoding='utf-8') as fh:
            out |= _enums(json.load(fh))   # progression and intensity models …
    return {x for x in out if isinstance(x, str)}


def _words(node) -> set:
    """Every key and string value of a document."""
    if isinstance(node, dict):
        return set(node) | set().union(*(_words(v) for v in node.values()))
    if isinstance(node, list):
        return set().union(*(_words(v) for v in node)) if node else set()
    return {node} if isinstance(node, str) else set()


def _enums(node) -> set:
    """Every value a schema enumerates: the engine's own vocabulary."""
    if isinstance(node, dict):
        out = {v for v in node.get('enum') or [] if isinstance(v, str)}
        return out.union(*(_enums(v) for v in node.values())) if node else out
    if isinstance(node, list):
        return set().union(*(_enums(v) for v in node)) if node else set()
    return set()


def owned_ids() -> dict[str, dict[str, str]]:
    """package -> {id: what it is}, for ids only that package owns."""
    from src import loader
    packages = loader._PACKAGES_DIR   # TRAINING_PACKAGES_DIR, when a test drops packages in
    owned: dict = defaultdict(dict)
    exercises: dict = defaultdict(set)
    for pkg_dir in sorted(glob.glob(os.path.join(packages, '*'))):
        pkg = os.path.basename(pkg_dir)
        phil_path = os.path.join(pkg_dir, 'philosophy.yaml')
        if not os.path.exists(phil_path):
            continue
        owned[pkg][pkg] = 'package'
        phil = _yaml(phil_path) or {}
        for t in phil.get('tracks') or []:
            owned[pkg][t['id']] = 'track'
            for ph in t.get('phases') or []:
                owned[pkg][ph['id']] = 'phase'
        for path in glob.glob(os.path.join(pkg_dir, 'frameworks', '*.yaml')):
            owned[pkg][(_yaml(path) or {}).get('id') or ''] = 'framework'
        for path in glob.glob(os.path.join(pkg_dir, 'archetypes', '**', '*.yaml'), recursive=True):
            owned[pkg][(_yaml(path) or {}).get('id') or ''] = 'archetype'
        ex_path = os.path.join(pkg_dir, 'exercises.yaml')
        if os.path.exists(ex_path):
            doc = _yaml(ex_path) or {}
            for e in doc if isinstance(doc, list) else doc.get('exercises') or []:
                exercises[e['id']].add(pkg)
    for eid, pkgs in exercises.items():
        if len(pkgs) == 1:
            owned[next(iter(pkgs))].setdefault(eid, 'exercise')
    commons = _commons()
    shared = defaultdict(set)
    for pkg, ids in owned.items():
        for i in ids:
            shared[i].add(pkg)
    # A package id is never shared vocabulary, even where a schema enumerates
    # it (the exercise schema once listed `gym_jones` as a category).
    return {pkg: {i: k for i, k in ids.items()
                  if k == 'package' or (i and i not in commons and len(shared[i]) == 1 and '_' in i)}
            for pkg, ids in owned.items()}


def _prefixes(owned: dict) -> dict[str, str]:
    """`wk_kb_` -> wildman_kettlebell: a prefix of two or more parts that
    three or more of one package's ids, and none of another's, start with
    (one part, `sb_`, is as likely an API key's)."""
    by_prefix: dict = defaultdict(lambda: defaultdict(int))
    for pkg, ids in owned.items():
        for i in ids:
            parts = i.split('_')
            for n in range(2, len(parts)):
                by_prefix['_'.join(parts[:n]) + '_'][pkg] += 1
    return {p: next(iter(c)) for p, c in by_prefix.items() if len(c) == 1 and next(iter(c.values())) >= PREFIX_MIN}


# ── Literals ─────────────────────────────────────────────────────────────────

def _py_literals(text: str):
    try:
        tree = ast.parse(text)
    except SyntaxError:
        return
    docstrings = set()
    for node in ast.walk(tree):
        body = getattr(node, 'body', None)
        if isinstance(body, list) and body and isinstance(body[0], ast.Expr) \
                and isinstance(getattr(body[0], 'value', None), ast.Constant) and isinstance(body[0].value.value, str):
            docstrings.add(id(body[0].value))
    for node in ast.walk(tree):
        if isinstance(node, ast.Constant) and isinstance(node.value, str) and id(node) not in docstrings:
            yield node.lineno, node.value


_OPENER = {'}': '{', ')': '('}


def _c_literals(text: str) -> list[tuple[int, str]]:
    """String literals of a C-family file (TS, Swift, Monkey C), comments
    skipped. An interpolation — TS `${…}`, Swift `\\(…)` — is code, scanned
    for its own literals, never part of the string around it."""
    out: list = []
    _scan_code(text, 0, 1, out, None)
    return out


def _scan_code(text: str, i: int, line: int, out: list, stop: str | None) -> tuple[int, int]:
    """Code from `i` to the `stop` that closes an interpolation (or the end)."""
    n, depth = len(text), 0
    while i < n:
        c = text[i]
        if stop and c == stop and depth == 0:
            return i + 1, line
        if stop and c == _OPENER[stop]:
            depth += 1
        elif stop and c == stop:
            depth -= 1
        if c == '\n':
            line += 1
            i += 1
        elif text.startswith('//', i):
            j = text.find('\n', i)
            i = n if j < 0 else j
        elif text.startswith('/*', i):
            j = text.find('*/', i + 2)
            j = n if j < 0 else j + 2
            line += text.count('\n', i, j)
            i = j
        elif c in '"\'`':
            i, line = _scan_string(text, i, line, out, c)
        else:
            i += 1
    return i, line


def _scan_string(text: str, i: int, line: int, out: list, quote: str) -> tuple[int, int]:
    """A literal from its opening quote; each stretch between interpolations
    is a literal of its own."""
    n, j, buf, start = len(text), i + 1, [], line
    while j < n and text[j] != quote:
        interpolates = (quote == '`' and text.startswith('${', j)) or (quote == '"' and text.startswith('\\(', j))
        if interpolates:
            out.append((start, ''.join(buf)))
            buf, start = [], line
            j, line = _scan_code(text, j + 2, line, out, '}' if quote == '`' else ')')
            continue
        if text[j] == '\\' and j + 1 < n:
            buf.append(text[j + 1])
            j += 2
            continue
        if text[j] == '\n':
            if quote != '`':
                break   # an apostrophe in prose, not a literal: stop at the line
            line += 1
        buf.append(text[j])
        j += 1
    out.append((start, ''.join(buf)))
    return j + 1, line


def files() -> list[tuple[str, str]]:
    out = []
    for pattern, kind in SCOPES:
        for path in sorted(glob.glob(os.path.join(ROOT, pattern), recursive=True)):
            rel = os.path.relpath(path, ROOT)
            if not OUT_OF_SCOPE.search(rel) and '/build/' not in rel:
                out.append((rel, kind))
    return out


def scan() -> list[dict]:
    """Every literal in scope that names one package: {file, line, literal, package, what}."""
    owned = owned_ids()
    by_id = {i: (pkg, k) for pkg, ids in owned.items() for i, k in ids.items()}
    prefixes = _prefixes(owned)
    hits = []
    for rel, kind in files():
        with open(os.path.join(ROOT, rel), encoding='utf-8', errors='replace') as fh:
            text = fh.read()
        for line, lit in (_py_literals(text) if kind == 'py' else _c_literals(text)):
            if lit in by_id:
                pkg, what = by_id[lit]
            elif lit in prefixes:
                pkg, what = prefixes[lit], 'id prefix'
            else:
                continue
            hits.append({'file': rel, 'line': line, 'literal': lit, 'package': pkg, 'what': what})
    return hits


def by_package(hits: list[dict]) -> dict[str, list[str]]:
    out: dict = defaultdict(list)
    for h in hits:
        out[h['package']].append(f"{h['file']}:{h['line']} '{h['literal']}' ({h['what']})")
    return out


def main() -> int:
    hits = scan()
    for h in hits:
        print(f"  {h['file']}:{h['line']} names {h['package']} ('{h['literal']}', {h['what']})")
    if hits:
        print(f'{len(hits)} literal(s) name a package: move what they decide into the package\'s data')
        return 1
    if '-v' in sys.argv:
        owned = owned_ids()
        print(f"{sum(map(len, owned.values()))} package-owned ids over {len(files())} files")
    print('No code names a package.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
