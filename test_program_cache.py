#!/usr/bin/env python
"""The stored program is read from Postgres once per revision, not once per
request (src/db.get_user_program). On 2026-11-27 re-reading its ~600 KB on
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
    own.close()
    print(f"\n{len(FAILURES)} failed" if FAILURES else '\nall passed')
    return 1 if FAILURES else 0


if __name__ == '__main__':
    sys.exit(main())
