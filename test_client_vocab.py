#!/usr/bin/env python
"""The clients' vocabulary tables come from the commons.

tools/gen_client_vocab.py writes the web's (frontend/src/lib/gen/clientVocab.ts)
and the Apple targets' (ClientVocab.swift in each target folder) from each
modality's and phase kind's `display` block, the equipment list and the
slot-type outcome table, and rewrites the four schemas' equipment enums from
the list. This fails when a generated file is stale, when a modality or kind
has no display, when a hand-written client table comes back, and when the
server does not read a stored alias as its equipment id.

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

    print('equipment and outcomes')
    sys.path.insert(0, ROOT)
    os.environ.setdefault('SUPABASE_URL', '')
    os.environ.setdefault('DATABASE_URL', '')
    from src import equipment
    check('an alias reads as its id, each once, an unknown id kept',
          equipment.canonical(['assault_bike', 'bike', 'rower', 'dip_bar']) == ['bike', 'rower', 'dip_bar'])
    import json
    for name, _, with_none in gen.SCHEMA_ENUMS:
        schema = json.load(open(os.path.join(ROOT, 'docs', 'schemas', f'{name}.schema.json'), encoding='utf-8'))
        prop = (schema['properties'].get('required_equipment') or schema['properties']['equipment'])
        want = equipment.ids() + (['none'] if with_none else [])
        check(f'{name}.schema.json enumerates the one list', prop['items']['enum'] == want)
    stale_copies = []
    for rel, needle in (('ios/TrainingCompanion/AppModels.swift', 'EquipmentItem(id: "barbell"'),
                        ('ios/TrainingCompanion/SessionLogging.swift', 'fieldsFor: [String'),
                        ('frontend/src/lib/outcomeFields.ts', 'const FIELDS_FOR'),
                        ('frontend/src/lib/equipment.ts', "{ id: 'barbell'"),
                        ('frontend/src/components/builder/ConstraintsForm.tsx', 'const EQUIPMENT_CATEGORIES'),
                        ('src/loader.py', "'pull_up_bar', 'rings'")):
        if needle in open(os.path.join(ROOT, rel), encoding='utf-8').read():
            stale_copies.append(rel)
    check('no client keeps its own equipment or outcome table', not stale_copies, stale_copies)

    import api
    from unittest.mock import patch
    client = api.app.test_client()
    with patch('src.db.get_user_program', return_value=None), patch('src.db.save_user_program'):
        r = client.post('/api/sessions/generate', json={
            'modality': 'aerobic_base', 'phase': 'base', 'week_number': 1,
            'constraints': {'equipment': ['assault_bike'], 'session_time_minutes': 60,
                            'training_level': 'intermediate', 'injury_flags': []}})
    check('a session for a stored assault_bike is generated against the bike',
          r.status_code == 200, (r.status_code, str(r.get_json())[:200]))
    profile = api._sanitize_profile({'equipment': ['assault_bike', 'rower']})
    check('the profile reads back the id the engine knows', profile['equipment'] == ['bike', 'rower'],
          profile['equipment'])
    if FAILURES:
        print(f'{len(FAILURES)} failed')
        return 1
    print('all passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
