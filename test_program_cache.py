#!/usr/bin/env python
"""The stored program is read from Postgres once per revision, not once per
request (src/db.get_user_program); so is each archived version
(program_history._version_envelopes), and the watch's headline is picked out
by Postgres (health_store.get_progression_headline). The workout summaries,
the matched workouts and the session logs are kept under a fingerprint of
the athlete's rows (health_store._kept). On 2026-11-27 re-reading its ~600 KB on
nearly every route had used the month's database egress.

Runs on a database it makes and drops; skips (exit 0) without a local server.
`TEST_ADMIN_DSN` points it at one.

Run: .venv/bin/python test_program_cache.py
"""
from __future__ import annotations

import json
import os
import sys
import uuid

ADMIN = os.environ.get('TEST_ADMIN_DSN', 'postgresql://localhost:5432/postgres?sslmode=disable')
NAME = f'tc_program_cache_{uuid.uuid4().hex[:8]}'
FAILURES: list[str] = []


def check(label: str, condition: bool, detail='') -> None:
    print(f"  {'ok  ' if condition else 'FAIL'} {label}{'' if condition else f' — {detail}'}")
    if not condition:
        FAILURES.append(label)


def main() -> int:
    if 'supabase' in ADMIN or 'pooler' in ADMIN:
        print('Refusing to run against what looks like a production database.')
        return 1
    try:
        import psycopg2
        admin = psycopg2.connect(ADMIN)
    except Exception as e:
        print(f'skipped: no local Postgres ({e})')
        return 0
    admin.autocommit = True
    admin.cursor().execute(f'CREATE DATABASE {NAME}')
    try:
        return run(psycopg2)
    finally:
        from src import db
        db.close_conn()
        admin.cursor().execute(f'DROP DATABASE IF EXISTS {NAME} WITH (FORCE)')
        admin.close()


def run(psycopg2) -> int:
    base = ADMIN.replace('/postgres', f'/{NAME}', 1)
    own = psycopg2.connect(base)
    own.autocommit = True
    cur = own.cursor()
    cur.execute('CREATE TABLE user_programs (user_id TEXT PRIMARY KEY, program_data JSONB NOT NULL, '
                'updated_at TIMESTAMPTZ DEFAULT NOW())')
    os.environ['SUPABASE_URL'] = ''
    os.environ['DATABASE_URL'] = base
    from src import db

    # Count what the module asks the database for.
    asked: list[str] = []
    real = db._get_pg_conn

    class Cursor:
        def __init__(self, c): self.c = c
        def __enter__(self): self.c.__enter__(); return self
        def __exit__(self, *a): return self.c.__exit__(*a)
        def execute(self, sql, *a): asked.append(sql); return self.c.execute(sql, *a)
        def __getattr__(self, name): return getattr(self.c, name)

    class Conn:
        def __init__(self, c): self.c = c
        def cursor(self, *a, **k): return Cursor(self.c.cursor(*a, **k))
        def __getattr__(self, name): return getattr(self.c, name)

    db._get_pg_conn = lambda: Conn(real())
    full = lambda: sum('program_data::text' in q for q in asked)

    check('no program: None', db.get_user_program('a') is None)
    db.save_user_program('a', {'currentProgram': {'weeks': [{'n': 1}]}, 'x': 1})
    first = db.get_user_program('a')
    check('the saved program reads back', first == {'currentProgram': {'weeks': [{'n': 1}]}, 'x': 1}, first)
    n = full()
    second = db.get_user_program('a')
    check('a second read asks only for the revision', full() == n and second == first, asked[-2:])
    second['currentProgram']['weeks'].append('mine')
    check("a caller's changes stay its own", db.get_user_program('a') == first)

    db.save_user_program('a', {'x': 2})
    check('a save is read at once', db.get_user_program('a') == {'x': 2})

    # A write that never touches updated_at — a script, a test, another process.
    cur.execute('UPDATE user_programs SET program_data = %s WHERE user_id = %s', (json.dumps({'x': 3}), 'a'))
    check("another writer's change is read at once", db.get_user_program('a') == {'x': 3})

    db.save_user_program('b', {'who': 'b'})
    check('athletes never share', db.get_user_program('b') == {'who': 'b'} and db.get_user_program('a') == {'x': 3})

    cur.execute("DELETE FROM user_programs WHERE user_id = 'a'")
    check('a deleted program is gone', db.get_user_program('a') is None)
    check('  and forgotten', 'a' not in db._PROGRAM_CACHE)

    for i in range(db._PROGRAM_CACHE_SIZE + 5):
        db.save_user_program(f'u{i}', {'i': i})
        db.get_user_program(f'u{i}')
    check('the cache is bounded', len(db._PROGRAM_CACHE) <= db._PROGRAM_CACHE_SIZE, len(db._PROGRAM_CACHE))
    db._get_pg_conn = real
    versions(cur)
    headline(cur)
    kept_reads(cur)
    own.close()
    print(f"\n{len(FAILURES)} failed" if FAILURES else '\nall passed')
    return 1 if FAILURES else 0


def versions(cur) -> None:
    """Archived versions (program_history.session_lookup) are read once each."""
    from src import program_history as ph
    cur.execute('CREATE TABLE program_versions (user_id TEXT, id TEXT, program_data JSONB NOT NULL, '
                'PRIMARY KEY (user_id, id))')
    for vid in ('v1', 'v2'):
        cur.execute('INSERT INTO program_versions VALUES (%s, %s, %s)',
                    ('a', vid, json.dumps({'currentProgram': {'weeks': [{'v': vid}]}})))
    asked: list[str] = []
    real = ph._query
    ph._query = lambda sql, params: (asked.append(sql), real(sql, params))[1]
    bodies = lambda: sum('AS body' in q for q in asked)
    try:
        first = ph._version_envelopes('a', ['v1', 'v2', 'nope'])
        check('each named version the athlete has', sorted(first) == ['v1', 'v2'], sorted(first))
        check('  as stored', first['v1'] == {'currentProgram': {'weeks': [{'v': 'v1'}]}}, first['v1'])
        n = bodies()
        again = ph._version_envelopes('a', ['v1', 'v2'])
        check('a second read fetches no body', bodies() == n and again == first)
        again['v1']['currentProgram']['weeks'].append('mine')
        check("a caller's changes stay its own", ph._version_envelopes('a', ['v1']) == {'v1': first['v1']})
        cur.execute("UPDATE program_versions SET program_data = %s WHERE id = 'v1'", (json.dumps({'x': 1}),))
        n = bodies()
        got = ph._version_envelopes('a', ['v1', 'v2'])
        check('a refreshed snapshot is read again', got['v1'] == {'x': 1} and got['v2'] == first['v2'], got['v1'])
        check('  and only that one', bodies() == n + 1 and "'v2'" not in str(asked[-1:]))
        check("another athlete's version is not theirs", ph._version_envelopes('b', ['v1']) == {})
        ph._ENVELOPES.clear()
        ph._ENVELOPES_MAX_BYTES, kept = 10, ph._ENVELOPES_MAX_BYTES
        ph._version_envelopes('a', ['v1', 'v2'])
        ph._ENVELOPES_MAX_BYTES = kept
        check('the cache is bounded by size', len(ph._ENVELOPES) <= 1, len(ph._ENVELOPES))
    finally:
        ph._query = real


def headline(cur) -> None:
    """The watch's headline is picked out by Postgres, not read with its document."""
    from src import health_store
    cur.execute('CREATE TABLE IF NOT EXISTS progression_snapshots (id SERIAL PRIMARY KEY, user_id TEXT NOT NULL, '
                'period_key TEXT NOT NULL, period_type TEXT NOT NULL, generated_at TIMESTAMP NOT NULL, '
                'session_hash TEXT NOT NULL, data JSONB NOT NULL, UNIQUE (user_id, period_key, period_type))')
    check('no snapshot: no headline', health_store.get_progression_headline('a', 'k') is None)
    put = lambda key, data: cur.execute(
        'INSERT INTO progression_snapshots (user_id, period_key, period_type, generated_at, session_hash, data) '
        "VALUES ('a', %s, 'program', NOW(), 'hash', %s::jsonb)", (key, json.dumps(data)))
    put('k', {'methodologies': [{'headlineSummary': {'label': 'Load', 'text': 'Squat 100kg'}, 'big': 'x' * 5000}]})
    check('the lead methodology\'s headline', health_store.get_progression_headline('a', 'k')
          == {'label': 'Load', 'text': 'Squat 100kg'}, health_store.get_progression_headline('a', 'k'))
    put('k2', {'methodologies': []})
    check('a document without one: None', health_store.get_progression_headline('a', 'k2') is None)


def kept_reads(cur) -> None:
    """health_store._kept: a reader's answer per athlete, for as long as the
    athlete's rows in the table are what they were."""
    from src import health_store as hs
    calls = []
    load = lambda: (calls.append(1), [{'n': len(calls)}])[1]
    check('no table: read every time, nothing kept',
          hs._kept('a', 'session_logs', ('t',), load) == [{'n': 1}]
          and hs._kept('a', 'session_logs', ('t',), load) == [{'n': 2}] and not hs._KEPT)
    cur.execute('CREATE TABLE session_logs (user_id TEXT, session_key TEXT, session_uid TEXT, note TEXT)')
    check('no rows: an empty answer is never kept',
          hs._session_log_rows('a') == [] and not hs._KEPT)
    cur.execute("INSERT INTO session_logs VALUES ('a', '1-Monday-0', 'v:w0-Monday-0', 'one'), ('b', 'x', NULL, 'theirs')")
    rows = hs._session_log_rows('a')
    check("the athlete's rows", [r['note'] for r in rows] == ['one'], rows)
    calls.clear()
    first = hs._kept('a', 'session_logs', ('t',), load)
    second = hs._kept('a', 'session_logs', ('t',), load)
    check('a second read is from memory', len(calls) == 1 and second == first, calls)
    second[0]['n'] = 'mine'
    check("a caller's changes stay its own", hs._kept('a', 'session_logs', ('t',), load) == first)
    for label, sql in (('an update', "UPDATE session_logs SET note = 'two' WHERE user_id = 'a'"),
                       ('an insert', "INSERT INTO session_logs VALUES ('a', '1-Tuesday-0', NULL, 'three')"),
                       ('a delete', "DELETE FROM session_logs WHERE user_id = 'a' AND note = 'three'")):
        before = len(calls)
        cur.execute(sql)
        hs._kept('a', 'session_logs', ('t',), load)
        check(f'{label} is read at once', len(calls) == before + 1)
    check('  and the rows are the new ones', [r['note'] for r in hs._session_log_rows('a')] == ['two'])
    before = len(calls)
    cur.execute("UPDATE session_logs SET note = 'still theirs' WHERE user_id = 'b'")
    hs._kept('a', 'session_logs', ('t',), load)
    check("another athlete's write reads nothing again", len(calls) == before)
    hs._KEPT.clear()
    hs._KEPT_MAX_BYTES, was = 10, hs._KEPT_MAX_BYTES
    hs._kept('a', 'session_logs', ('t',), load)
    hs._kept('a', 'session_logs', ('u',), load)
    hs._KEPT_MAX_BYTES = was
    check('the cache is bounded by size', len(hs._KEPT) <= 1, len(hs._KEPT))


if __name__ == '__main__':
    sys.exit(main())
