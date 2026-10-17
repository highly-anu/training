"""Database client for Supabase PostgreSQL.

In production, connects to Supabase via DATABASE_URL.
In local dev (no DATABASE_URL), falls back to JSON file storage in data/user_profiles/.
"""
from __future__ import annotations

import os
import json
import threading
import time
from pathlib import Path
from typing import Any

DATABASE_URL = os.environ.get('DATABASE_URL', '')

# One connection per thread. gunicorn runs a pool of request threads
# (gthread, see the Dockerfile) beside the Garmin drain thread and the async
# parse threads; a single shared connection let one thread's `with conn:`
# commit or roll back another's work, and it serialised every query.
_local = threading.local()
_pg_dsn: str = ''

if DATABASE_URL:
    try:
        import psycopg2
        import psycopg2.extras
        # Supabase pooler requires SSL
        _pg_dsn = DATABASE_URL if 'sslmode=' in DATABASE_URL else DATABASE_URL + ('&' if '?' in DATABASE_URL else '?') + 'sslmode=require'
        _local.conn = psycopg2.connect(_pg_dsn)
        _local.conn.autocommit = True
        print("Connected to Supabase PostgreSQL")
    except Exception as e:
        print(f"Warning: Could not connect to PostgreSQL: {e}")
        _local.conn = None


# A link that was used this recently is handed out without a `SELECT 1`.
# Until 2026-10-17 the app ran in sjc and the database in eu-west-3, ~150 ms
# a round trip, and pinging on each hand-out cost as much as the queries did.
# Both are in Paris now, but a ping is still a round trip per hand-out. A link
# psycopg2 saw fail is marked `closed` and still reconnects at once.
_IDLE_PING_SECONDS = 30


def _thread_conn(attr: str):
    """This thread's live connection under `attr`, reconnecting if the link is broken."""
    if not _pg_dsn:
        return None
    import psycopg2
    conn = getattr(_local, attr, None)
    now = time.monotonic()
    if conn is not None and not conn.closed:
        if now - getattr(_local, attr + '_used', 0.0) < _IDLE_PING_SECONDS:
            setattr(_local, attr + '_used', now)
            return conn
        try:
            conn.cursor().execute('SELECT 1')
            setattr(_local, attr + '_used', now)
            return conn
        except Exception:
            pass
    if conn is not None:
        try:
            conn.close()
        except Exception:
            pass
        setattr(_local, attr, None)
    try:
        conn = psycopg2.connect(_pg_dsn)
        conn.autocommit = True
        setattr(_local, attr, conn)
        setattr(_local, attr + '_used', now)
        return conn
    except Exception as e:
        print(f"Warning: Could not reconnect to PostgreSQL: {e}")
        setattr(_local, attr, None)
        return None


def _get_pg_conn():
    """This thread's live PostgreSQL connection, reconnecting if the link is broken."""
    return _thread_conn('conn')


def read_conn():
    """A second per-thread autocommit connection, for reads that may run
    inside a caller's `with get_conn()` block (a nested `with` on the shared
    connection returns nothing and swallows why). Reused across calls, unlike
    `new_conn()`: opening one costs a TLS and auth handshake (~0.7 s when the
    app ran in sjc), and Log ▸ Linking opened ten per request. Never close
    it, and never turn autocommit off on it; None without a database."""
    return _thread_conn('read_conn')


def close_conn():
    """Close this thread's connections, if it has any."""
    for attr in ('conn', 'read_conn'):
        conn = getattr(_local, attr, None)
        setattr(_local, attr, None)
        if conn is not None:
            try:
                conn.close()
            except Exception:
                pass

# Local dev fallback: JSON file storage
_local_storage_dir = Path(__file__).parent.parent / 'data' / 'user_profiles'


def get_conn():
    """Get the database connection, reconnecting if the link is broken."""
    conn = _get_pg_conn()
    if conn is None:
        raise Exception("No database connection available. Set DATABASE_URL to connect to PostgreSQL.")
    return conn


def new_conn(autocommit: bool = False):
    """A connection of one's own, for work that needs a real transaction.

    `get_conn()` hands out the thread's connection with `autocommit = True`,
    and everything that runs on the thread shares it: flipping autocommit off
    on it to get a transaction would enrol an unrelated INSERT made later on
    the same thread, to be rolled back by our `except` or committed early by
    our `commit()`. So callers that need atomicity take a fresh connection
    instead and close it when they are done.

    Returns None when there is no database configured, so a caller in local-dev
    mode can degrade rather than raise.
    """
    if not _pg_dsn:
        return None
    import psycopg2
    try:
        conn = psycopg2.connect(_pg_dsn)
        conn.autocommit = autocommit
        return conn
    except Exception as e:
        print(f"Warning: could not open a new PostgreSQL connection: {e}")
        return None


def _ensure_local_storage():
    """Create local storage directory if it doesn't exist."""
    _local_storage_dir.mkdir(parents=True, exist_ok=True)


def _get_profile_path(user_id: str) -> Path:
    """Get the local file path for a user's profile."""
    # Sanitize user_id for filesystem
    safe_id = user_id.replace('/', '_').replace('\\', '_')
    return _local_storage_dir / f'{safe_id}.json'


def get_user_profile(user_id: str) -> dict[str, Any] | None:
    """Fetch user profile from database or local file."""
    conn = _get_pg_conn()
    if conn:
        try:
            import psycopg2.extras
            with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                cur.execute(
                    'SELECT profile_data FROM profiles WHERE user_id = %s',
                    (user_id,)
                )
                row = cur.fetchone()
                return dict(row['profile_data']) if row else None
        except Exception as e:
            print(f"Error fetching profile from database: {e}")
            return None
    else:
        # Local dev mode
        _ensure_local_storage()
        profile_path = _get_profile_path(user_id)
        if profile_path.exists():
            try:
                with open(profile_path, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except Exception as e:
                print(f"Error reading local profile: {e}")
                return None
        return None


def save_user_profile(user_id: str, profile_data: dict[str, Any]) -> None:
    """Save user profile to database or local file."""
    conn = _get_pg_conn()
    if conn:
        try:
            with conn.cursor() as cur:
                cur.execute('''
                    INSERT INTO profiles (user_id, profile_data, updated_at)
                    VALUES (%s, %s, NOW())
                    ON CONFLICT (user_id)
                    DO UPDATE SET profile_data = EXCLUDED.profile_data, updated_at = NOW()
                ''', (user_id, json.dumps(profile_data)))
        except Exception as e:
            print(f"Error saving profile to database: {e}")
            raise
    else:
        # Local dev mode
        _ensure_local_storage()
        profile_path = _get_profile_path(user_id)
        try:
            with open(profile_path, 'w', encoding='utf-8') as f:
                json.dump(profile_data, f, indent=2)
        except Exception as e:
            print(f"Error writing local profile: {e}")
            raise


def get_program_revision(user_id: str) -> str | None:
    """Opaque revision token for the stored program (its updated_at).

    Clients echo this back when saving so a write based on a stale read can be
    rejected instead of silently clobbering a newer program.
    """
    conn = _get_pg_conn()
    if conn:
        try:
            with conn.cursor() as cur:
                cur.execute('SELECT updated_at FROM user_programs WHERE user_id = %s',
                            (user_id,))
                row = cur.fetchone()
                return row[0].isoformat() if row and row[0] else None
        except Exception as e:
            print(f"Error fetching program revision: {e}")
            return None
    _ensure_local_storage()
    safe_id = user_id.replace('/', '_').replace('\\', '_')
    program_path = _local_storage_dir / f'{safe_id}_program.json'
    if program_path.exists():
        return str(program_path.stat().st_mtime)
    return None


def get_user_program(user_id: str) -> dict[str, Any] | None:
    """Fetch user's current program from database or local file."""
    conn = _get_pg_conn()
    if conn:
        try:
            import psycopg2.extras
            with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                cur.execute(
                    'SELECT program_data FROM user_programs WHERE user_id = %s',
                    (user_id,)
                )
                row = cur.fetchone()
                return dict(row['program_data']) if row else None
        except Exception as e:
            print(f"Error fetching program from database: {e}")
            return None
    else:
        # Local dev mode - store in same directory with _program suffix
        _ensure_local_storage()
        safe_id = user_id.replace('/', '_').replace('\\', '_')
        program_path = _local_storage_dir / f'{safe_id}_program.json'
        if program_path.exists():
            try:
                with open(program_path, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except Exception as e:
                print(f"Error reading local program: {e}")
                return None
        return None


def save_user_program(user_id: str, program_data: dict[str, Any]) -> None:
    """Save user's current program to database or local file.

    `currentProgram.phase_summary` is derived from the weeks on every read
    (src/phase_summary.py) and is never stored, so a stale copy cannot outlive
    a swap or an adjustment.
    """
    cp = program_data.get('currentProgram') if isinstance(program_data, dict) else None
    if isinstance(cp, dict) and 'phase_summary' in cp:
        program_data = {**program_data,
                        'currentProgram': {k: v for k, v in cp.items() if k != 'phase_summary'}}
    conn = _get_pg_conn()
    if conn:
        try:
            with conn.cursor() as cur:
                cur.execute('''
                    INSERT INTO user_programs (user_id, program_data, updated_at)
                    VALUES (%s, %s, NOW())
                    ON CONFLICT (user_id)
                    DO UPDATE SET program_data = EXCLUDED.program_data, updated_at = NOW()
                ''', (user_id, json.dumps(program_data)))
        except Exception as e:
            print(f"Error saving program to database: {e}")
            raise
    else:
        # Local dev mode
        _ensure_local_storage()
        safe_id = user_id.replace('/', '_').replace('\\', '_')
        program_path = _local_storage_dir / f'{safe_id}_program.json'
        try:
            with open(program_path, 'w', encoding='utf-8') as f:
                json.dump(program_data, f, indent=2)
        except Exception as e:
            print(f"Error writing local program: {e}")
            raise
