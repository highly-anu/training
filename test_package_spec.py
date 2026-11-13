#!/usr/bin/env python
"""The package spec (docs/roadmap.md 20.8): docs/schemas/PACKAGE_SPEC.md, the
one document that says how to write a package, and the ways it is handed out.

tools/gen_package_spec.py --check (a push gate of its own) holds its generated
blocks to the commons, the schemas and the gate. Here: it says what it must,
it is where the API image carries it, the server and the MCP tools serve it,
and the MCP server's skeleton package — what an agent starts from — passes
every gate and quotes no list of values that could go stale.

Run: SUPABASE_URL='' .venv/bin/python test_package_spec.py
"""
from __future__ import annotations

import atexit
import os
import shutil
import subprocess
import sys
import tempfile

os.environ.setdefault('SUPABASE_URL', '')
os.environ.setdefault('DATABASE_URL', '')
os.environ.pop('TRAINING_PACKAGES_DIR', None)

ROOT = os.path.dirname(os.path.abspath(__file__))

import yaml  # noqa: E402

import mcp_server  # noqa: E402
from src import equipment, loader, package_gate, package_spec, portability, recovery_regions  # noqa: E402

FAILURES: list[str] = []


def check(label: str, condition: bool, detail='') -> None:
    if condition:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label} {detail}")
        FAILURES.append(label)


def test_document():
    print('the document')
    text = package_spec.text()
    sections = package_spec.sections()
    check('nine numbered sections', [s['number'] for s in sections] == list(range(1, 10)),
          [s['number'] for s in sections])
    done = subprocess.run([sys.executable, os.path.join(ROOT, 'tools', 'gen_package_spec.py'), '--check'],
                          cwd=ROOT, capture_output=True, text=True)
    check('its generated blocks are current (tools/gen_package_spec.py)', done.returncode == 0, done.stdout[-200:])
    values = next(s['text'] for s in sections if s['number'] == 5)
    with loader.overlay(None):
        commons = [m for m, mod in loader.load_all_modalities().items() if not mod.get('_package')]
    check('every commons modality', all(f'`{m}`' in values for m in commons))
    check('every implement', all(f'`{e}`' in values for e in (i['id'] for i in equipment.commons_items())))
    regions = recovery_regions.config()
    check('every movement pattern, loading or not',
          all(f'`{p}`' in values for p in list(regions['patterns']) + list(regions.get('unloaded') or [])))
    check('every injury flag', all(f'`{f}`' in values for f in loader.load_injury_flags()))
    files = next(s['text'] for s in sections if s['number'] == 2)
    check('every file a package may hold', all(path in files for _id, path, _req in portability.FILES))
    gate = next(s['text'] for s in sections if s['number'] == 6)
    check('every stage of the gate', all(f'`{stage}`' in gate for stage in package_gate.STAGES))
    example = next(s['text'] for s in sections if s['number'] == 9)
    scratch = os.path.join(ROOT, 'test_packages', 'scratch_minimal')
    with open(os.path.join(scratch, 'vocabulary.yaml'), encoding='utf-8') as fh:
        check('the worked example is the from-scratch package, file for file', fh.read().rstrip('\n') in example)
    check('it says what stays the engine\'s', 'slot type' in text and 'phase kind' in text and 'watch template' in text)

    print('where it is')
    ignore = open(os.path.join(ROOT, '.dockerignore'), encoding='utf-8').read()
    check('in docs/schemas, the part of docs/ the API image carries',
          os.path.dirname(package_spec.PATH) == os.path.join(ROOT, 'docs', 'schemas') and '!docs/schemas' in ignore)
    check('and no ignore rule takes it out again', '**/*.md' not in ignore and 'docs/schemas/*.md' not in ignore)


def test_served():
    print('how it is handed out')
    import api
    from src import package_store
    client = api.app.test_client()
    body = client.get('/api/dev/package-spec').get_json()
    check('the server serves it whole and by section', body['spec'] == package_spec.text()
          and len(body['sections']) == 9)
    check("with the asker's id prefix and the limits", body['prefix'] == package_store.owner_prefix('local-dev-user')
          and body['limits']['files'] == package_store.MAX_FILES, {k: body.get(k) for k in ('prefix', 'limits')})
    check('the MCP server too, whole', mcp_server.get_package_spec() == package_spec.text())
    one = mcp_server.get_package_spec(5)
    check('or one section', one.startswith('## 5. Valid values') and '## 6.' not in one)
    check('and says so for a section there is not', 'No section 12' in mcp_server.get_package_spec(12))
    check('its value lists are the sets the checks use',
          set(mcp_server.list_valid_values('equipment')) == set(equipment.ids())
          and 'lumbar_disc' in mcp_server.list_valid_values('injury_flag')
          and set(mcp_server.list_valid_values('movement_pattern')) >= set(recovery_regions.config()['patterns']))


def test_skeleton():
    print("the MCP server's skeleton package")
    files = mcp_server.get_package_template('zz skeleton')
    text = '\n'.join(files.values())
    stale = [w for w in ('| rack |', 'hip_hinge | squat', 'max_strength | strength_endurance')
             if w in text]
    check('quotes no list of modalities, implements or patterns', not stale, stale)
    check('and the lists it does print are read from the schemas when asked',
          all(v in files[next(k for k in files if k.startswith('frameworks/'))]
              for v in mcp_server.list_valid_values('progression_model'))
          and all(v in files['philosophy.yaml'] for v in mcp_server.list_valid_values('training_phase')))
    overlay = tempfile.mkdtemp(prefix='skeleton-')
    atexit.register(shutil.rmtree, overlay, True)
    pkg = yaml.safe_load(files['philosophy.yaml'])['id']
    for rel, content in files.items():
        path = os.path.join(overlay, pkg, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'w', encoding='utf-8') as fh:
            fh.write(content)
    with loader.overlay(overlay):
        result = package_gate.check_package(os.path.join(overlay, pkg))
    check('passes every gate as written, and generates', result['ok'], {'problems': result['problems'][:3],
                                                                       'skipped': result['skipped']})


def main() -> int:
    test_document()
    test_served()
    test_skeleton()
    if FAILURES:
        print(f'{len(FAILURES)} failed')
        return 1
    print('all passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
