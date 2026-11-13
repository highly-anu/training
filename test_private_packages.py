#!/usr/bin/env python
"""An athlete's own packages (docs/roadmap.md 20.5): src/package_store.py and
the /api/packages routes.

The package is the modality scheduler's fixture rewritten as an athlete's own
— every id it declares given the owner's prefix — which is what a builder
would hand in: a file map, written from nothing the repository ships. In one
interpreter, as the server is, on the repository's packages unchanged:

  - the limits and the gate refuse what is not a package, and store nothing;
  - an installed package is laid out, loads and generates for its owner, and
    another athlete sees nothing of it;
  - a new revision is a new directory; removal takes it away;
  - through the routes: the same, with the overlay bound by require_auth and
    gone when the request ends.

Then the store on Postgres (a database made and dropped for the run; skipped
without a local server — TEST_ADMIN_DSN points it at one).

Run: SUPABASE_URL='' .venv/bin/python test_private_packages.py
"""
from __future__ import annotations

import atexit
import glob
import os
import re
import shutil
import sys
import tempfile

os.environ['SUPABASE_URL'] = ''
os.environ['DATABASE_URL'] = ''
os.environ.pop('TRAINING_PACKAGES_DIR', None)
BASE = tempfile.mkdtemp(prefix='user-packages-')
atexit.register(shutil.rmtree, BASE, True)
os.environ['TRAINING_USER_PACKAGES_DIR'] = BASE

ROOT = os.path.dirname(os.path.abspath(__file__))
FIXTURE = os.path.join(ROOT, 'test_packages', 'block_fixture')

import yaml  # noqa: E402

from src import loader, package_store  # noqa: E402

FAILURES: list[str] = []
ANN, BEN = 'user-ann', 'user-ben'


def check(label: str, condition: bool, detail='') -> None:
    if condition:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label} {detail}")
        FAILURES.append(label)


def package_for(user_id: str, name: str = 'blocks') -> tuple[str, dict]:
    """The fixture as `user_id`'s own package: (package id, {path: yaml text}).
    Its id, its frameworks, its archetypes and the exercises no shipped
    package declares take the owner's prefix; a framework's file is named for
    its id, as the loader finds it."""
    prefix = package_store.owner_prefix(user_id)
    shipped, _ = loader.load_all_exercises()
    texts = {}
    for path in sorted(glob.glob(os.path.join(FIXTURE, '**', '*.yaml'), recursive=True)):
        texts[os.path.relpath(path, FIXTURE).replace(os.sep, '/')] = open(path, encoding='utf-8').read()
    rename = {yaml.safe_load(texts['philosophy.yaml'])['id']: f'{prefix}{name}'}
    for rel, text in texts.items():
        doc = yaml.safe_load(text) or {}
        if rel.startswith(('frameworks/', 'archetypes/')):
            rename[doc['id']] = prefix + doc['id']
        elif rel == 'exercises.yaml':
            for ex in doc.get('exercises') or []:
                if ex['id'] not in shipped:
                    rename[ex['id']] = prefix + ex['id']
    pattern = re.compile(r'(?<![A-Za-z0-9_])(' + '|'.join(sorted(map(re.escape, rename), key=len, reverse=True))
                         + r')(?![A-Za-z0-9_])')
    files = {}
    for rel, text in texts.items():
        text = pattern.sub(lambda m: rename[m.group(1)], text)
        if rel.startswith('frameworks/'):
            rel = f"frameworks/{yaml.safe_load(text)['id']}.yaml"
        elif rel.startswith('archetypes/'):
            rel = re.sub(r'[^a-z0-9_/]', '_', rel[:-5].lower()) + '.yaml'
        files[rel] = text
    return f'{prefix}{name}', files


def ids() -> set:
    return {p['id'] for p in loader.load_philosophies()}


def generates(package_id: str) -> int:
    from src import package_smoke
    return sum(r['sessions'] for r in package_smoke.smoke_package(package_id) if r['ok'])


def test_limits():
    print('what is not a package is refused before anything is laid out')
    pkg, files = package_for(ANN)
    codes = lambda f: {p['code'] for p in package_store.check(ANN, f)['problems']}   # noqa: E731
    check('no files', codes({}) == {'no_files'} and codes(None) == {'no_files'})
    check('a path a package does not hold', 'path_not_allowed' in codes({**files, '../escape.yaml': 'x: 1'})
          and 'path_not_allowed' in codes({**files, 'records/golden.json': '{}'})
          and 'path_not_allowed' in codes({**files, 'tests/test_x.py': 'import os'}))
    check('a file that is not text', 'not_text' in codes({**files, 'analytics.yaml': {'a': 1}}))
    check('too large', 'too_large' in codes({**files, 'analytics.yaml': '# ' + 'x' * package_store.MAX_BYTES}))
    check('too many files', 'too_many_files' in codes(
        {**files, **{f'archetypes/zz/a{i}.yaml': 'id: x' for i in range(package_store.MAX_FILES)}}))
    check('no philosophy', 'no_philosophy' in codes({k: v for k, v in files.items() if k != 'philosophy.yaml'}))
    check('nothing was stored or laid out', package_store.list_packages(ANN) == []
          and package_store.overlay_for(ANN) is None)


def test_gate():
    print('the gate, as this athlete\'s package')
    pkg, files = package_for(ANN)
    result = package_store.check(ANN, files)
    check('the athlete\'s own passes every stage', result['ok'] and result['package'] == pkg
          and result['prefix'] == package_store.owner_prefix(ANN), {'problems': result['problems'][:3],
                                                                    'skipped': result['skipped']})
    plain = {rel.replace(package_store.owner_prefix(ANN), ''): text.replace(package_store.owner_prefix(ANN), '')
             for rel, text in files.items()}
    result = package_store.check(ANN, plain)
    check('ids without the owner\'s prefix are refused', not result['ok']
          and {p['code'] for p in result['problems']} == {'not_prefixed'}, result['problems'][:3])
    _, bens = package_for(BEN)
    result = package_store.check(ANN, bens)
    check('another athlete\'s prefix is not this one\'s', not result['ok']
          and any(p['code'] == 'not_prefixed' for p in result['problems']))
    broken = {**files, 'frameworks/zz.yaml': 'name: [unclosed'}
    result = package_store.install(ANN, broken)
    check('a file that does not validate: not installed, the problems are the answer', not result['installed']
          and any(p['stage'] == 'schema' for p in result['problems']), result['problems'][:2])
    check('and nothing was stored', package_store.list_packages(ANN) == [])
    check('no scratch folder is left behind', not [d for d in os.listdir(BASE) if d.startswith('.')], os.listdir(BASE))


def test_install():
    print('installed: for its owner, and nobody else')
    pkg, files = package_for(ANN)
    shipped = ids()
    result = package_store.install(ANN, files)
    check('installed at revision 1', result['installed'] and result['revision'] == 1, result.get('problems'))
    listed = package_store.list_packages(ANN)
    check('listed with its name', [p['id'] for p in listed] == [pkg] and listed[0]['name']
          and listed[0]['status'] == 'installed', listed)
    check('its files read back', package_store.get_package(ANN, pkg)['files'] == files)
    mine = package_store.overlay_for(ANN)
    check('laid out as a folder', bool(mine) and os.path.isfile(os.path.join(mine, pkg, 'philosophy.yaml')), mine)
    check('the other athlete has no overlay', package_store.overlay_for(BEN) is None
          and package_store.list_packages(BEN) == [] and package_store.get_package(BEN, pkg) is None)
    check('without an overlay nothing changed', ids() == shipped)
    with loader.overlay(mine):
        check('its owner sees it beside the shipped packages', ids() == shipped | {pkg})
        check('and it generates', generates(pkg) > 0)
        check('nothing is set aside', loader.quarantined() == [])
    with loader.overlay(package_store.overlay_for(BEN)):
        check('the other athlete sees the shipped packages alone', ids() == shipped)

    print('a new revision is a new directory')
    files2 = {**files, 'philosophy.yaml': files['philosophy.yaml'].replace('name:', 'name: Second', 1)}
    result = package_store.install(ANN, files2)
    second = package_store.overlay_for(ANN)
    check('revision 2, laid out beside the first', result['installed'] and result['revision'] == 2
          and second != mine and os.path.isdir(second), (result.get('revision'), second))
    with loader.overlay(second):
        check('the new files are the ones read', loader.load_philosophy(pkg)['name'].startswith('Second'))
    check('one row, not two', len(package_store.list_packages(ANN)) == 1)

    print('each athlete their own')
    bpkg, bfiles = package_for(BEN)
    check('the same method installs for another athlete under their prefix',
          package_store.install(BEN, bfiles)['installed'] and bpkg != pkg)
    with loader.overlay(package_store.overlay_for(BEN)):
        check('who sees theirs and not the first athlete\'s', bpkg in ids() and pkg not in ids())
    with loader.overlay(package_store.overlay_for(ANN)):
        check('and the reverse', pkg in ids() and bpkg not in ids())

    print('removed')
    check('removes', package_store.remove(ANN, pkg) is True)
    check('nothing listed, nothing laid out', package_store.list_packages(ANN) == []
          and package_store.overlay_for(ANN) is None and package_store.get_package(ANN, pkg) is None)
    check('a second removal finds nothing', package_store.remove(ANN, pkg) is False)
    check('the other athlete keeps theirs', [p['id'] for p in package_store.list_packages(BEN)] == [bpkg])
    package_store.remove(BEN, bpkg)
    left = [d for d in os.listdir(BASE) if not d.startswith('_')]
    check('at most the last overlay of each is left on disk', len(left) <= 2, left)


def test_engine_change():
    print('a package that stops loading is set aside for its owner alone')
    pkg, files = package_for(ANN)
    package_store.install(ANN, files)
    mine = package_store.overlay_for(ANN)
    # What an engine change can do to a stored package: a file the loader can no longer index.
    fw = next(p for p in glob.glob(os.path.join(mine, pkg, 'frameworks', '*.yaml')))
    open(fw, 'w', encoding='utf-8').write('name: no id any more\n')
    loader.forget_overlay(mine)
    shipped = None
    with loader.overlay(None):
        shipped = ids()
    with loader.overlay(mine):
        check('set aside, with why', [q['package'] for q in loader.quarantined()] == [pkg])
        check('the shipped packages still load for them', ids() == shipped)
    package_store.remove(ANN, pkg)


def test_routes():
    print('the routes (local dev: every request is local-dev-user)')
    import api
    client = api.app.test_client()
    me = 'local-dev-user'
    pkg, files = package_for(me)
    body = client.get('/api/packages').get_json()
    check('the list says the prefix and the limits', body['prefix'] == package_store.owner_prefix(me)
          and body['packages'] == [] and body['limits']['files'] == package_store.MAX_FILES, body)
    dry = client.post('/api/packages', json={'files': files, 'dry_run': True})
    check('a dry run checks and stores nothing', dry.status_code == 200 and dry.get_json()['ok']
          and not dry.get_json()['installed'] and client.get('/api/packages').get_json()['packages'] == [],
          dry.get_json())
    bad = client.post('/api/packages', json={'files': {**files, 'frameworks/zz.yaml': 'name: [unclosed'}})
    check('a package that does not pass answers 422 with the problems', bad.status_code == 422
          and bad.get_json()['problems'] and not bad.get_json()['installed'], bad.get_json())
    done = client.post('/api/packages', json={'files': files})
    check('installs', done.status_code == 200 and done.get_json()['installed'] and done.get_json()['revision'] == 1,
          done.get_json())
    check('listed, and read back with its files',
          [p['id'] for p in client.get('/api/packages').get_json()['packages']] == [pkg]
          and client.get(f'/api/packages/{pkg}').get_json()['files'] == files)
    check('an unknown id is 404', client.get('/api/packages/zz_none').status_code == 404
          and client.delete('/api/packages/zz_none').status_code == 404)

    phil = yaml.safe_load(files['philosophy.yaml'])
    fw_file = next(v for k, v in files.items() if k.startswith('frameworks/'))
    exp = (yaml.safe_load(fw_file).get('expectations') or {})
    constraints = {'days_per_week': exp.get('ideal_days_per_week', 4),
                   'session_time_minutes': exp.get('ideal_session_minutes', 60), 'training_level': 'intermediate',
                   'equipment': api.loader.load_equipment() and [e['id'] for e in api.loader.load_equipment()],
                   'injury_flags': [], 'periodization_week': 1, 'fatigue_state': 'normal'}
    made = client.post('/api/programs/generate', json={'philosophy_id': phil['id'], 'constraints': constraints,
                                                       'num_weeks': 2, 'persist': False})
    program = made.get_json()
    check('a program generates from it through the API', made.status_code == 200 and len(program.get('weeks') or []) == 2,
          (made.status_code, str(program)[:300]))
    check('when the request ends the thread sees no overlay', loader.overlay_dir() is None and pkg not in ids())

    from src import db
    real = db.get_user_program
    db.get_user_program = lambda user_id: program
    try:
        held = client.delete(f'/api/packages/{pkg}')
        check('it cannot be removed while the athlete\'s program is built from it', held.status_code == 409
              and held.get_json()['error'] == 'in_use', held.get_json())
    finally:
        db.get_user_program = real
    check('removed', client.delete(f'/api/packages/{pkg}').status_code == 200
          and client.get('/api/packages').get_json()['packages'] == [])
    gone = client.post('/api/programs/generate', json={'philosophy_id': phil['id'], 'constraints': constraints,
                                                       'num_weeks': 1, 'persist': False})
    check('and nothing generates from it any more', not (gone.get_json() or {}).get('weeks'), gone.status_code)

    print('the routes are behind the authoring gate')
    os.environ['SUPABASE_URL'] = 'https://example.invalid'   # as production: authoring off unless switched on
    try:
        check('off, they answer 403', not api._authoring_enabled())
    finally:
        os.environ['SUPABASE_URL'] = ''


def test_sql():
    print('the store on Postgres')
    admin = os.environ.get('TEST_ADMIN_DSN', 'postgresql://localhost:5432/postgres?sslmode=disable')
    if 'supabase' in admin or 'pooler' in admin:
        print('  Refusing to run against what looks like a production database.')
        FAILURES.append('admin dsn')
        return
    try:
        import psycopg2
        conn = psycopg2.connect(admin)
        conn.autocommit = True
    except Exception as exc:
        print(f'  No local PostgreSQL available ({exc.__class__.__name__}) — skipping.')
        return
    name = f'user_packages_test_{os.getpid()}'
    with conn.cursor() as cur:
        cur.execute(f'CREATE DATABASE {name}')
    import importlib
    import src.db
    try:
        dsn = admin.rsplit('/', 1)[0] + f'/{name}?sslmode=disable'
        os.environ['DATABASE_URL'] = dsn
        importlib.reload(src.db)                # it reads DATABASE_URL at import time
        package_store._SCHEMA_READY = False
        package_store._SETS.clear()
        pkg, files = package_for(ANN)
        check('nothing yet (the table is made on first use)', package_store.list_packages(ANN) == [])
        check('installs', package_store.install(ANN, files)['revision'] == 1)
        check('again is revision 2 of the same row', package_store.install(ANN, files)['revision'] == 2
              and len(package_store.list_packages(ANN)) == 1)
        check('reads back', package_store.get_package(ANN, pkg)['files'] == files)
        check('another athlete reads none of it', package_store.list_packages(BEN) == []
              and package_store.overlay_for(BEN) is None)
        mine = package_store.overlay_for(ANN)
        with loader.overlay(mine):
            check('laid out from the row, and it loads', pkg in ids())
        check('removed: the row is kept and marked', package_store.remove(ANN, pkg)
              and package_store.list_packages(ANN) == [] and package_store.overlay_for(ANN) is None)
        with psycopg2.connect(dsn) as c, c.cursor() as cur:
            cur.execute('SELECT deleted_at IS NOT NULL, revision FROM user_packages WHERE user_id = %s', (ANN,))
            check('its revision kept', cur.fetchall() == [(True, 2)])
            cur.execute("SELECT relrowsecurity FROM pg_class WHERE relname = 'user_packages'")
            check('row security is on (deny-by-default until 013 adds the policy)', cur.fetchone()[0] is True)
            cur.execute("SELECT 1 FROM information_schema.columns WHERE table_name = 'user_packages' "
                        "AND column_name = 'user_id'")
            check('account deletion finds it: a public table with a user_id', cur.fetchone() is not None)
        check('installed again after removal: the row comes back', package_store.install(ANN, files)['revision'] == 3
              and len(package_store.list_packages(ANN)) == 1)
    finally:
        src.db.close_conn()
        os.environ['DATABASE_URL'] = ''
        importlib.reload(src.db)
        package_store._SCHEMA_READY = False
        with conn.cursor() as cur:
            cur.execute(f'DROP DATABASE IF EXISTS {name} WITH (FORCE)')
        conn.close()


def main() -> int:
    test_limits()
    test_gate()
    test_install()
    test_engine_change()
    test_routes()
    test_sql()
    if FAILURES:
        print(f'{len(FAILURES)} failed')
        return 1
    print('all passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
