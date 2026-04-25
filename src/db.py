"""Database client for Supabase PostgreSQL.

In production, connects to Supabase via DATABASE_URL.
In local dev (no DATABASE_URL), falls back to JSON file storage in data/user_profiles/.
"""
from __future__ import annotations

import os
import json
from pathlib import Path
from typing import Any

DATABASE_URL = os.environ.get('DATABASE_URL', '')

# Use psycopg2 for production Supabase connection
_pg_conn = None
_pg_dsn: str = ''

if DATABASE_URL:
    try:
        import psycopg2
        import psycopg2.extras
        # Supabase pooler requires SSL
        _pg_dsn = DATABASE_URL if 'sslmode=' in DATABASE_URL else DATABASE_URL + ('&' if '?' in DATABASE_URL else '?') + 'sslmode=require'
        _pg_conn = psycopg2.connect(_pg_dsn)
        _pg_conn.autocommit = True
        print("Connected to Supabase PostgreSQL")
    except Exception as e:
        print(f"Warning: Could not connect to PostgreSQL: {e}")
        _pg_conn = None


def _get_pg_conn():
    """Return a live PostgreSQL connection, reconnecting if the link is broken."""
    global _pg_conn
    if not _pg_dsn:
        return None
    import psycopg2
    # Check if existing connection is still alive
    if _pg_conn is not None:
        try:
            _pg_conn.cursor().execute('SELECT 1')
            return _pg_conn
        except Exception:
            try:
                _pg_conn.close()
            except Exception:
                pass
            _pg_conn = None
    # Reconnect
    try:
        _pg_conn = psycopg2.connect(_pg_dsn)
        _pg_conn.autocommit = True
        return _pg_conn
    except Exception as e:
        print(f"Warning: Could not reconnect to PostgreSQL: {e}")
        _pg_conn = None
        return None

# Local dev fallback: JSON file storage
_local_storage_dir = Path(__file__).parent.parent / 'data' / 'user_profiles'


def get_conn():
    """Get the database connection. Raises exception if not connected to PostgreSQL."""
    if not _pg_conn:
        raise Exception("No database connection available. Set DATABASE_URL to connect to PostgreSQL.")
    return _pg_conn


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
    """Save user's current program to database or local file."""
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
