#!/usr/bin/env python
"""The clients' modality and phase-kind tables come from the commons.

tools/gen_client_vocab.py writes the web's (frontend/src/lib/gen/clientVocab.ts)
and the Apple targets' (ClientVocab.swift in each target folder) from each
modality's and phase kind's `display` block. This fails when a generated file
is stale, when a modality or kind has no display, and when a hand-written
client table names a modality again instead of reading the generated one.

    .venv/bin/python test_client_vocab.py
"""
from __future__ import annotations

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import gen_client_vocab as gen  # noqa: E402

FAILURES: list[str] = []


def check(label: str, condition: bool, detail='') -> None:
    if condition:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label} {detail}")
        FAILURES.append(label)


def main() -> int:
    print('the generated tables')
    done = subprocess.run([sys.executable, os.path.join(ROOT, 'tools', 'gen_client_vocab.py'), '--check'],
                          capture_output=True, text=True)
    check('every generated file is current (python3 tools/gen_client_vocab.py)', done.returncode == 0,
          done.stdout)
    modalities, phases = gen.load()
    check('every modality has its display', len(modalities) == len(os.listdir(os.path.join(gen.COMMONS, 'modalities'))))
    for kind, d in phases:
        check(f'phase kind {kind}: label, colour, tint, shade',
              bool(d.get('label')) and re.fullmatch(r'#[0-9a-f]{6}', d.get('color') or '') is not None
              and bool(re.fullmatch(r'[a-z]+', d.get('tint') or '')) and d.get('text_shade') in (700, 800), d)
    copies = {open(p, encoding='utf-8').read() for p in gen.SWIFT_OUT}
    check('the four Apple targets carry one table', len(copies) == 1)

    print('no client names a modality table again')
    ids = [i for i, _ in modalities]
    pattern = re.compile(r'"(' + '|'.join(ids) + r')"\s*:\s*return\s+(Color\(|"[^"]+")')
    offenders = []
    for folder in ('ios/TrainingCompanion', 'ios/TrainingWidgets', 'ios/TrainingCompanionWatch Watch App',
                   'ios/TrainingWatchWidgets'):
        for dirpath, _, files in os.walk(os.path.join(ROOT, folder)):
            for name in files:
                if name.endswith('.swift') and name != 'ClientVocab.swift':
                    text = open(os.path.join(dirpath, name), encoding='utf-8').read()
                    if pattern.search(text):
                        offenders.append(os.path.relpath(os.path.join(dirpath, name), ROOT))
    check("no Swift switch maps a modality to a colour or a label", not offenders, offenders)
    web = os.path.join(ROOT, 'frontend', 'src')
    listed = []
    for dirpath, _, files in os.walk(web):
        if '/gen' in dirpath or '/mocks' in dirpath:
            continue
        for name in files:
            if name.endswith(('.ts', '.tsx')) and not name.endswith(('.test.ts', '.test.tsx')):
                text = open(os.path.join(dirpath, name), encoding='utf-8').read()
                if sum(f"'{i}'" in text for i in ids) == len(ids):
                    listed.append(os.path.relpath(os.path.join(dirpath, name), ROOT))
    check('no web file lists every modality by hand', not listed, listed)
    if FAILURES:
        print(f'{len(FAILURES)} failed')
        return 1
    print('all passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
