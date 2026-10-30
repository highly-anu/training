#!/usr/bin/env python
"""src/portability.py and GET /api/dev/portability: what each package brings in
its folder, what it still needs outside it, and the gaps no package can close.

The gaps list (tools/portability_gaps.json) is checked against the code: every
anchor of a gap must still be in its file, so closing a gap without changing
its status here fails. Then the report runs on the shipped packages, on the
modality scheduler's fixture and on a copy of it that collides with it. The
web's recording of that report (frontend/src/mocks/fixtures/portability.json,
which the Dev Lab panel's test and the offline mock render) must keep its
shape; `--write` re-records it.

Run: SUPABASE_URL='' .venv/bin/python test_portability.py [--write]
"""
from __future__ import annotations

import atexit
import json
import os
import re
import shutil
import sys
import tempfile

os.environ.setdefault('SUPABASE_URL', '')

ROOT = os.path.dirname(os.path.abspath(__file__))
SHIPPED = sorted(n for n in os.listdir(os.path.join(ROOT, 'data', 'packages'))
                 if os.path.isdir(os.path.join(ROOT, 'data', 'packages', n)))
FIXTURE = 'block_fixture'
COPY = 'zz_collider'
RECORDING = os.path.join(ROOT, 'frontend', 'src', 'mocks', 'fixtures', 'portability.json')


def _stage() -> str:
    """The shipped packages, the fixture, and a copy of the fixture under a new
    id that keeps its archetype and framework ids and names a modality the
    commons do not define."""
    folder = tempfile.mkdtemp(prefix='packages-')
    atexit.register(shutil.rmtree, folder, True)
    for name in SHIPPED:
        shutil.copytree(os.path.join(ROOT, 'data', 'packages', name), os.path.join(folder, name))
    shutil.copytree(os.path.join(ROOT, 'test_packages', FIXTURE), os.path.join(folder, FIXTURE))
    copy = os.path.join(folder, COPY)
    shutil.copytree(os.path.join(ROOT, 'test_packages', FIXTURE), copy)
    path = os.path.join(copy, 'philosophy.yaml')
    with open(path, encoding='utf-8') as fh:
        text = fh.read()
    with open(path, 'w', encoding='utf-8') as fh:
        fh.write(re.sub(rf'^id: {FIXTURE}$', f'id: {COPY}', text, flags=re.M))
    with open(os.path.join(copy, 'archetypes', 'zz_unknown.yaml'), 'w', encoding='utf-8') as fh:
        fh.write('id: zz_unknown_modality\nname: Unknown modality\nmodality: not_a_modality\n'
                 'required_equipment: [not_an_implement]\nslots: []\n')
    os.environ['TRAINING_PACKAGES_DIR'] = folder
    return folder


_stage()

from src import portability  # noqa: E402

FAILURES: list[str] = []


def check(label: str, condition: bool, detail='') -> None:
    if condition:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label} {detail}")
        FAILURES.append(label)


KINDS = {'gate', 'tooling', 'commons', 'code', 'client', 'watch', 'docs'}
IMPACTS = {'blocks', 'degrades', 'cosmetic'}
STATUSES = {'open', 'by_design'}


def test_gaps():
    print('the gaps list, against the code')
    doc = portability.gaps()
    gaps = doc['gaps']
    check('a verdict', bool(doc.get('verdict')))
    check('ids unique', len({g['id'] for g in gaps}) == len(gaps))
    with open(os.path.join(ROOT, 'docs', 'roadmap.md'), encoding='utf-8') as fh:
        roadmap = fh.read()
    for g in gaps:
        check(f"{g['id']}: kind, impact, status", g.get('kind') in KINDS and g.get('impact') in IMPACTS
              and g.get('status') in STATUSES, g)
        check(f"{g['id']}: anchored", bool(g.get('anchors')))
        if g['status'] == 'open':
            check(f"{g['id']}: a roadmap step", bool(g.get('roadmap')) and f"**{g['roadmap']} " in roadmap,
                  g.get('roadmap'))
        for anchor in g.get('anchors') or []:
            path, _, text = anchor.partition('::')
            full = os.path.join(ROOT, path)
            found = os.path.exists(full) and text in open(full, encoding='utf-8').read()
            check(f"{g['id']}: {anchor} still there (or the gap is closed — update its status)", found)


def test_report():
    print('the report')
    report = portability.report()
    rows = {p['id']: p for p in report['packages']}
    check('every package folder', set(rows) == set(SHIPPED) | {FIXTURE, COPY}, sorted(rows))
    for name in SHIPPED:
        p = rows[name]
        check(f'{name} drops in as it stands', p['ready'],
              {'outside': [o['id'] for o in p['outside'] if not o['done']],
               'unknown': [v for v in p['vocabulary'] if v['unknown']], 'collisions': p['collisions']})
    fixture = rows[FIXTURE]
    check('the fixture runs on the scheduler', {t['shape'] for t in fixture['tracks']} == {'scheduler'},
          fixture['tracks'])
    check('the fixture has no record outside its folder', not any(o['done'] for o in fixture['outside']),
          fixture['outside'])
    check('so it is not ready', fixture['ready'] is False)
    check('each missing record says how', all(o['how'] for o in fixture['outside']))
    files = {f['id']: f['present'] for f in fixture['files']}
    check('its files', files['philosophy'] and files['archetypes'] and not files['contract'], files)

    copy = rows[COPY]
    unknown = {v['kind']: v['unknown'] for v in copy['vocabulary']}
    check('a modality the commons lack', unknown['modalities'] == ['not_a_modality'], unknown)
    check('equipment no athlete can name', unknown['equipment'] == ['not_an_implement'], unknown)
    check('the fixture names none', not any(v['unknown'] for v in fixture['vocabulary']), fixture['vocabulary'])

    kinds = {c['kind'] for c in report['collisions'] if set(c['packages']) == {FIXTURE, COPY}}
    check('the copy collides on archetypes and frameworks', {'archetype', 'framework'} <= kinds, kinds)
    check('and says which copy is kept', all(c['kept'] for c in report['collisions']))
    check('the two count their collisions', copy['collisions'] > 0 and fixture['collisions'] == copy['collisions'])
    check('shared exercises are counted, not flagged',
          report['sharedExercises'] > 0 and not any(c['kind'] == 'exercise' for c in report['collisions']))
    check('the gaps ride along', bool(report['gaps']) and bool(report['verdict']))


def _shape(node):
    """The keys of a document, the first item standing for every list."""
    if isinstance(node, dict):
        return {k: _shape(v) for k, v in sorted(node.items())}
    if isinstance(node, list):
        return [_shape(node[0])] if node else []
    return type(node).__name__ if node is not None else None


def test_recording(write: bool):
    print('the web recording')
    report = portability.report()
    report['packagesDir'] = 'data/packages'
    if write:
        with open(RECORDING, 'w', encoding='utf-8') as fh:
            json.dump(report, fh, indent=1, ensure_ascii=False)
            fh.write('\n')
    with open(RECORDING, encoding='utf-8') as fh:
        recorded = json.load(fh)
    check('recorded with the report\'s shape (re-record: test_portability.py --write)',
          _shape(recorded) == _shape(report))
    check('recorded with the current gaps (re-record: test_portability.py --write)',
          recorded['gaps'] == report['gaps'])


def test_route():
    print('the route')
    import api
    client = api.app.test_client()
    res = client.get('/api/dev/portability')
    body = res.get_json()
    check('200', res.status_code == 200, res.status_code)
    check('the report', {p['id'] for p in body['packages']} >= set(SHIPPED) and body['gaps'])
    check('it serialises', bool(json.dumps(body)))


def main() -> int:
    test_gaps()
    test_report()
    test_recording('--write' in sys.argv)
    test_route()
    if FAILURES:
        print(f'{len(FAILURES)} failed')
        return 1
    print('all passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
