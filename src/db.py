"""Postgres connection helper for Supabase.

Used by profile and program endpoints. Falls back gracefully when DATABASE_URL
is not set (local dev without Supabase).
"""
from __future__ import annotations

import os

DATABASE_URL = os.environ.get('DATABASE_URL', '')


def get_conn():
    """Return a psycopg2 connection using DATABASE_URL.

    Raises RuntimeError if DATABASE_URL is not configured.
    The caller is responsible for closing the connection (use as context manager).
    """
    if not DATABASE_URL:
        raise RuntimeError('DATABASE_URL environment variable not set — Supabase Postgres not configured')
    import psycopg2
    import psycopg2.extras
    conn = psycopg2.connect(DATABASE_URL, cursor_factory=psycopg2.extras.RealDictCursor)
    return conn
