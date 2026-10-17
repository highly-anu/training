"""Deleting an account: every row the athlete owns, then the Supabase user.

The iOS app can create an account (Sign in with Apple, an email code), so the
App Store requires it to delete one too (guideline 5.1.1(v)). The tables are
found, not listed: every table in `public` with a `user_id` column, so a table
added next year is covered without anyone remembering this file. They are
emptied children first (by their foreign keys) in one transaction, and the
Supabase user goes only after that commits — a failure there leaves an empty
account the athlete can delete again, never rows nobody can reach.
"""
from __future__ import annotations

import os

import requests

from src import db


def _supabase_url() -> str:
    return os.environ.get('SUPABASE_URL', '')


def _service_role_key() -> str:
    return os.environ.get('SUPABASE_SERVICE_ROLE_KEY', '')

_TABLES_SQL = '''
    SELECT c.table_name
      FROM information_schema.columns c
      JOIN information_schema.tables t
        ON t.table_schema = c.table_schema AND t.table_name = c.table_name
     WHERE c.table_schema = 'public'
       AND c.column_name = 'user_id'
       AND t.table_type = 'BASE TABLE'
'''

# (child, parent) for every foreign key between public tables.
_FKS_SQL = '''
    SELECT tc.table_name AS child, ccu.table_name AS parent
      FROM information_schema.table_constraints tc
      JOIN information_schema.constraint_column_usage ccu
        ON ccu.constraint_name = tc.constraint_name
       AND ccu.constraint_schema = tc.constraint_schema
     WHERE tc.constraint_type = 'FOREIGN KEY'
       AND tc.table_schema = 'public'
       AND ccu.table_schema = 'public'
'''


class AccountDeletionError(Exception):
    """The rows or the Supabase user could not be deleted; `status` is the HTTP answer."""

    def __init__(self, message: str, status: int = 502):
        super().__init__(message)
        self.status = status


def deletion_order(tables: list[str], fks: list[tuple[str, str]]) -> list[str]:
    """`tables` ordered so a table comes before every table it references.

    A cycle (or a self-reference) cannot be ordered; its tables keep their
    sorted order, which leaves Postgres to say which constraint is in the way.
    """
    wanted = set(tables)
    parents: dict[str, set[str]] = {t: set() for t in wanted}
    for child, parent in fks:
        if child in wanted and parent in wanted and child != parent:
            parents[child].add(parent)
    order: list[str] = []
    remaining = set(wanted)
    while remaining:
        # Tables no remaining table references can go now.
        referenced = {p for t in remaining for p in parents[t] if p in remaining}
        ready = sorted(t for t in remaining if t not in referenced)
        if not ready:
            order.extend(sorted(remaining))
            break
        order.extend(ready)
        remaining -= set(ready)
    return order


def delete_rows(user_id: str) -> dict[str, int]:
    """Delete every row of `user_id` in one transaction; {table: rows deleted}."""
    conn = db.new_conn(autocommit=False)
    if conn is None:
        return _delete_local(user_id)
    try:
        with conn.cursor() as cur:
            cur.execute(_TABLES_SQL)
            tables = [r[0] for r in cur.fetchall()]
            cur.execute(_FKS_SQL)
            fks = [(r[0], r[1]) for r in cur.fetchall()]
            counts: dict[str, int] = {}
            from psycopg2 import sql
            for table in deletion_order(tables, fks):
                cur.execute(
                    sql.SQL('DELETE FROM {} WHERE user_id = %s').format(sql.Identifier(table)),
                    (user_id,))
                if cur.rowcount:
                    counts[table] = cur.rowcount
        conn.commit()
        return counts
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def _delete_local(user_id: str) -> dict[str, int]:
    """Local dev without a database keeps only the profile file."""
    path = db._get_profile_path(user_id)
    if path.exists():
        path.unlink()
        return {'profiles': 1}
    return {}


def delete_auth_user(user_id: str) -> None:
    """Delete the Supabase Auth user (and with it its passkeys and identities)."""
    key = _service_role_key()
    try:
        resp = requests.delete(
            f'{_supabase_url()}/auth/v1/admin/users/{user_id}',
            headers={'apikey': key, 'Authorization': f'Bearer {key}'},
            timeout=15,
        )
    except requests.RequestException as e:
        raise AccountDeletionError(f'Supabase unreachable: {e}') from e
    # 404: already gone (a retry after the user went but the answer was lost).
    if resp.status_code not in (200, 204, 404):
        raise AccountDeletionError(f'Supabase refused the deletion ({resp.status_code})')


def revoke_integrations(user_id: str) -> None:
    """Tell Strava and Garmin to stop sending; best effort, never raises."""
    try:
        import oauth as _oauth
        _oauth.disconnect(user_id)
    except Exception:
        pass
    try:
        from src import garmin_connect
        garmin_connect.disconnect(user_id)
    except Exception:
        pass


def delete_account(user_id: str) -> dict[str, int]:
    """The whole deletion. Raises AccountDeletionError with the HTTP status to answer."""
    if _supabase_url() and not _service_role_key():
        # Checked first: without the key the rows would go and the user stay.
        raise AccountDeletionError('Account deletion is not configured', status=503)
    revoke_integrations(user_id)
    counts = delete_rows(user_id)
    if _supabase_url():
        delete_auth_user(user_id)
    return counts
