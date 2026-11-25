"""Shared links: one row a link (migrations/015_shares.sql).

A link is a token and what it shows — a snapshot taken when it was shared
(src/sharing.py builds it). `get` is the public read: by token alone, through
the API's own connection, for a link that is not revoked. Everything else
takes the sharer's user id. Without a database (local dev) the rows are JSON
files under the package store's base directory.
"""
from __future__ import annotations

import json
import os
import secrets
import threading
import time

from src import package_store

MAX_LIVE = 50
KINDS = ('package', 'program', 'session')

_SCHEMA_READY = False
_LOCK = threading.RLock()

_TABLE = '''
CREATE TABLE IF NOT EXISTS shares (
    token       TEXT        PRIMARY KEY,
    user_id     TEXT        NOT NULL,
    kind        TEXT        NOT NULL,
    title       TEXT,
    payload     JSONB       NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revoked_at  TIMESTAMPTZ
)
'''
_INDEX = 'CREATE INDEX IF NOT EXISTS shares_user_idx ON shares (user_id) WHERE revoked_at IS NULL'
_RLS = 'ALTER TABLE shares ENABLE ROW LEVEL SECURITY'


class StoreError(Exception):
    """A read or write that did not happen (the routes answer 503)."""


class TooMany(Exception):
    """The sharer already has MAX_LIVE links."""


def _conn():
    from src import db
    return db.new_conn(autocommit=True)


def _ensure_schema(conn) -> None:
    """The table where 015 has not run: row security on and no policy
    (deny-by-default); the migration adds the per-user policy."""
    global _SCHEMA_READY
    if _SCHEMA_READY:
        return
    with conn.cursor() as cur:
        cur.execute(_TABLE)
        cur.execute(_INDEX)
        cur.execute(_RLS)
    _SCHEMA_READY = True


def _file() -> str:
    return os.path.join(package_store.base_dir(), '_shares.json')


def _file_rows() -> dict:
    try:
        with open(_file(), encoding='utf-8') as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def _write_file_rows(rows: dict) -> None:
    os.makedirs(package_store.base_dir(), exist_ok=True)
    tmp = _file() + f'.{os.getpid()}.{threading.get_ident()}.tmp'
    with open(tmp, 'w', encoding='utf-8') as fh:
        json.dump(rows, fh)
    os.replace(tmp, _file())


def _now() -> str:
    return time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())


def _listed(row: dict) -> dict:
    return {'token': row['token'], 'kind': row['kind'], 'title': row.get('title'),
            'createdAt': str(row.get('created_at') or '') or None}


def create(user_id: str, kind: str, title: str | None, payload: dict) -> dict:
    """A new link → {token, kind, title, createdAt}. Raises TooMany at the
    sharer's cap, StoreError when the write fails."""
    if kind not in KINDS:
        raise ValueError(f'unknown kind {kind!r}')
    token = secrets.token_urlsafe(16)
    conn = _conn()
    if conn is None:
        with _LOCK:
            rows = _file_rows()
            if sum(1 for r in rows.values() if r['user_id'] == str(user_id) and not r.get('revoked_at')) >= MAX_LIVE:
                raise TooMany()
            rows[token] = {'token': token, 'user_id': str(user_id), 'kind': kind, 'title': title,
                           'payload': payload, 'created_at': _now(), 'revoked_at': None}
            _write_file_rows(rows)
            return _listed(rows[token])
    try:
        _ensure_schema(conn)
        with conn.cursor() as cur:
            cur.execute('SELECT COUNT(*) FROM shares WHERE user_id = %s AND revoked_at IS NULL', (str(user_id),))
            if cur.fetchone()[0] >= MAX_LIVE:
                raise TooMany()
            cur.execute('INSERT INTO shares (token, user_id, kind, title, payload) VALUES (%s, %s, %s, %s, %s::jsonb) '
                        'RETURNING created_at', (token, str(user_id), kind, title, json.dumps(payload, default=str)))
            return _listed({'token': token, 'kind': kind, 'title': title, 'created_at': cur.fetchone()[0]})
    except TooMany:
        raise
    except Exception as e:
        raise StoreError(f'shares not written: {e}') from e
    finally:
        conn.close()


def get(token: str) -> dict | None:
    """A live link by its token → {token, userId, kind, title, payload,
    createdAt}; None for an unknown or revoked one."""
    from src import db
    conn = db.read_conn()
    if conn is None:
        row = _file_rows().get(str(token))
        if not row or row.get('revoked_at'):
            return None
        return {**_listed(row), 'userId': row['user_id'], 'payload': row['payload']}
    try:
        import psycopg2.errors
        with conn.cursor() as cur:
            try:
                cur.execute('SELECT user_id, kind, title, payload, created_at FROM shares '
                            'WHERE token = %s AND revoked_at IS NULL', (str(token),))
            except psycopg2.errors.UndefinedTable:
                return None
            row = cur.fetchone()
    except Exception as e:
        raise StoreError(f'shares not read: {e}') from e
    if not row:
        return None
    return {'token': str(token), 'userId': row[0], 'kind': row[1], 'title': row[2], 'payload': row[3],
            'createdAt': str(row[4])}


def list_for(user_id: str) -> list[dict]:
    """The sharer's live links, newest first, without their payloads."""
    from src import db
    conn = db.read_conn()
    if conn is None:
        rows = [r for r in _file_rows().values() if r['user_id'] == str(user_id) and not r.get('revoked_at')]
        return [_listed(r) for r in sorted(rows, key=lambda r: r['created_at'], reverse=True)]
    try:
        import psycopg2.errors
        with conn.cursor() as cur:
            try:
                cur.execute('SELECT token, kind, title, created_at FROM shares '
                            'WHERE user_id = %s AND revoked_at IS NULL ORDER BY created_at DESC', (str(user_id),))
            except psycopg2.errors.UndefinedTable:
                return []
            return [_listed({'token': t, 'kind': k, 'title': n, 'created_at': at}) for t, k, n, at in cur.fetchall()]
    except Exception as e:
        raise StoreError(f'shares not read: {e}') from e


def revoke(user_id: str, token: str) -> bool:
    """Revoke one of the sharer's links; False when it is not theirs or
    already revoked."""
    conn = _conn()
    if conn is None:
        with _LOCK:
            rows = _file_rows()
            row = rows.get(str(token))
            if not row or row['user_id'] != str(user_id) or row.get('revoked_at'):
                return False
            row['revoked_at'] = _now()
            _write_file_rows(rows)
            return True
    try:
        _ensure_schema(conn)
        with conn.cursor() as cur:
            cur.execute('UPDATE shares SET revoked_at = NOW() WHERE token = %s AND user_id = %s AND revoked_at IS NULL',
                        (str(token), str(user_id)))
            return cur.rowcount > 0
    except Exception as e:
        raise StoreError(f'shares not written: {e}') from e
    finally:
        conn.close()
