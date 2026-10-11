#!/usr/bin/env python3
"""The watch's core names no philosophy.

The Monkey C counterpart of the rule for src/: a package's watch behaviour lives
in its data/packages/<id>/watch.yaml (or its module under garmin/packages/<id>/),
never in garmin/core. This fails on any package id or archetype id written in a
core source file -- code or comment, since a comment naming an archetype is
usually a branch that was moved out and left a note behind.

    .venv/bin/python garmin/tools/check_core_neutral.py
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, ROOT)

from src import loader  # noqa: E402

CORE = os.path.join(ROOT, 'garmin', 'core')


def forbidden_ids() -> set:
    ids = {p['id'] for p in loader.load_philosophies()}
    ids |= {a['id'] for a in loader.load_all_archetypes() if a.get('id')}
    return ids


def main() -> int:
    ids = forbidden_ids()
    pattern = re.compile(r'\b(' + '|'.join(sorted(map(re.escape, ids), key=len, reverse=True)) + r')\b')
    hits = []
    for path in sorted(glob.glob(os.path.join(CORE, '**', '*.mc'), recursive=True)):
        with open(path, encoding='utf-8') as f:
            for n, line in enumerate(f, 1):
                for m in pattern.finditer(line):
                    hits.append(f'{os.path.relpath(path, ROOT)}:{n}: {m.group(1)}')
    for h in hits:
        print(h)
    if hits:
        print(f'{len(hits)} package or archetype id(s) in garmin/core: move them to the package')
        return 1
    print(f'garmin/core names none of {len(ids)} package and archetype ids')
    return 0


if __name__ == '__main__':
    sys.exit(main())
