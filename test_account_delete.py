#!/usr/bin/env python
"""Deleting an account from the phone (`src/account.py`, `DELETE /api/account`).

The order tables are emptied in, the checks that run before anything is
removed, the route's answers, and — against a scratch database this test makes
and drops itself (never `training_test`, the dev database) — that every row of
the athlete goes, children first, and nobody else's does. Without a local
PostgreSQL the SQL half skips with exit 0:

    SUPABASE_URL='' .venv/bin/python test_account_delete.py
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

os.environ['SUPABASE_URL'] = ''
os.environ.pop('DATABASE_URL', None)
os.environ.pop('SUPABASE_SERVICE_ROLE_KEY', None)
sys.path.insert(0, str(Path(__file__).parent))

import api  # noqa: E402
from src import account  # noqa: E402

_failures: list[str] = []


def check(label: str, condition: bool, detail: str = '') -> None:
    if condition:
        print(f'  ok   {label}')
    else:
        print(f'  FAIL {label}' + (f' — {detail}' if detail else ''))
        _failures.append(label)


def test_order() -> None:
    print('deletion order')
    order = account.deletion_order(
        ['workouts', 'workout_matches', 'profiles', 'planned_sessions', 'program_versions'],
        [('workout_matches', 'workouts'),
         ('planned_sessions', 'program_versions'),
         ('workout_matches', 'auth_users_elsewhere'),   # a parent outside the set
         ('profiles', 'profiles')])                     # a self-reference
    check('every table once', sorted(order) == sorted(
        ['workouts', 'workout_matches', 'profiles', 'planned_sessions', 'program_versions']), str(order))
    check('a child before its parent',
          order.index('workout_matches') < order.index('workouts')
          and order.index('planned_sessions') < order.index('program_versions'), str(order))
    cyc = account.deletion_order(['a', 'b'], [('a', 'b'), ('b', 'a')])
    check('a cycle still lists both tables', sorted(cyc) == ['a', 'b'], str(cyc))


class _Resp:
    def __init__(self, status: int):
        self.status_code = status


def test_preconditions() -> None:
    print('before anything is removed')
    calls: list[str] = []
    saved = (account.delete_rows, account.revoke_integrations, account.requests.delete)
    account.delete_rows = lambda uid: calls.append('rows') or {'profiles': 1}
    account.revoke_integrations = lambda uid: calls.append('revoke')
    try:
        os.environ['SUPABASE_URL'] = 'https://example.supabase.co'
        try:
            account.delete_account('u1')
            check('no service-role key refuses', False)
        except account.AccountDeletionError as e:
            check('no service-role key answers 503', e.status == 503, str(e.status))
        check('…and removes nothing', calls == [], str(calls))

        os.environ['SUPABASE_SERVICE_ROLE_KEY'] = 'service-key'
        seen = {}

        def fake_delete(url, headers, timeout):
            seen.update(url=url, headers=headers)
            return _Resp(200)
        account.requests.delete = fake_delete
        counts = account.delete_account('u1')
        check('rows, then the Supabase user', calls == ['revoke', 'rows'] and counts == {'profiles': 1}, str(calls))
        check('the admin route for that user',
              seen.get('url') == 'https://example.supabase.co/auth/v1/admin/users/u1', seen.get('url', ''))
        check('with the service-role key',
              seen.get('headers', {}).get('Authorization') == 'Bearer service-key')

        os.environ['SUPABASE_SERVICE_ROLE_KEY'] = 'sb_secret_abc'
        seen.clear()
        account.requests.delete = fake_delete
        account.delete_account('u1')
        check('a secret key (sb_secret_) goes in apikey only',
              seen.get('headers') == {'apikey': 'sb_secret_abc'}, str(seen.get('headers')))
        os.environ['SUPABASE_SERVICE_ROLE_KEY'] = 'service-key'

        account.requests.delete = lambda url, headers, timeout: _Resp(404)
        account.delete_account('u1')
        check('a user already gone is not an error', True)

        account.requests.delete = lambda url, headers, timeout: _Resp(500)
        try:
            account.delete_account('u1')
            check('a refused deletion raises', False)
        except account.AccountDeletionError as e:
            check('a refused deletion answers 502', e.status == 502, str(e.status))

        def unreachable(url, headers, timeout):
            raise account.requests.ConnectionError('down')
        account.requests.delete = unreachable
        try:
            account.delete_account('u1')
            check('Supabase unreachable raises', False)
        except account.AccountDeletionError as e:
            check('Supabase unreachable answers 502', e.status == 502, str(e.status))
    finally:
        account.delete_rows, account.revoke_integrations, account.requests.delete = saved
        os.environ['SUPABASE_URL'] = ''
        os.environ.pop('SUPABASE_SERVICE_ROLE_KEY', None)


def test_route() -> None:
    print('DELETE /api/account')
    client = api.app.test_client()
    r = client.delete('/api/account')
    check('local dev is never deleted (409)', r.status_code == 409, str(r.status_code))

    # The handler as a signed-in athlete: require_auth is functools.wraps'd,
    # so the undecorated view runs with g.user_id set by hand.
    from flask import g
    view = api.app.view_functions['delete_account'].__wrapped__
    saved = account.delete_account
    try:
        account.delete_account = lambda uid: {'workouts': 3}
        with api.app.test_request_context('/api/account', method='DELETE'):
            g.user_id = 'athlete-1'
            body = view().get_json()
        check('a deletion answers deleted with its counts',
              body == {'deleted': True, 'rows': {'workouts': 3}}, str(body))

        def refuse(uid):
            raise account.AccountDeletionError('not configured', status=503)
        account.delete_account = refuse
        with api.app.test_request_context('/api/account', method='DELETE'):
            g.user_id = 'athlete-1'
            _, status = view()
        check('a refusal answers its status', status == 503, str(status))

        def crash(uid):
            raise RuntimeError('connection reset')
        account.delete_account = crash
        with api.app.test_request_context('/api/account', method='DELETE'):
            g.user_id = 'athlete-1'
            _, status = view()
        check('anything else answers 503', status == 503, str(status))
    finally:
        account.delete_account = saved


# ── SQL ───────────────────────────────────────────────────────────────────────

def sql_suite() -> None:
    admin = os.environ.get('TEST_ADMIN_DSN', 'postgresql://postgres@localhost:5432/postgres?sslmode=disable')
    if 'supabase' in admin or 'pooler' in admin:
        print('Refusing to run against what looks like a production database.')
        sys.exit(1)
    try:
        import psycopg2
        conn = psycopg2.connect(admin)
        conn.autocommit = True
    except Exception as exc:
        print(f'No local PostgreSQL available ({exc.__class__.__name__}) — skipping the SQL half.')
        return
    name = f'account_delete_test_{os.getpid()}'
    with conn.cursor() as cur:
        cur.execute(f'CREATE DATABASE {name}')
    try:
        dsn = admin.rsplit('/', 1)[0] + f'/{name}?sslmode=disable'
        os.environ['DATABASE_URL'] = dsn
        import importlib
        import src.db
        importlib.reload(src.db)                # it reads DATABASE_URL at import time
        importlib.reload(account)
        _sql_checks(dsn)
    finally:
        import src.db
        src.db.close_conn()
        os.environ.pop('DATABASE_URL', None)
        with conn.cursor() as cur:
            cur.execute(f'DROP DATABASE IF EXISTS {name} WITH (FORCE)')
        conn.close()


def _sql_checks(dsn: str) -> None:
    import psycopg2
    print('rows (PostgreSQL)')
    db = psycopg2.connect(dsn)
    db.autocommit = True
    with db.cursor() as cur:
        # A production-shaped slice: a parent and a child with a plain FK (no
        # cascade), a table keyed on user_id, one without the column, and a view.
        cur.execute('''
            CREATE TABLE workouts (id TEXT PRIMARY KEY, user_id TEXT NOT NULL);
            CREATE TABLE workout_matches (
                id SERIAL PRIMARY KEY, user_id TEXT NOT NULL,
                imported_workout_id TEXT NOT NULL REFERENCES workouts(id));
            CREATE TABLE profiles (user_id TEXT PRIMARY KEY, profile_data JSONB);
            CREATE TABLE exercises_catalog (id TEXT PRIMARY KEY);
            CREATE VIEW my_workouts AS SELECT * FROM workouts;
            INSERT INTO workouts VALUES ('w1', 'gone'), ('w2', 'gone'), ('w3', 'stays');
            INSERT INTO workout_matches (user_id, imported_workout_id)
                VALUES ('gone', 'w1'), ('gone', 'w2'), ('stays', 'w3');
            INSERT INTO profiles VALUES ('gone', '{}'), ('stays', '{}');
            INSERT INTO exercises_catalog VALUES ('squat');
        ''')
    counts = account.delete_rows('gone')
    check('every table of the athlete',
          counts == {'workouts': 2, 'workout_matches': 2, 'profiles': 1}, str(counts))
    with db.cursor() as cur:
        cur.execute("SELECT (SELECT count(*) FROM workouts), (SELECT count(*) FROM workout_matches),"
                    " (SELECT count(*) FROM profiles), (SELECT count(*) FROM exercises_catalog)")
        left = cur.fetchone()
    check("nobody else's rows", left == (1, 1, 1, 1), str(left))

    # A failure part-way rolls the whole deletion back.
    with db.cursor() as cur:
        cur.execute('''
            CREATE TABLE z_locked (user_id TEXT);
            CREATE FUNCTION refuse() RETURNS trigger LANGUAGE plpgsql AS
                $$ BEGIN RAISE EXCEPTION 'no'; END $$;
            CREATE TRIGGER z_refuse BEFORE DELETE ON z_locked FOR EACH ROW EXECUTE FUNCTION refuse();
            INSERT INTO z_locked VALUES ('stays');
        ''')
    try:
        account.delete_rows('stays')
        check('a failing table raises', False)
    except Exception:
        check('a failing table raises', True)
    with db.cursor() as cur:
        cur.execute("SELECT count(*) FROM profiles WHERE user_id = 'stays'")
        check('…and nothing was removed', cur.fetchone()[0] == 1)
    db.close()


if __name__ == '__main__':
    test_order()
    test_preconditions()
    test_route()
    sql_suite()
    print()
    if _failures:
        print(f'{len(_failures)} FAILED: ' + '; '.join(_failures))
        sys.exit(1)
    print('all passed')
