#!/usr/bin/env python
"""The authoring paths: the API's write routes and the MCP server's tools.

On a copy of the packages (`TRAINING_PACKAGES_DIR`), never the repository's:

- the API creates, edits and deletes only in the `custom` package — a PUT on a
  shipped exercise, archetype or framework answers 403 (roadmap 9.7; an
  authored package is edited as files in a branch, where the gates check it);
- mcp_server.py checks every file kind a package carries with the gates' own
  validator (it used to know four schemas, one of them gone, and wrote
  analytics, watch, contract, fidelity and source-week files unchecked), a
  package with add_package's checks, and writes and deletes only inside the
  packages folder.

    SUPABASE_URL='' .venv/bin/python test_authoring.py
"""
from __future__ import annotations

import atexit
import copy
import os
import shutil
import subprocess
import sys
import tempfile

import yaml

ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ROOT)
os.environ['SUPABASE_URL'] = ''
os.environ['DATABASE_URL'] = ''
os.environ.pop('AUTHORING_ENABLED', None)


def _stage() -> str:
    folder = tempfile.mkdtemp(prefix='packages-')
    atexit.register(shutil.rmtree, folder, True)
    for name in sorted(os.listdir(os.path.join(ROOT, 'data', 'packages'))):
        src = os.path.join(ROOT, 'data', 'packages', name)
        if os.path.isdir(src):
            shutil.copytree(src, os.path.join(folder, name))
    os.environ['TRAINING_PACKAGES_DIR'] = folder
    return folder


FOLDER = _stage()
BEFORE = subprocess.run(['git', 'status', '--porcelain'], cwd=ROOT, capture_output=True, text=True).stdout

FAILURES: list[str] = []


def check(label: str, condition: bool, detail='') -> None:
    if condition:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label} {detail}")
        FAILURES.append(label)


def _first(pattern: str) -> dict:
    import glob
    return yaml.safe_load(open(sorted(glob.glob(os.path.join(FOLDER, pattern), recursive=True))[0], encoding='utf-8'))


def test_api() -> None:
    print('the API writes only the custom package')
    import api
    client = api.app.test_client()
    exercise = next(e for e in _first('starting_strength/exercises.yaml')['exercises'] if e['id'] == 'back_squat')
    archetype = _first('starting_strength/archetypes/**/*.yaml')
    framework = _first('starting_strength/frameworks/*.yaml')

    for path, body in ((f"/api/exercises/{exercise['id']}", {'name': 'Renamed'}),
                       (f"/api/archetypes/{archetype['id']}", {'name': 'Renamed'}),
                       (f"/api/frameworks/{framework['id']}", {'notes': 'edited'})):
        r = client.put(path, json=body)
        check(f'PUT {path.split("/")[2]} on a shipped package is refused', r.status_code == 403
              and 'custom package' in (r.get_json() or {}).get('detail', ''), (r.status_code, r.get_json()))

    mine = {**copy.deepcopy(exercise), 'id': 'zz_custom_squat', 'name': 'Custom squat'}
    r = client.post('/api/exercises', json=mine)
    check('an exercise is created in the custom package', r.status_code == 201, (r.status_code, r.get_json()))
    r = client.put('/api/exercises/zz_custom_squat', json={'name': 'Custom squat, renamed'})
    check('and edited there', r.status_code == 200 and r.get_json()['name'] == 'Custom squat, renamed',
          (r.status_code, r.get_json()))
    shared = {**copy.deepcopy(exercise), 'name': 'Custom back squat'}
    r = client.post('/api/exercises', json=shared)
    check('an id another package has is not created', r.status_code == 409, r.status_code)
    # A shared id the custom package declares by hand (packages may share
    # exercise ids): the edit lands on the custom copy, not the first found.
    path = os.path.join(FOLDER, 'custom', 'exercises.yaml')
    doc = yaml.safe_load(open(path, encoding='utf-8'))
    doc['exercises'].append(shared)
    yaml.safe_dump(doc, open(path, 'w', encoding='utf-8'), sort_keys=False)
    r = client.put(f"/api/exercises/{exercise['id']}", json={'notes': 'edited in custom'})
    check("a shared id is edited in the custom package's copy, not another's", r.status_code == 200
          and 'edited in custom' in open(path, encoding='utf-8').read()
          and 'edited in custom' not in open(os.path.join(FOLDER, 'starting_strength', 'exercises.yaml'),
                                             encoding='utf-8').read(), (r.status_code, r.get_json()))

    arch = {**copy.deepcopy(archetype), 'id': 'zz_custom_session', 'name': 'Custom session'}
    r = client.post('/api/archetypes', json=arch)
    check('an archetype is created in the custom package', r.status_code == 201, (r.status_code, r.get_json()))
    r = client.put('/api/archetypes/zz_custom_session', json={'name': 'Custom session, renamed'})
    check('and edited there', r.status_code == 200, (r.status_code, r.get_json()))
    os.makedirs(os.path.join(FOLDER, 'custom', 'frameworks'), exist_ok=True)
    with open(os.path.join(FOLDER, 'custom', 'frameworks', 'zz_custom_framework.yaml'), 'w', encoding='utf-8') as fh:
        yaml.safe_dump({**framework, 'id': 'zz_custom_framework'}, fh)
    r = client.put('/api/frameworks/zz_custom_framework', json={'notes': 'edited'})
    check("a custom package's framework is edited", r.status_code == 200, (r.status_code, r.get_json()))
    r = client.delete('/api/archetypes/zz_custom_session')
    check('and deleted there', r.status_code == 200, (r.status_code, r.get_json()))


def test_mcp() -> None:
    print('the MCP server')
    import mcp_server as m
    check('it writes where the loader reads', os.path.realpath(m.PACKAGES_DIR) == os.path.realpath(FOLDER))
    check('it knows every kind a package carries, and no goal profile',
          set(m.KIND_PATHS) == set(m.SCHEMA_FILES) and 'goal_profile' not in m.SCHEMA_FILES
          and all(os.path.exists(os.path.join(ROOT, 'docs', 'schemas', f)) for f in m.SCHEMA_FILES.values()))

    phil = open(os.path.join(FOLDER, 'atg', 'philosophy.yaml'), encoding='utf-8').read()
    check('a valid philosophy validates', m.validate_yaml('philosophy', phil)['valid'],
          m.validate_yaml('philosophy', phil)['errors'][:2])
    bad_analytics = 'id: atg\nnot_a_field: 1\n'
    result = m.validate_yaml('analytics', bad_analytics, 'atg')
    check('an analytics file is checked (it was written unchecked)', not result['valid'], result)
    result = m.validate_yaml('training_contract', 'version: 1\n')
    check('so is a training contract', not result['valid'], result)
    result = m.validate_yaml('standards', 'standards:\n  - {id: back_squat_bw_ratio, name: x, domain: power, '
                             'metric_type: reps, levels: {entry: {male: 1}, intermediate: {male: 2}, '
                             'advanced: {male: 3}, elite: {male: 4}}}\n', 'atg')
    check("a package standard taking a commons id is refused", not result['valid']
          and any('commons' in e['message'] for e in result['errors']), result)

    written = m.write_package_file('zz_new', 'analytics.yaml', bad_analytics)
    check('an invalid file is not written', not written['written']
          and not os.path.exists(os.path.join(FOLDER, 'zz_new', 'analytics.yaml')), written)
    written = m.write_package_file('zz_new', 'exercise_media.yaml', 'push_up: {}\n')
    check('a file no schema covers is written as is', written['written'], written)
    escaped = m.write_package_file('zz_new', '../../escape.yaml', 'x: 1\n')
    check('a path out of the packages folder is refused', not escaped['written'], escaped)

    check('a shipped package validates', m.validate_package('wildman_kettlebell')['valid'],
          m.validate_package('wildman_kettlebell')['files'])
    shutil.copytree(os.path.join(FOLDER, 'atg'), os.path.join(FOLDER, 'zz_atg_copy'))
    path = os.path.join(FOLDER, 'zz_atg_copy', 'philosophy.yaml')
    text = open(path, encoding='utf-8').read().replace('id: atg\n', 'id: zz_atg_copy\n', 1)
    open(path, 'w', encoding='utf-8').write(text)
    result = m.validate_package('zz_atg_copy')
    check("a copy that takes another package's ids is refused, naming them", not result['valid']
          and any('also declared by atg' in e for e in result['files'].get('(package)', [])), result['files'])
    check('a standard id is checked too', not m.check_id_available('standard', 'back_squat_bw_ratio')['available'])

    check('a delete outside the packages folder is refused', not m.delete_package('..')['deleted'])
    check('a package folder is deleted', m.delete_package('zz_atg_copy')['deleted']
          and not os.path.exists(os.path.join(FOLDER, 'zz_atg_copy')))


def main() -> int:
    test_api()
    test_mcp()
    after = subprocess.run(['git', 'status', '--porcelain'], cwd=ROOT, capture_output=True, text=True).stdout
    check('nothing in the repository changed', before_equals(after), after)
    if FAILURES:
        print(f'{len(FAILURES)} failed')
        return 1
    print('all passed')
    return 0


def before_equals(after: str) -> bool:
    return after == BEFORE


if __name__ == '__main__':
    sys.exit(main())
