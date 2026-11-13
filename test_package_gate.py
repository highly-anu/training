#!/usr/bin/env python
"""src/package_gate.check_package: one folder through the gates' own checks,
as data (docs/roadmap.md 20.2).

The shipped packages and the scheduler's fixture are staged in a scratch
packages directory, and broken copies are made beside them: the wrong id, a
file that does not validate, ids another package declares, a folder outside
the directory. The stages after generation are exercised twice — on real
packages (they pass), and with package_smoke stubbed to fail, since a package
that validates yet cannot generate is hard to write by hand and easy for a
model to.

Run: SUPABASE_URL='' .venv/bin/python test_package_gate.py
"""
from __future__ import annotations

import atexit
import os
import re
import shutil
import sys
import tempfile

os.environ.setdefault('SUPABASE_URL', '')
os.environ.setdefault('DATABASE_URL', '')

ROOT = os.path.dirname(os.path.abspath(__file__))
SHIPPED = sorted(n for n in os.listdir(os.path.join(ROOT, 'data', 'packages'))
                 if os.path.isdir(os.path.join(ROOT, 'data', 'packages', n)))
FIXTURE = 'block_fixture'

FOLDER = tempfile.mkdtemp(prefix='gate-packages-')
OUTSIDE = tempfile.mkdtemp(prefix='gate-outside-')
atexit.register(shutil.rmtree, FOLDER, True)
atexit.register(shutil.rmtree, OUTSIDE, True)
for _name in SHIPPED:
    shutil.copytree(os.path.join(ROOT, 'data', 'packages', _name), os.path.join(FOLDER, _name))
shutil.copytree(os.path.join(ROOT, 'test_packages', FIXTURE), os.path.join(FOLDER, FIXTURE))
SCRATCH = 'scratch_minimal'   # written from nothing, with a vocabulary of its own (the spec's worked example)
shutil.copytree(os.path.join(ROOT, 'test_packages', SCRATCH), os.path.join(FOLDER, SCRATCH))
os.environ['TRAINING_PACKAGES_DIR'] = FOLDER

from src import package_gate, package_smoke  # noqa: E402

FAILURES: list[str] = []


def check(label: str, condition: bool, detail='') -> None:
    if condition:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label} {detail}")
        FAILURES.append(label)


def _copy(source: str, name: str, folder: str = FOLDER, rename: bool = True) -> str:
    """A copy of a staged package under another folder name, its philosophy id
    following the folder unless `rename` is off."""
    dest = os.path.join(folder, name)
    shutil.copytree(os.path.join(FOLDER, source), dest)
    if rename:
        path = os.path.join(dest, 'philosophy.yaml')
        text = open(path, encoding='utf-8').read()
        open(path, 'w', encoding='utf-8').write(re.sub(rf'^id: {source}$', f'id: {name}', text, flags=re.M))
    return dest


def codes(result: dict) -> set:
    return {(p['stage'], p['code']) for p in result['problems']}


def test_passes():
    print('packages that run')
    shapes = {}
    # a contract, week templates, the scheduler, and one written from nothing
    for name in ('wildman_kettlebell', 'horsemen_gpp', FIXTURE, SCRATCH):
        r = package_gate.check_package(os.path.join(FOLDER, name))
        shapes[name] = r
        check(f'{name}: ok, every stage ran', r['ok'] and r['ran'] == list(package_gate.STAGES) and not r['skipped'],
              {'problems': r['problems'][:3], 'skipped': r['skipped']})
        check(f'{name}: its tracks and phases', bool(r['tracks']) and all(t['phases'] for t in r['tracks']), r['tracks'])
    check('the result is the documented shape',
          set(shapes[FIXTURE]) == {'package', 'ok', 'problems', 'warnings', 'ran', 'skipped', 'tracks', 'seconds'})
    quick = package_gate.check_package(os.path.join(FOLDER, FIXTURE), smoke=False)
    check('smoke=False stops before generating, and says so',
          quick['ran'] == ['files', 'schema', 'ids'] and [s['stage'] for s in quick['skipped']] == ['smoke', 'provenance']
          and not quick['ok'] and not quick['problems'], quick)


def test_files():
    print('a folder that is not a package')
    empty = os.path.join(FOLDER, 'zz_empty')
    os.makedirs(empty)
    r = package_gate.check_package(empty)
    check('no philosophy.yaml', codes(r) == {('files', 'no_philosophy')} and not r['ok'], r['problems'])
    check('nothing after it runs', r['ran'] == ['files'] and len(r['skipped']) == 4, r)
    shutil.rmtree(empty)

    wrong = _copy(FIXTURE, 'zz_wrong_id', rename=False)
    r = package_gate.check_package(wrong)
    check("an id that is not the folder's name", codes(r) == {('files', 'id_not_folder')}
          and FIXTURE in r['problems'][0]['message'] and 'zz_wrong_id' in r['problems'][0]['message'], r['problems'])
    shutil.rmtree(wrong)

    broken = _copy(FIXTURE, 'zz_unparsable')
    open(os.path.join(broken, 'philosophy.yaml'), 'w', encoding='utf-8').write('id: [unclosed\n')
    r = package_gate.check_package(broken)
    check('a philosophy.yaml that does not parse', codes(r) == {('files', 'yaml')}, r['problems'])
    shutil.rmtree(broken)

    r = package_gate.check_package(os.path.join(FOLDER, 'zz_nowhere'))
    check('a path that is not a folder', codes(r) == {('files', 'not_a_folder')}, r['problems'])


def test_schema():
    print('a file that does not validate')
    bad = _copy(FIXTURE, 'zz_bad_file')
    with open(os.path.join(bad, 'archetypes', 'zz_no_slots.yaml'), 'w', encoding='utf-8') as fh:
        fh.write('id: zz_no_slots\nname: No slots\nmodality: not_a_modality\n')
    r = package_gate.check_package(bad)
    found = [p for p in r['problems'] if p['stage'] == 'schema']
    check('found, in its file', bool(found) and all(p['file'] == 'archetypes/zz_no_slots.yaml' for p in found),
          r['problems'][:3])
    check('and nothing is generated from it', r['ran'] == ['files', 'schema']
          and [s['stage'] for s in r['skipped']] == ['ids', 'smoke', 'provenance'] and not r['ok'], r)
    shutil.rmtree(bad)

    print('a modality in scope that nothing serves')
    scoped = _copy(FIXTURE, 'zz_scope')
    path = os.path.join(scoped, 'philosophy.yaml')
    text = open(path, encoding='utf-8').read()
    import yaml
    doc = yaml.safe_load(text)
    served = set()
    for root, _dirs, names in os.walk(os.path.join(scoped, 'archetypes')):
        for n in names:
            served.add((yaml.safe_load(open(os.path.join(root, n), encoding='utf-8')) or {}).get('modality'))
    from src import loader
    extra = next(m for m in sorted(loader.load_all_modalities()) if m not in served and m not in (doc.get('scope') or []))
    doc['scope'] = list(doc.get('scope') or []) + [extra]
    yaml.safe_dump(doc, open(path, 'w', encoding='utf-8'), sort_keys=False, allow_unicode=True)
    r = package_gate.check_package(scoped, smoke=False)
    check('is a warning, not a problem', any(w['code'] == 'scope_unserved' and extra in w['message'] for w in r['warnings'])
          and not any(p['stage'] == 'schema' for p in r['problems']), {'warnings': r['warnings'], 'problems': r['problems']})
    shutil.rmtree(scoped)


def test_ids():
    print('ids another package declares')
    copy = _copy('atg', 'zz_atg_copy')
    r = package_gate.check_package(copy)
    check('refused, naming the other package', ('ids', 'collision') in codes(r)
          and any('also declared by atg' in p['message'] for p in r['problems']), r['problems'][:3])
    check('before anything is generated', r['ran'] == ['files', 'schema', 'ids'] and not r['ok'], r['ran'])
    other = package_gate.check_package(os.path.join(FOLDER, 'atg'), smoke=False)
    check('and the shipped one is told too, while the copy is there', ('ids', 'collision') in codes(other))
    shutil.rmtree(copy)
    check('gone with the copy', not package_gate.check_package(os.path.join(FOLDER, 'atg'), smoke=False)['problems'])

    print('a folder outside the packages directory')
    away = _copy(FIXTURE, FIXTURE, folder=OUTSIDE, rename=False)
    r = package_gate.check_package(away)
    check('is checked as far as its files', r['ran'] == ['files', 'schema'] and not r['problems'], r)
    check('the rest is skipped out loud, so it is not ok',
          [s['stage'] for s in r['skipped']] == ['ids', 'smoke', 'provenance'] and not r['ok']
          and 'packages directory' in r['skipped'][0]['why'], r['skipped'])


def test_generation_findings():
    print('a package that validates and cannot generate')
    folder = os.path.join(FOLDER, FIXTURE)
    real_smoke, real_audit = package_smoke.smoke_package, package_smoke.audit_program
    base = {'label': f'{FIXTURE}/t/p', 'ok': True, 'days': 4, 'sessions': 4, 'why': None,
            'missing_framework': None, 'test_problems': None, 'program': None}
    try:
        package_smoke.smoke_package = lambda pkg: [
            {**base, 'ok': False, 'sessions': 0, 'why': ['INSUFFICIENT_DAYS']},
            {**base, 'ok': False, 'why': ['ran another_framework']},
            {**base, 'ok': False, 'sessions': 0, 'why': 'generated 0 sessions'},
            {**base, 'ok': False, 'missing_framework': 'gone', 'why': "framework 'gone' not found"},
            {**base, 'test_problems': ['week 4: 0 of 1 tests placed']},
        ]
        r = package_gate.check_package(folder)
        check('each finding is a problem of its kind', codes(r) == {
            ('smoke', 'infeasible'), ('smoke', 'wrong_framework'), ('smoke', 'no_sessions'),
            ('smoke', 'missing_framework'), ('smoke', 'test_not_placed')}, sorted(codes(r)))
        check('each names its track and phase', all(p['message'].startswith(f'{FIXTURE}/t/p') for p in r['problems']))
        check('not ok', not r['ok'])

        package_smoke.smoke_package = lambda pkg: []
        r = package_gate.check_package(folder)
        check('no phase to generate is a problem', codes(r) == {('smoke', 'no_phases')}, r['problems'])

        def boom(pkg):
            raise KeyError('slots')
        package_smoke.smoke_package = boom
        r = package_gate.check_package(folder)
        check('a generator that raises is a finding, not a crash', codes(r) == {('smoke', 'raised')}
              and 'KeyError' in r['problems'][0]['message'] and r['skipped'] == [
                  {'stage': 'provenance', 'why': 'generation raised'}], r)

        print('a program that draws from outside its package')
        package_smoke.smoke_package = real_smoke
        package_smoke.audit_program = lambda raw, policy, ex_index: {
            'archetypes': {}, 'exercises': {}, 'foreign': ['archetype stray from elsewhere']}
        r = package_gate.check_package(os.path.join(FOLDER, 'wildman_kettlebell'))
        leaks = [p for p in r['problems'] if p['stage'] == 'provenance']
        check('is a provenance problem, said once', len(leaks) == 1 and leaks[0]['code'] == 'foreign'
              and 'archetype stray from elsewhere' in leaks[0]['message'], r['problems'][:3])
    finally:
        package_smoke.smoke_package, package_smoke.audit_program = real_smoke, real_audit


def test_tools_share_it():
    print('the tools run the same code')
    from tools import add_package, check_provenance, check_styles
    from src import portability
    check('check_styles\' loop', check_styles.smoke_philosophy is package_smoke.smoke_philosophy)
    check('check_provenance\'s audit', check_provenance.audit_program is package_smoke.audit_program)
    check('add_package\'s checks', add_package._problems is portability.problems)

    import mcp_server
    result = mcp_server.validate_package(FIXTURE)
    check('the MCP server answers from the gate', result['valid'] and result['ran'] == list(package_gate.STAGES)
          and result['files'] == {}, result)
    copy = _copy('atg', 'zz_atg_copy')
    result = mcp_server.validate_package('zz_atg_copy')
    check('and groups a finding that names no file under (package)', not result['valid']
          and any('also declared by atg' in e for e in result['files'].get('(package)', [])), result['files'])
    shutil.rmtree(copy)


def main() -> int:
    test_passes()
    test_files()
    test_schema()
    test_ids()
    test_generation_findings()
    test_tools_share_it()
    if FAILURES:
        print(f'{len(FAILURES)} failed')
        return 1
    print('all passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
