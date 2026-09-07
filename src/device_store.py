"""Device-token store for the watch-companion pairing flow.

A watch (with no credentials yet) mints a *pending* pairing: a short, human-
readable code plus a long-lived opaque device token. It shows the code as a QR /
text; the user, signed in on web or phone, claims the code, which binds the token
to their user_id. From then on the watch authenticates every request with
`Authorization: Bearer <device_token>` (see src/auth.py).

Mirrors src/db.py: uses Supabase PostgreSQL when DATABASE_URL is set, else falls
back to a local JSON file so the flow is testable in dev.
"""
from __future__ import annotations

import json
import secrets
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import psycopg2.extras as _pg_extras

TOKEN_PREFIX = 'ciqdev_'          # marks a device token vs. a Supabase JWT
PAIRING_TTL_SEC = 600             # a pairing code is valid for 10 minutes
# Unambiguous alphabet (no O/0/I/1) for a code a user might read off a watch.
_CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
_CODE_LEN = 6

_local_path = Path(__file__).parent.parent / 'data' / 'user_profiles' / '_device_tokens.json'

_TABLE_READY = False


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _gen_code() -> str:
    return ''.join(secrets.choice(_CODE_ALPHABET) for _ in range(_CODE_LEN))


def _gen_token() -> str:
    return TOKEN_PREFIX + secrets.token_urlsafe(32)


# ── Postgres path ───────────────────────────────────────────────────────────────

def _conn():
    """Return a live Postgres connection or None (dev / no DATABASE_URL)."""
    from src.db import _get_pg_conn
    return _get_pg_conn()


def _ensure_table(cur) -> None:
    global _TABLE_READY
    if _TABLE_READY:
        return
    cur.execute('''
        CREATE TABLE IF NOT EXISTS device_tokens (
            device_token TEXT PRIMARY KEY,
            pairing_code TEXT,
            user_id      TEXT,
            claimed      BOOLEAN NOT NULL DEFAULT FALSE,
            device_name  TEXT,
            created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            claimed_at   TIMESTAMPTZ,
            last_used_at TIMESTAMPTZ
        )
    ''')
    cur.execute('''
        CREATE INDEX IF NOT EXISTS idx_device_tokens_pairing_code
        ON device_tokens (pairing_code) WHERE claimed = FALSE
    ''')
    cur.execute('''
        CREATE INDEX IF NOT EXISTS idx_device_tokens_user_id
        ON device_tokens (user_id)
    ''')
    _TABLE_READY = True


# ── Local JSON fallback ─────────────────────────────────────────────────────────

def _local_load() -> dict[str, Any]:
    if _local_path.exists():
        try:
            with open(_local_path, 'r', encoding='utf-8') as f:
                return json.load(f)
        except Exception:
            return {}
    return {}


def _local_save(data: dict[str, Any]) -> None:
    _local_path.parent.mkdir(parents=True, exist_ok=True)
    with open(_local_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2)


def _expired(created_iso: str) -> bool:
    try:
        created = datetime.fromisoformat(created_iso)
    except Exception:
        return True
    if created.tzinfo is None:
        created = created.replace(tzinfo=timezone.utc)
    return (_now() - created).total_seconds() > PAIRING_TTL_SEC


# ── Public API ──────────────────────────────────────────────────────────────────

def create_pairing(device_name: str | None = None) -> dict:
    """Mint a pending pairing. Returns {code, deviceToken, expiresInSec}."""
    token = _gen_token()
    conn = _conn()
    if conn:
        with conn.cursor(cursor_factory=_pg_extras.RealDictCursor) as cur:
            _ensure_table(cur)
            # Retry on the (rare) chance of a live code collision.
            for _ in range(5):
                code = _gen_code()
                cur.execute(
                    'SELECT 1 FROM device_tokens WHERE pairing_code = %s AND claimed = FALSE',
                    (code,),
                )
                if not cur.fetchone():
                    break
            cur.execute(
                'INSERT INTO device_tokens (device_token, pairing_code, device_name) '
                'VALUES (%s, %s, %s)',
                (token, code, device_name),
            )
        conn.commit()
    else:
        data = _local_load()
        for _ in range(5):
            code = _gen_code()
            if not any(v.get('pairing_code') == code and not v.get('claimed') for v in data.values()):
                break
        data[token] = {
            'pairing_code': code,
            'user_id': None,
            'claimed': False,
            'device_name': device_name,
            'created_at': _now().isoformat(),
        }
        _local_save(data)
    return {'code': code, 'deviceToken': token, 'expiresInSec': PAIRING_TTL_SEC}


def claim_pairing(code: str, user_id: str) -> bool:
    """Bind a pending, unexpired code to a signed-in user. True if claimed."""
    code = (code or '').strip().upper()
    if not code:
        return False
    conn = _conn()
    if conn:
        with conn.cursor(cursor_factory=_pg_extras.RealDictCursor) as cur:
            _ensure_table(cur)
            cur.execute(
                'SELECT device_token, created_at FROM device_tokens '
                'WHERE pairing_code = %s AND claimed = FALSE '
                'ORDER BY created_at DESC LIMIT 1',
                (code,),
            )
            row = cur.fetchone()
            if not row:
                return False
            created = row['created_at']
            if created and (_now() - created).total_seconds() > PAIRING_TTL_SEC:
                return False
            cur.execute(
                'UPDATE device_tokens SET user_id = %s, claimed = TRUE, '
                'claimed_at = NOW(), pairing_code = NULL '
                'WHERE device_token = %s',
                (user_id, row['device_token']),
            )
        conn.commit()
        return True
    data = _local_load()
    for token, rec in data.items():
        if rec.get('pairing_code') == code and not rec.get('claimed'):
            if _expired(rec.get('created_at', '')):
                return False
            rec['user_id'] = user_id
            rec['claimed'] = True
            rec['claimed_at'] = _now().isoformat()
            rec['pairing_code'] = None
            _local_save(data)
            return True
    return False


def pairing_status(device_token: str) -> dict | None:
    """Poll target for the watch. Returns {claimed} (+{userId} once claimed), or None if unknown."""
    conn = _conn()
    if conn:
        with conn.cursor(cursor_factory=_pg_extras.RealDictCursor) as cur:
            _ensure_table(cur)
            cur.execute(
                'SELECT user_id, claimed FROM device_tokens WHERE device_token = %s',
                (device_token,),
            )
            row = cur.fetchone()
        if not row:
            return None
        out: dict = {'claimed': bool(row['claimed'])}
        if row['claimed']:
            out['userId'] = row['user_id']
        return out
    rec = _local_load().get(device_token)
    if not rec:
        return None
    out = {'claimed': bool(rec.get('claimed'))}
    if rec.get('claimed'):
        out['userId'] = rec.get('user_id')
    return out


def user_for_token(device_token: str) -> str | None:
    """Resolve a claimed device token to its user_id (used by require_auth). Touches last_used_at."""
    conn = _conn()
    if conn:
        with conn.cursor(cursor_factory=_pg_extras.RealDictCursor) as cur:
            _ensure_table(cur)
            cur.execute(
                'SELECT user_id, claimed FROM device_tokens WHERE device_token = %s',
                (device_token,),
            )
            row = cur.fetchone()
            if not row or not row['claimed'] or not row['user_id']:
                return None
            cur.execute(
                'UPDATE device_tokens SET last_used_at = NOW() WHERE device_token = %s',
                (device_token,),
            )
        conn.commit()
        return row['user_id']
    rec = _local_load().get(device_token)
    if rec and rec.get('claimed') and rec.get('user_id'):
        return rec['user_id']
    return None


def list_devices(user_id: str) -> list[dict]:
    """Claimed devices for a user (for a future 'manage devices' UI)."""
    conn = _conn()
    if conn:
        with conn.cursor(cursor_factory=_pg_extras.RealDictCursor) as cur:
            _ensure_table(cur)
            cur.execute(
                'SELECT device_token, device_name, claimed_at, last_used_at '
                'FROM device_tokens WHERE user_id = %s AND claimed = TRUE '
                'ORDER BY claimed_at DESC',
                (user_id,),
            )
            rows = cur.fetchall()
        return [
            {
                'deviceToken': r['device_token'][:14] + '…',   # never expose the full secret
                'deviceName': r['device_name'],
                'claimedAt': str(r['claimed_at']) if r['claimed_at'] else None,
                'lastUsedAt': str(r['last_used_at']) if r['last_used_at'] else None,
            }
            for r in rows
        ]
    return [
        {
            'deviceToken': tok[:14] + '…',
            'deviceName': rec.get('device_name'),
            'claimedAt': rec.get('claimed_at'),
            'lastUsedAt': rec.get('last_used_at'),
        }
        for tok, rec in _local_load().items()
        if rec.get('user_id') == user_id and rec.get('claimed')
    ]


def revoke_token(device_token: str, user_id: str) -> bool:
    """Delete a device token the user owns. True if a row was removed."""
    conn = _conn()
    if conn:
        with conn.cursor(cursor_factory=_pg_extras.RealDictCursor) as cur:
            _ensure_table(cur)
            cur.execute(
                'DELETE FROM device_tokens WHERE device_token = %s AND user_id = %s',
                (device_token, user_id),
            )
            deleted = cur.rowcount > 0
        conn.commit()
        return deleted
    data = _local_load()
    rec = data.get(device_token)
    if rec and rec.get('user_id') == user_id:
        del data[device_token]
        _local_save(data)
        return True
    return False
