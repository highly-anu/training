"""How the model's parts act on each other, as data: tools/model_map.json.

Dev Lab ▸ Model Interactions used to carry this as constants in a component,
describing the modality scheduler's path as the pipeline — the path no shipped
package takes — and nothing checked it against the code. It is data now: each
interaction names the code that carries it (`anchors`, path::text), and
test_model_map.py fails when one is gone. With it ride, computed here, which
engine each shipped track runs on, so the map says how much each path is used.
"""
from __future__ import annotations

import json
import os

from . import portability

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(ROOT, 'tools', 'model_map.json')
_SHAPE_ENGINE = {'contract': 'training_contract', 'templates': 'week_templates', 'scheduler': 'scheduler'}


def document() -> dict:
    with open(PATH, encoding='utf-8') as fh:
        return json.load(fh)


def missing_anchors(doc: dict | None = None) -> list[str]:
    """Every anchor whose text is no longer in its file."""
    out = []
    for edge in (doc or document())['edges']:
        for anchor in edge.get('anchors') or []:
            path, _, text = anchor.partition('::')
            full = os.path.join(ROOT, path)
            if not (text and os.path.exists(full) and text in open(full, encoding='utf-8').read()):
                out.append(f"{edge['id']}: {anchor}")
    return out


def usage() -> dict:
    """{engine: {'tracks': n, 'packages': [ids]}} over the packages the caller
    sees: which engine each track runs on (portability's reading, the
    generator's own)."""
    out: dict = {engine: {'tracks': 0, 'packages': []} for engine in _SHAPE_ENGINE.values()}
    for pkg in portability.report()['packages']:
        for track in pkg['tracks']:
            engine = _SHAPE_ENGINE.get(track['shape'])
            if engine:
                out[engine]['tracks'] += 1
                if pkg['id'] not in out[engine]['packages']:
                    out[engine]['packages'].append(pkg['id'])
    return out


def report() -> dict:
    doc = document()
    return {'checked': doc['checked'], 'engines': doc['engines'], 'nodes': doc['nodes'], 'edges': doc['edges'],
            'authoring': doc['authoring'], 'usage': usage()}
