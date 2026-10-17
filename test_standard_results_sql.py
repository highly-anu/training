"""src/standards_store.py against PostgreSQL, on a table shaped like production's.

Makes and drops its own database (never training_test, the dev database), and
skips with exit 0 without a local server:

    .venv/bin/python test_standard_results_sql.py

The table is built as supabase/schema.sql has it — UUID user id, none of
migrations/011's columns — because a store writer tested against a schema of
its own making stays green while production fails (CLAUDE.md, session logs).
"""
import os
import sys
import uuid

FAILED = []


def check(name: str, ok: bool, detail: str = '') -> None:
    print(f"  {'ok  ' if ok else 'FAIL'} {name}{'' if ok else f' — {detail}'}")
    if not ok:
        FAILED.append(name)


PRODUCTION_SHAPE = '''
CREATE TABLE performance_logs (
  id           BIGSERIAL PRIMARY KEY,
  user_id      UUID NOT NULL,
  benchmark_id TEXT NOT NULL,
  value        REAL NOT NULL,
  logged_at    TIMESTAMPTZ NOT NULL
)
'''


def main() -> None:
    admin = os.environ.get('TEST_ADMIN_DSN', 'postgresql://localhost:5432/postgres?sslmode=disable')
    if 'supabase' in admin or 'pooler' in admin:
        print('Refusing to run against what looks like a production database.')
        sys.exit(1)
    try:
        import psycopg2
        conn = psycopg2.connect(admin)
        conn.autocommit = True
    except Exception as exc:
        print(f'No local PostgreSQL available ({exc.__class__.__name__}) — skipping.')
        return
    name = f'standards_test_{os.getpid()}'
    with conn.cursor() as cur:
        cur.execute(f'CREATE DATABASE {name}')
    try:
        dsn = admin.rsplit('/', 1)[0] + f'/{name}?sslmode=disable'
        os.environ['DATABASE_URL'] = dsn
        import importlib
        import src.db
        importlib.reload(src.db)                # it reads DATABASE_URL at import time
        checks(dsn)
    finally:
        import src.db
        src.db.close_conn()
        with conn.cursor() as cur:
            cur.execute(f'DROP DATABASE IF EXISTS {name} WITH (FORCE)')
        conn.close()
    if FAILED:
        print(f'\n{len(FAILED)} failed')
        sys.exit(1)
    print('\nall standard results SQL checks passed')


def checks(dsn: str) -> None:
    import psycopg2
    from src import standards_store as store

    c = psycopg2.connect(dsn)
    c.autocommit = True
    with c.cursor() as cur:
        cur.execute(PRODUCTION_SHAPE)
        cur.execute("INSERT INTO performance_logs (user_id, benchmark_id, value, logged_at) VALUES "
                    "(%s, 'wod_fran_minutes', 6.0, '2026-05-01 19:00:00-07')", (USER,))
    print('store (PostgreSQL, production-shaped performance_logs)')

    old = store.list_results(USER)
    check('the lazy ensure adds 011 to the old table and reads its row',
          [e['value'] for e in old.get('wod_fran_minutes', [])] == [6.0], str(old))
    row = old['wod_fran_minutes'][0]
    check('an old row reads as manual, with no day of its own', row['source'] == 'manual' and row['loggedOn'] is None,
          str(row))

    a = store.add_result(USER, 'wod_fran_minutes', 4.9667, logged_at='2026-10-02T03:30:00+00:00',
                         logged_on='2026-10-01', note='PR', input_={'text': '4:58'})
    b = store.add_result(USER, 'wod_fran_minutes', 5.5, logged_at='2026-09-20T08:00:00+00:00', logged_on='2026-09-20')
    fran = store.list_results(USER)['wod_fran_minutes']
    check('results come back in the athlete\'s day order', [e['id'] for e in fran][-2:] == [b, a],
          str([(e['id'], e['loggedOn']) for e in fran]))
    got = store.get_result(USER, a)
    check('a result keeps its day, note and input', got['loggedOn'] == '2026-10-01' and got['note'] == 'PR'
          and got['input'] == {'text': '4:58'} and got['benchmarkId'] == 'wod_fran_minutes', str(got))

    check('an edit changes value, day and note', store.update_result(USER, a, {'value': 4.8, 'logged_on': '2026-10-03',
                                                                                'note': None}))
    got = store.get_result(USER, a)
    check('…and they read back', abs(got['value'] - 4.8) < 1e-6 and got['loggedOn'] == '2026-10-03'
          and got['note'] is None, str(got))
    other = str(uuid.uuid4())
    check("another athlete's result is not found to edit", not store.update_result(other, a, {'note': 'x'}))
    check("…nor to delete", not store.delete_result(other, a))
    check('one result is deleted, not the series', store.delete_result(USER, a)
          and len(store.list_results(USER)['wod_fran_minutes']) == 2)

    s1 = store.add_result(USER, 'wod_fran_minutes', 5.0, logged_at='2026-10-04T08:00:00+00:00',
                          logged_on='2026-10-04', source='session', session_uid='v1:2-Monday-0')
    dup_refused = False
    try:
        store.add_result(USER, 'wod_fran_minutes', 4.9, logged_at='2026-10-04T08:00:00+00:00',
                         logged_on='2026-10-04', source='session', session_uid='v1:2-Monday-0')
    except psycopg2.errors.UniqueViolation:
        dup_refused = True
    check('one result per standard per session (the partial unique index)', s1 > 0 and dup_refused)

    raised = False
    try:
        store.add_result(USER, 'wod_fran_minutes', None, logged_at='2026-10-04', logged_on='2026-10-04')
    except Exception:
        raised = True
    check('a failed write raises instead of reporting success', raised)

    check('the old route still deletes a whole series', store.delete_series(USER, 'wod_fran_minutes') == 3)
    c.close()


USER = str(uuid.uuid4())

if __name__ == '__main__':
    main()
