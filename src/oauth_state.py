"""Short-lived OAuth CSRF state, shared by every provider.

Replaces the local SQLite file oauth.py used (`data/oauth_state.db`). That file
sits on fly.io's ephemeral disk, so a machine restart between the redirect and
the callback loses the state and the athlete gets "possible CSRF" instead of a
connection. It also cannot hold a PKCE `code_verifier`, which Garmin needs and
which must not travel in a cookie.

Falls back to an in-process dict when there is no database, so the flow is
still exercisable in local dev.
"""
from __future__ import annotations

import secrets
from datetime import datetime, timedelta, timezone

TTL_SECONDS = 600

_TABLE_READY: bool | None = None

# Local-dev fallback: state -> (user_id, provider, code_verifier, created_at)
_memory: dict[str, tuple[str, str, str | None, datetime]] = {}


def _now() -> datetime:
    return datetime.now(timezone.utc)


def new_state() -> str:
    return secrets.token_urlsafe(32)


def _ensure_table(cur) -> bool:
    global _TABLE_READY
    if _TABLE_READY is not None:
        return _TABLE_READY
    try:
        cur.execute('''
            CREATE TABLE IF NOT EXISTS oauth_state (
                state         TEXT PRIMARY KEY,
                user_id       TEXT NOT NULL,
                provider      TEXT NOT NULL,
                code_verifier TEXT,
                created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
            )
        ''')
        cur.execute('CREATE INDEX IF NOT EXISTS idx_oauth_state_created_at '
                    'ON oauth_state (created_at)')
        _TABLE_READY = True
    except Exception:
        _TABLE_READY = False
    return _TABLE_READY


def put(state: str, user_id: str, provider: str, code_verifier: str | None = None) -> None:
    from src.db import _get_pg_conn
    conn = _get_pg_conn()
    if conn is None:
        _memory[state] = (user_id, provider, code_verifier, _now())
        return
    with conn.cursor() as cur:
        if not _ensure_table(cur):
            _memory[state] = (user_id, provider, code_verifier, _now())
            return
        # Opportunistic prune — no scheduler in this app to do it for us.
        cur.execute('DELETE FROM oauth_state WHERE created_at < %s',
                    (_now() - timedelta(seconds=TTL_SECONDS),))
        cur.execute(
            'INSERT INTO oauth_state (state, user_id, provider, code_verifier) '
            'VALUES (%s, %s, %s, %s) ON CONFLICT (state) DO NOTHING',
            (state, user_id, provider, code_verifier),
        )


def take(state: str, provider: str) -> tuple[str, str | None] | None:
    """Consume a state, returning (user_id, code_verifier).

    Delete-on-read: a state is single-use, so a replayed callback fails. Returns
    None when the state is unknown, expired, or belongs to another provider.
    """
    from src.db import _get_pg_conn
    conn = _get_pg_conn()

    if conn is None:
        entry = _memory.pop(state, None)
        if entry is None:
            return None
        user_id, stored_provider, verifier, created = entry
        if stored_provider != provider:
            return None
        if _now() - created > timedelta(seconds=TTL_SECONDS):
            return None
        return user_id, verifier

    with conn.cursor() as cur:
        if not _ensure_table(cur):
            return None
        cur.execute(
            'DELETE FROM oauth_state WHERE state = %s AND provider = %s AND created_at >= %s '
            'RETURNING user_id, code_verifier',
            (state, provider, _now() - timedelta(seconds=TTL_SECONDS)),
        )
        row = cur.fetchone()
    if not row:
        return None
    return row[0], row[1]
