#!/usr/bin/env python
"""tools/model_map.json and GET /api/dev/model-map (docs/roadmap.md 20.11):
how the model's parts act on each other, as data the code holds to.

Every interaction names the code that carries it (`anchors`, path::text) and
each must still be there — a function renamed or removed without the map
changing fails here. Every engine a track can run on has its interaction, the
map reaches from the philosophy to the load, and the usage it reports is the
generator's own reading of each track. The web's recording
(frontend/src/mocks/fixtures/model-map.json, which the Dev Lab panel's test
and the offline mock render) keeps the report's shape; `--write` re-records it.

Run: SUPABASE_URL='' .venv/bin/python test_model_map.py [--write]
"""
from __future__ import annotations

import json
import os
import sys

os.environ.setdefault('SUPABASE_URL', '')
os.environ.setdefault('DATABASE_URL', '')
os.environ.pop('TRAINING_PACKAGES_DIR', None)

ROOT = os.path.dirname(os.path.abspath(__file__))
RECORDING = os.path.join(ROOT, 'frontend', 'src', 'mocks', 'fixtures', 'model-map.json')

from src import loader, model_map, portability  # noqa: E402

FAILURES: list[str] = []


def check(label: str, condition: bool, detail='') -> None:
    if condition:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label} {detail}")
        FAILURES.append(label)


def test_document():
    print('the map, against the code')
    doc = model_map.document()
    nodes = {n['id'] for n in doc['nodes']}
    edges = doc['edges']
    check('every anchor is still in the code (or the interaction changed — update the map)',
          not model_map.missing_anchors(doc), model_map.missing_anchors(doc))
    check('every interaction is anchored', all(e.get('anchors') for e in edges),
          [e['id'] for e in edges if not e.get('anchors')])
    check('ids unique', len({e['id'] for e in edges}) == len(edges) and len(nodes) == len(doc['nodes']))
    check('every interaction joins two parts of the map', all(e['from'] in nodes and e['to'] in nodes for e in edges),
          [(e['id'], e['from'], e['to']) for e in edges if e['from'] not in nodes or e['to'] not in nodes])
    check('each says what it reads and what the engine decides',
          all(e['reads_from_source'] and e['engine_decides'] and e['function'] and e['files'] for e in edges),
          [e['id'] for e in edges if not (e['reads_from_source'] and e['engine_decides'])])
    engines = set(doc['engines'])
    check('an interaction\'s engine is one the map names', all(e['engine'] in engines | {None} for e in edges))
    check('every engine a track can run on has its interaction',
          {'training_contract', 'week_templates', 'scheduler', 'composition'} <= {e['engine'] for e in edges})

    def reach(start: str) -> set:
        seen, queue = {start}, [start]
        while queue:
            here = queue.pop()
            for e in edges:
                if e['from'] == here and e['to'] not in seen:
                    seen.add(e['to'])
                    queue.append(e['to'])
        return seen
    check('the map reaches from the philosophy to the load by every engine',
          {'phase', 'contract', 'template', 'scheduler', 'session', 'exercise', 'load'} <= reach('philosophy'),
          sorted(reach('philosophy')))
    check('a date it was checked', bool(doc.get('checked')))
    statuses = {'yes', 'partial', 'no', 'n/a'}
    check('the authoring table says what can be written where',
          all({a['create'], a['edit'], a['remove']} <= statuses and a['type'] and a['notes'] for a in doc['authoring']))


def test_usage():
    print('which engine each track runs on')
    usage = model_map.usage()
    report = portability.report()
    tracks = sum(len(p['tracks']) for p in report['packages'])
    check('every shipped track is counted once', sum(u['tracks'] for u in usage.values()) == tracks, usage)
    check('no shipped package runs on the scheduler', usage['scheduler'] == {'tracks': 0, 'packages': []}, usage['scheduler'])
    check('contracts and templates between them carry every package',
          set(usage['training_contract']['packages']) | set(usage['week_templates']['packages'])
          == {p['id'] for p in report['packages']})
    import shutil
    import tempfile
    overlay = tempfile.mkdtemp(prefix='model-map-')
    try:
        shutil.copytree(os.path.join(ROOT, 'test_packages', 'scratch_minimal'), os.path.join(overlay, 'scratch_minimal'))
        with loader.overlay(overlay):
            mine = model_map.usage()
        check("a caller's own package is counted in their view", mine['scheduler'] == {'tracks': 1, 'packages': ['scratch_minimal']},
              mine['scheduler'])
    finally:
        shutil.rmtree(overlay, ignore_errors=True)


def _shape(node):
    if isinstance(node, dict):
        return {k: _shape(v) for k, v in sorted(node.items())}
    if isinstance(node, list):
        return [_shape(node[0])] if node else []
    return type(node).__name__ if node is not None else None


def test_recording(write: bool):
    print('the web recording')
    report = model_map.report()
    if write:
        with open(RECORDING, 'w', encoding='utf-8') as fh:
            json.dump(report, fh, indent=1, ensure_ascii=False)
            fh.write('\n')
    with open(RECORDING, encoding='utf-8') as fh:
        recorded = json.load(fh)
    check("recorded with the report's shape (re-record: test_model_map.py --write)", _shape(recorded) == _shape(report))
    check('recorded with the current map (re-record: test_model_map.py --write)',
          recorded['edges'] == report['edges'] and recorded['nodes'] == report['nodes']
          and recorded['authoring'] == report['authoring'])


def test_route():
    print('the route')
    import api
    res = api.app.test_client().get('/api/dev/model-map')
    body = res.get_json()
    check('200, the map and the usage', res.status_code == 200 and body['edges'] and body['usage']
          and body['nodes'] and body['authoring'], res.status_code)


def main() -> int:
    test_document()
    test_usage()
    test_recording('--write' in sys.argv)
    test_route()
    if FAILURES:
        print(f'{len(FAILURES)} failed')
        return 1
    print('all passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
