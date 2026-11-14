#!/usr/bin/env python
"""A build of an athlete's own method as a durable job (docs/roadmap.md 21.2):
src/build_store.py, src/build_worker.py and the /api/methods/builds routes.

No model: the builder here is scripted — it writes the from-scratch test
package (test_packages/scratch_minimal, under the athlete's prefix) into the
draft, checks it against the real gates and returns it, or fails, stalls or is
cancelled as a case needs. The worker, the store, the install and the routes
are the real ones, in one interpreter as the server is.

Then the store on Postgres (a database made and dropped for the run; skipped
without a local server — TEST_ADMIN_DSN points it at one).

Run: SUPABASE_URL='' .venv/bin/python test_package_builds.py
"""
from __future__ import annotations

import atexit
import os
import shutil
import sys
import tempfile
import threading

os.environ['SUPABASE_URL'] = ''
os.environ['DATABASE_URL'] = ''
os.environ.pop('TRAINING_PACKAGES_DIR', None)
os.environ.pop('PACKAGE_BUILDER', None)
os.environ['ANTHROPIC_API_KEY'] = 'test-key'      # the builder reports itself available; nothing calls a model here
BASE = tempfile.mkdtemp(prefix='package-builds-')
atexit.register(shutil.rmtree, BASE, True)

import test_private_packages as tpp  # noqa: E402  (sets TRAINING_USER_PACKAGES_DIR to its own scratch folder)

import api  # noqa: E402
from src import build_store, build_worker, heavy, loader, package_store  # noqa: E402

FAILURES: list[str] = []
ME = 'local-dev-user'
client = api.app.test_client()
DESCRIPTION = 'Lift an atlas stone to the shoulder twice a week and walk easily twice a week, eight weeks.'


def check(label: str, condition: bool, detail='') -> None:
    if condition:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label} {detail}")
        FAILURES.append(label)


def scripted(session, name='stones'):
    """A builder that writes the from-scratch package and checks it."""
    _pkg, files = tpp.package_for(session.user_id, name, tpp.SCRATCH)
    session.transcript.append({'turn': len(session.transcript) + 1})
    session.draft_files = dict(files)
    session.save(stage='writing', turns=1)
    result = session.check()
    session.save(stage='checking', checks=1, problems=len(result['problems']))
    if not result['ok']:
        return {'ok': False, 'error': {'code': 'not_installable', 'message': 'did not pass'}}
    return {'ok': True, 'files': session.draft_files, 'name': 'Stone work', 'summary': 'Two stone days, two walks.',
            'check': result}


def start(body=None, **headers):
    if body is None:
        body = {'description': DESCRIPTION, 'answers': {'days': 4, 'minutes': 45}}
    return client.post('/api/methods/builds', json=body, **headers)


def settle():
    """Wait for the worker, then run anything still open (deterministic)."""
    build_worker.join(120)
    build_worker.drain()


def clean():
    for p in package_store.list_packages(ME):
        package_store.remove(ME, p['id'])
    with build_store._FILE_LOCK:
        build_store._write_file_rows({})


def test_built():
    print('a build, to a method the athlete can use')
    build_worker.BUILDER = scripted
    res = start()
    build = res.get_json()['build']
    check('202, queued, with its id', res.status_code == 202 and build['status'] in ('queued', 'running') and build['id'], res.get_json())
    check('the description is kept short in what a client reads', build['description'] == DESCRIPTION and 'transcript' not in build
          and 'draft_files' not in build)
    settle()
    done = client.get(f"/api/methods/builds/{build['id']}").get_json()['build']
    check('done', done['status'] == 'done' and done['progress']['stage'] == 'done', done)
    check('with what was built', done['result']['name'] == 'Stone work' and done['result']['revision'] == 1
          and done['result']['packageId'].startswith(package_store.owner_prefix(ME)), done['result'])
    check('and what it took', done['progress']['turns'] == 1 and done['progress']['checks'] == 1, done['progress'])
    listed = client.get('/api/methods').get_json()
    check('the method is the athlete\'s', [m['id'] for m in listed['methods']] == [done['result']['packageId']], listed['methods'])
    check('the build is in their list, and counted against today', listed['builds'][0]['id'] == build['id']
          and listed['limits']['remaining'] == listed['limits']['daily'] - 1, listed['limits'])
    check('a program generates from it', client.get('/api/philosophies').status_code == 200
          and done['result']['packageId'] in {p['id'] for p in client.get('/api/philosophies').get_json()})
    check('the worker left no overlay on its thread or this one', loader.overlay_dir() is None)
    return done['result']['packageId']


def test_install_once():
    print('a build that ends on a passing check pays for the gates once')
    clean()
    calls = []
    real = package_store.check

    def counting(user_id, files, **kw):
        calls.append(1)
        return real(user_id, files, **kw)
    package_store.check = counting
    try:
        build_worker.BUILDER = scripted
        start()
        settle()
    finally:
        package_store.check = real
    check('one check, not two', len(calls) == 1, len(calls))
    _pkg, files = tpp.package_for(ME, 'stones', tpp.SCRATCH)
    other = dict(files)
    other['analytics.yaml'] = files['analytics.yaml'] + '\n# changed since it was checked\n'
    result = real(ME, files)
    calls.clear()
    package_store.check = counting
    try:
        package_store.install(ME, other, checked=result)
    finally:
        package_store.check = real
    check('a check of other files is not taken for these', len(calls) == 1, len(calls))
    calls.clear()
    package_store.check = counting
    try:
        package_store.install(ME, files, checked={**result, 'ok': False})
    finally:
        package_store.check = real
    check('nor a check that did not pass', len(calls) == 1, len(calls))


def test_revise(package_id):
    print('revise: a new revision of the same method')
    clean()
    build_worker.BUILDER = scripted
    start()
    settle()
    package_id = client.get('/api/methods').get_json()['methods'][0]['id']
    before = client.get('/api/methods').get_json()['methods'][0]['revision']
    seen = {}

    def revising(session):
        seen['draft'] = dict(session.draft_files)
        seen['request'] = session.request
        return scripted(session)
    build_worker.BUILDER = revising
    res = start({'revise': {'packageId': package_id, 'note': 'Make the walks longer.'}})
    check('202', res.status_code == 202 and res.get_json()['build']['revise'] == package_id, res.get_json())
    settle()
    done = client.get(f"/api/methods/builds/{res.get_json()['build']['id']}").get_json()['build']
    _pkg, installed_files = tpp.package_for(ME, 'stones', tpp.SCRATCH)
    check('the builder starts from the method as installed', seen['draft'] == installed_files, list(seen.get('draft', {}))[:3])
    check('with the note as what to do', seen['request']['description'] == 'Make the walks longer.'
          and seen['request']['revise']['packageId'] == package_id)
    check('and installs the next revision of the same id', done['status'] == 'done'
          and done['result']['packageId'] == package_id and done['result']['revision'] == before + 1, done)
    check('still one method', len(client.get('/api/methods').get_json()['methods']) == 1)
    check('a method that is not theirs cannot be revised',
          start({'revise': {'packageId': 'u00000000_x', 'note': 'Anything at all.'}}).status_code == 404)


def test_refused_requests():
    print('what is not a request')
    clean()
    for body, why in (({'description': 'too short'}, 'a description too short'),
                      ({'description': 'x' * 9000}, 'one too long'),
                      ({'description': DESCRIPTION, 'pastedText': 'x' * 70000}, 'pasted text too long'),
                      ({'revise': {'packageId': 'u1_x', 'note': 'no'}}, 'a note too short'),
                      ({'revise': 'the first one'}, 'a revise that names nothing'),
                      ({}, 'nothing')):
        res = start(body)
        check(f'{why}: 422', res.status_code == 422 and res.get_json()['error'] == 'invalid', (res.status_code, res.get_json()))
    check('nothing was queued', client.get('/api/methods').get_json()['builds'] == [])

    print('limits')
    hold = threading.Event()

    def waiting(session):
        hold.wait(30)
        return scripted(session)
    build_worker.BUILDER = waiting
    first = start()
    again = start()
    check('one build at a time: 409 with the one running', again.status_code == 409 and again.get_json()['error'] == 'build_running'
          and again.get_json()['build']['id'] == first.get_json()['build']['id'], again.get_json())
    hold.set()
    settle()
    os.environ['PACKAGE_BUILDER_DAILY_LIMIT'] = '1'
    try:
        res = start()
        check('the daily limit: 429', res.status_code == 429 and res.get_json()['error'] == 'daily_limit', res.get_json())
        check('and the list says none are left', client.get('/api/methods').get_json()['limits']['remaining'] == 0)
    finally:
        os.environ.pop('PACKAGE_BUILDER_DAILY_LIMIT', None)
    saved = package_store.MAX_PACKAGES
    package_store.MAX_PACKAGES = 1
    try:
        res = start()
        check('the kept limit: 409, remove one first', res.status_code == 409 and res.get_json()['error'] == 'too_many_methods', res.get_json())
        mine = client.get('/api/methods').get_json()['methods'][0]['id']
        build_worker.BUILDER = scripted
        ok = start({'revise': {'packageId': mine, 'note': 'Revising is not one more.'}})
        check('revising one is not one more', ok.status_code == 202, ok.get_json())
        settle()
    finally:
        package_store.MAX_PACKAGES = saved
    os.environ.pop('ANTHROPIC_API_KEY')
    try:
        res = start()
        check('without a model key: 503, and why', res.status_code == 503 and res.get_json()['error'] == 'builder_unavailable'
              and res.get_json()['reason'] == 'no_model_key', res.get_json())
    finally:
        os.environ['ANTHROPIC_API_KEY'] = 'test-key'
    os.environ['PACKAGE_BUILDER'] = 'off'
    try:
        check('off: 403 on every build route', start().status_code == 403
              and client.get('/api/methods/builds/x').status_code == 403
              and client.post('/api/methods/builds/x/cancel').status_code == 403)
    finally:
        os.environ.pop('PACKAGE_BUILDER', None)


def test_failures():
    print('a build that fails')
    clean()
    build_worker.BUILDER = lambda s: {'ok': False, 'error': {'code': 'budget', 'message': 'It took too many tries.'}}
    build = start().get_json()['build']
    settle()
    failed = client.get(f"/api/methods/builds/{build['id']}").get_json()['build']
    check('says why, in words', failed['status'] == 'failed' and failed['error'] == {'code': 'budget', 'message': 'It took too many tries.'}, failed)
    check('and installs nothing', client.get('/api/methods').get_json()['methods'] == [])

    def broken(session):
        _pkg, files = tpp.package_for(session.user_id, 'stones', tpp.SCRATCH)
        return {'ok': True, 'files': {**files, 'frameworks/zz.yaml': 'name: [unclosed'}, 'name': 'x', 'summary': ''}
    build_worker.BUILDER = broken
    build = start().get_json()['build']
    settle()
    failed = client.get(f"/api/methods/builds/{build['id']}").get_json()['build']
    check('a builder that hands over a package that does not pass is checked anyway', failed['status'] == 'failed'
          and failed['error']['code'] == 'not_installable' and failed['error']['problems'], failed['error'])

    def raising(session):
        raise KeyError('slots')
    build_worker.BUILDER = raising
    build = start().get_json()['build']
    settle()
    failed = client.get(f"/api/methods/builds/{build['id']}").get_json()['build']
    check('a builder that raises is a failed build, with words for the athlete', failed['status'] == 'failed'
          and failed['error']['code'] == 'error' and 'KeyError' in failed['error']['detail'], failed['error'])
    build_worker.BUILDER = scripted
    build = start().get_json()['build']
    settle()
    check('and the worker is alive for the next one',
          client.get(f"/api/methods/builds/{build['id']}").get_json()['build']['status'] == 'done')
    build_worker.BUILDER = None
    build = start().get_json()['build']
    settle()
    check('no builder configured is a failed build too',
          client.get(f"/api/methods/builds/{build['id']}").get_json()['build']['status'] == 'failed')


def test_cancel():
    print('cancelled')
    clean()
    reached, go = threading.Event(), threading.Event()

    def slow(session):
        session.save(stage='writing', turns=1)
        reached.set()
        go.wait(30)
        session.save(stage='writing', turns=2)      # the next turn: stops here if asked to
        return scripted(session)
    build_worker.BUILDER = slow
    build = start().get_json()['build']
    reached.wait(30)
    res = client.post(f"/api/methods/builds/{build['id']}/cancel")
    check('a running build is asked to stop', res.status_code == 200 and res.get_json()['build']['status'] == 'running', res.get_json())
    go.set()
    settle()
    ended = client.get(f"/api/methods/builds/{build['id']}").get_json()['build']
    check('and stops at its next turn', ended['status'] == 'cancelled' and ended['error']['code'] == 'cancelled'
          and ended['progress']['turns'] == 2, ended)
    check('nothing was installed', client.get('/api/methods').get_json()['methods'] == [])
    check('cancelling it again answers as it ended',
          client.post(f"/api/methods/builds/{build['id']}/cancel").get_json()['build']['status'] == 'cancelled')

    row = build_store.create(ME, {'description': DESCRIPTION})          # queued, no worker kicked
    res = client.post(f"/api/methods/builds/{row['id']}/cancel")
    check('a waiting build is cancelled at once', res.get_json()['build']['status'] == 'cancelled')
    check('and one never started does not count against today',
          build_store.started_since(ME) == 1, build_store.started_since(ME))
    check('a build that is not theirs: 404', client.get('/api/methods/builds/nope').status_code == 404
          and client.post('/api/methods/builds/nope/cancel').status_code == 404)


def test_restart():
    print('a process that dies mid-build')
    clean()
    row = build_store.create(ME, {'description': DESCRIPTION})
    claimed = build_store.claim_next()
    check('claimed, running, first attempt', claimed['id'] == row['id'] and claimed['status'] == 'running' and claimed['attempts'] == 1)
    build_store.save(row['id'], transcript=[{'turn': 1}], draft_files={'philosophy.yaml': 'id: half\n'},
                     progress={'stage': 'writing', 'turns': 1})
    check('while its worker is alive nobody else takes it', build_store.claim_next() is None)
    check('and it is the athlete\'s open build', build_store.active(ME)['id'] == row['id'] and build_store.has_open())

    saved = build_store.LEASE_SECONDS
    build_store.LEASE_SECONDS = -1          # the heartbeat is stale: the worker is gone
    seen = {}

    def resuming(session):
        seen.update(transcript=list(session.transcript), draft=dict(session.draft_files), attempt=session.attempt)
        return scripted(session)
    build_worker.BUILDER = resuming
    try:
        api._BUILDS_RESUMED = False
        client.get('/api/methods')          # the first request of the new process takes it up
        build_worker.join(120)
    finally:
        build_store.LEASE_SECONDS = saved
    check('the next worker takes it up, from the first request', seen.get('attempt') == 2, seen.get('attempt'))
    check('with the transcript and the draft as last saved', seen.get('transcript') == [{'turn': 1}]
          and seen.get('draft') == {'philosophy.yaml': 'id: half\n'}, seen)
    check('and finishes it', build_store.get(ME, row['id'])['status'] == 'done')

    row = build_store.create(ME, {'description': DESCRIPTION})
    build_store.LEASE_SECONDS = -1
    try:
        build_store.claim_next()
        build_store.claim_next()
        gone = build_store.claim_next()
    finally:
        build_store.LEASE_SECONDS = saved
    ended = build_store.get(ME, row['id'])
    check('a build that died twice is stopped, and says so', gone is None and ended['status'] == 'failed'
          and ended['error']['code'] == 'interrupted', ended)


def test_slot_and_privacy():
    print('the heavy slot')
    clean()
    inside = threading.Event()
    release = threading.Event()
    real = package_store.check

    def slow_check(user_id, files, **kw):
        inside.set()
        release.wait(30)
        return real(user_id, files, **kw)
    package_store.check = slow_check
    build_worker.BUILDER = scripted
    try:
        start()
        inside.wait(30)
        check('is held while the draft is checked', not heavy.GATE.acquire(blocking=False))
        busy = client.post('/api/packages', json={'files': {'philosophy.yaml': 'id: x'}, 'dry_run': True})
        check('so a request that needs it answers busy, and does not wait', busy.status_code == 429 and busy.get_json()['busy'], busy.get_json())
    finally:
        release.set()
        package_store.check = real
    settle()
    got = heavy.GATE.acquire(blocking=False)
    check('and is free again afterwards', got)
    if got:
        heavy.GATE.release()

    print("another athlete")
    mine = client.get('/api/methods').get_json()['builds'][0]['id']
    check('reads none of the builds', build_store.recent('someone-else') == [] and build_store.get('someone-else', mine) is None
          and build_store.active('someone-else') is None and build_store.started_since('someone-else') == 0)
    check('and cannot cancel one', build_store.request_cancel('someone-else', mine) is None)


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
    name = f'package_builds_test_{os.getpid()}'
    with conn.cursor() as cur:
        cur.execute(f'CREATE DATABASE {name}')
    import importlib
    import src.db
    try:
        dsn = admin.rsplit('/', 1)[0] + f'/{name}?sslmode=disable'
        os.environ['DATABASE_URL'] = dsn
        importlib.reload(src.db)
        build_store._SCHEMA_READY = False
        package_store._SCHEMA_READY = False
        package_store._SETS.clear()
        package_store._NO_TABLE['until'] = 0.0
        check('before the table exists: nothing open, nothing recent, and nothing made',
              build_store.has_open() is False and build_store.recent(ME) == [] and build_store.started_since(ME) == 0
              and build_store.claim_next() is None)
        with psycopg2.connect(dsn) as c, c.cursor() as cur:
            cur.execute("SELECT to_regclass('public.package_builds')")
            check('a read made no table (production before migration 014)', cur.fetchone()[0] is None)
        row = build_store.create(ME, {'description': DESCRIPTION}, {'philosophy.yaml': 'id: x\n'})
        check('the first build makes it', row['status'] == 'queued' and row['draft_files'] == {'philosophy.yaml': 'id: x\n'}, row)
        check('open, the athlete\'s, counted', build_store.has_open() and build_store.active(ME)['id'] == row['id']
              and build_store.started_since(ME) == 1)
        claimed = build_store.claim_next()
        check('claimed once', claimed['id'] == row['id'] and claimed['attempts'] == 1 and build_store.claim_next() is None)
        build_store.save(row['id'], transcript=[{'turn': 1}], progress={'stage': 'writing', 'turns': 1}, usage={'out': 10})
        back = build_store.get(ME, row['id'])
        check('saved, with a heartbeat', back['transcript'] == [{'turn': 1}] and back['progress']['turns'] == 1
              and back['usage'] == {'out': 10} and back['heartbeat_at'] is not None, back)
        check('asked to stop', build_store.request_cancel(ME, row['id'])['cancel_requested'] is True
              and build_store.cancel_requested(row['id']))
        saved = build_store.LEASE_SECONDS
        build_store.LEASE_SECONDS = -1
        try:
            again = build_store.claim_next()
            check('a stale heartbeat is claimed again', again['id'] == row['id'] and again['attempts'] == 2)
            check('and after its attempts it is failed as interrupted', build_store.claim_next() is None
                  and build_store.get(ME, row['id'])['error']['code'] == 'interrupted')
        finally:
            build_store.LEASE_SECONDS = saved
        check('another athlete reads none of it', build_store.get('someone-else', row['id']) is None
              and build_store.recent('someone-else') == [])

        build_worker.BUILDER = scripted
        row = build_store.create(ME, {'description': DESCRIPTION})
        build_worker.drain()
        ended = build_store.get(ME, row['id'])
        check('a build runs to an installed method on Postgres', ended['status'] == 'done'
              and [p['id'] for p in package_store.list_packages(ME)] == [ended['result']['packageId']], ended.get('error'))
        with psycopg2.connect(dsn) as c, c.cursor() as cur:
            cur.execute("SELECT relrowsecurity FROM pg_class WHERE relname = 'package_builds'")
            check('row security is on (deny-by-default until 014 adds the policy)', cur.fetchone()[0] is True)
            cur.execute("SELECT 1 FROM information_schema.columns WHERE table_name = 'package_builds' "
                        "AND column_name = 'user_id'")
            check('account deletion finds it: a public table with a user_id', cur.fetchone() is not None)
    finally:
        src.db.close_conn()
        os.environ['DATABASE_URL'] = ''
        importlib.reload(src.db)
        build_store._SCHEMA_READY = False
        package_store._SCHEMA_READY = False
        with conn.cursor() as cur:
            cur.execute(f'DROP DATABASE IF EXISTS {name} WITH (FORCE)')
        conn.close()


def main() -> int:
    pkg = test_built()
    test_install_once()
    test_revise(pkg)
    test_refused_requests()
    test_failures()
    test_cancel()
    test_restart()
    test_slot_and_privacy()
    test_sql()
    if FAILURES:
        print(f'{len(FAILURES)} failed')
        return 1
    print('all passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
