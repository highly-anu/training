"""Strava OAuth 2.0 integration — token storage, authorization, sync."""
from __future__ import annotations

import os
import secrets
import sqlite3
import time
from datetime import datetime, timezone
from urllib.parse import urlencode

import requests as _requests

# ---------------------------------------------------------------------------
# Ephemeral state DB (SQLite — short-lived CSRF tokens only)
# Actual Strava tokens are stored in Supabase (strava_tokens table).

_STATE_DB_PATH = os.path.join(os.path.dirname(__file__), 'data', 'oauth_state.db')

_STRAVA_MODALITY_MAP = {
    'Run': 'aerobic_base', 'TrailRun': 'aerobic_base', 'VirtualRun': 'aerobic_base',
    'Ride': 'aerobic_base', 'VirtualRide': 'aerobic_base', 'Swim': 'aerobic_base',
    'Walk': 'durability', 'Hike': 'durability',
    'WeightTraining': 'max_strength',
    'HIIT': 'anaerobic_intervals', 'Crossfit': 'mixed_modal_conditioning',
    'Workout': 'mixed_modal_conditioning', 'Yoga': 'mobility', 'Rowing': 'aerobic_base',
    'MartialArts': 'combat_sport', 'Boxing': 'combat_sport', 'RockClimbing': 'durability',
    'Skiing': 'aerobic_base', 'Snowboard': 'aerobic_base', 'Skateboard': 'movement_skill',
}


def _get_state_db() -> sqlite3.Connection:
    conn = sqlite3.connect(_STATE_DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db() -> None:
    """Create the ephemeral CSRF state table."""
    with _get_state_db() as conn:
        conn.execute('''
            CREATE TABLE IF NOT EXISTS oauth_state (
                state      TEXT PRIMARY KEY,
                user_id    TEXT NOT NULL,
                created_at INTEGER NOT NULL
            )
        ''')
        # Migrate existing state table that lacks user_id
        try:
            conn.execute('ALTER TABLE oauth_state ADD COLUMN user_id TEXT NOT NULL DEFAULT ""')
        except sqlite3.OperationalError:
            pass


# ---------------------------------------------------------------------------
# Strava helpers

_AUTH_URL       = 'https://www.strava.com/oauth/authorize'
_TOKEN_URL      = 'https://www.strava.com/oauth/token'
_ACTIVITIES_URL = 'https://www.strava.com/api/v3/athlete/activities'
_DEAUTH_URL     = 'https://www.strava.com/oauth/deauthorize'


def _creds() -> tuple[str, str, str]:
    """Return (client_id, client_secret, redirect_uri)."""
    client_id     = os.environ.get('STRAVA_CLIENT_ID', '')
    client_secret = os.environ.get('STRAVA_CLIENT_SECRET', '')
    redirect_uri  = os.environ.get(
        'STRAVA_REDIRECT_URI', 'http://localhost:8000/api/oauth/strava/callback'
    )
    return client_id, client_secret, redirect_uri


def is_configured() -> bool:
    client_id, client_secret, _ = _creds()
    return bool(client_id and client_secret)


# ---------------------------------------------------------------------------
# Status

def get_strava_status(user_id: str) -> dict:
    from src.db import get_conn
    try:
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute('SELECT * FROM strava_tokens WHERE user_id = %s', (user_id,))
                row = cur.fetchone()
    except RuntimeError:
        row = None

    if not row:
        return {'connected': False, 'configured': is_configured()}
    return {
        'connected':   True,
        'configured':  True,
        'athlete': {
            'id':      row['athlete_id'],
            'name':    row['athlete_name'],
            'profile': row['athlete_profile'],
        },
        'last_sync_at': str(row['last_sync_at']) if row['last_sync_at'] else None,
    }


# ---------------------------------------------------------------------------
# Authorization

def generate_auth_url(user_id: str) -> str:
    client_id, _, redirect_uri = _creds()
    state = secrets.token_urlsafe(16)
    with _get_state_db() as conn:
        conn.execute(
            'DELETE FROM oauth_state WHERE created_at < ?', (int(time.time()) - 600,)
        )
        conn.execute(
            'INSERT OR REPLACE INTO oauth_state VALUES (?, ?, ?)',
            (state, user_id, int(time.time())),
        )
    params = {
        'client_id':       client_id,
        'redirect_uri':    redirect_uri,
        'response_type':   'code',
        'approval_prompt': 'auto',
        'scope':           'activity:read_all',
        'state':           state,
    }
    return f'{_AUTH_URL}?{urlencode(params)}'


def handle_callback(code: str, state: str) -> None:
    """Exchange authorization code for tokens and store in Supabase."""
    with _get_state_db() as conn:
        row = conn.execute(
            'SELECT * FROM oauth_state WHERE state = ?', (state,)
        ).fetchone()
        if not row or int(time.time()) - row['created_at'] > 600:
            raise ValueError('Invalid or expired state parameter — possible CSRF')
        user_id = row['user_id']
        conn.execute('DELETE FROM oauth_state WHERE state = ?', (state,))

    if not user_id:
        raise ValueError('State token missing user_id — re-authorize')

    client_id, client_secret, _ = _creds()
    resp = _requests.post(_TOKEN_URL, data={
        'client_id':     client_id,
        'client_secret': client_secret,
        'code':          code,
        'grant_type':    'authorization_code',
    }, timeout=15)
    resp.raise_for_status()
    data = resp.json()

    athlete = data.get('athlete', {})
    name    = f"{athlete.get('firstname', '')} {athlete.get('lastname', '')}".strip()
    profile = athlete.get('profile_medium') or athlete.get('profile')

    from src.db import get_conn
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute('''
                INSERT INTO strava_tokens
                (user_id, access_token, refresh_token, expires_at, athlete_id, athlete_name, athlete_profile)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (user_id) DO UPDATE SET
                    access_token    = EXCLUDED.access_token,
                    refresh_token   = EXCLUDED.refresh_token,
                    expires_at      = EXCLUDED.expires_at,
                    athlete_id      = EXCLUDED.athlete_id,
                    athlete_name    = EXCLUDED.athlete_name,
                    athlete_profile = EXCLUDED.athlete_profile
            ''', (
                user_id,
                data['access_token'], data['refresh_token'], data['expires_at'],
                str(athlete.get('id', '')), name, profile,
            ))
        conn.commit()


# ---------------------------------------------------------------------------
# Token refresh + disconnect

def _get_valid_token(user_id: str) -> str:
    from src.db import get_conn
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute('SELECT * FROM strava_tokens WHERE user_id = %s', (user_id,))
            row = cur.fetchone()

    if not row:
        raise ValueError('Strava not connected')

    # Refresh if expiring within 5 minutes
    if int(time.time()) >= row['expires_at'] - 300:
        client_id, client_secret, _ = _creds()
        resp = _requests.post(_TOKEN_URL, data={
            'client_id':     client_id,
            'client_secret': client_secret,
            'refresh_token': row['refresh_token'],
            'grant_type':    'refresh_token',
        }, timeout=15)
        resp.raise_for_status()
        data = resp.json()
        from src.db import get_conn as _gc
        with _gc() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    'UPDATE strava_tokens SET access_token = %s, refresh_token = %s, expires_at = %s '
                    'WHERE user_id = %s',
                    (data['access_token'], data['refresh_token'], data['expires_at'], user_id),
                )
            conn.commit()
        return data['access_token']

    return row['access_token']


def disconnect(user_id: str) -> None:
    try:
        token = _get_valid_token(user_id)
        _requests.post(_DEAUTH_URL, headers={'Authorization': f'Bearer {token}'}, timeout=10)
    except Exception:
        pass  # best-effort revocation
    from src.db import get_conn
    try:
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute('DELETE FROM strava_tokens WHERE user_id = %s', (user_id,))
            conn.commit()
    except RuntimeError:
        pass


# ---------------------------------------------------------------------------
# Activity sync

def _activity_to_workout(a: dict) -> dict | None:
    if not a.get('start_date'):
        return None
    sport_type = a.get('sport_type') or a.get('type') or 'Workout'
    elapsed    = a.get('elapsed_time', 0)
    try:
        start_dt = datetime.fromisoformat(a['start_date'].replace('Z', '+00:00'))
        end_dt   = datetime.fromtimestamp(start_dt.timestamp() + elapsed, tz=timezone.utc)
    except Exception:
        return None

    dist   = a.get('distance', 0)
    kj     = a.get('kilojoules')
    avg_hr = a.get('average_heartrate')
    max_hr = a.get('max_heartrate')

    import hashlib as _hashlib
    raw = f"strava|{a['start_date']}|{sport_type}|{round(elapsed / 60)}"
    workout_id = f"strava-{_hashlib.sha256(raw.encode()).hexdigest()[:24]}"

    return {
        'id':              workout_id,
        'source':          'strava',
        'date':            start_dt.strftime('%Y-%m-%d'),
        'startTime':       start_dt.isoformat(),
        'endTime':         end_dt.isoformat(),
        'durationMinutes': round(elapsed / 60),
        'activityType':    sport_type,
        'inferredModalityId': _STRAVA_MODALITY_MAP.get(sport_type),
        'heartRate': {
            'avg': avg_hr, 'max': max_hr, 'min': None, 'samples': [],
        },
        'calories': round(kj * 0.239) if kj else None,
        'distance': {'value': round(dist / 1000, 3), 'unit': 'km'} if dist else None,
        'rawData':  {},
    }


def sync_activities(user_id: str, since_timestamp: float | None = None) -> list[dict]:
    """Pull activities from Strava, return ImportedWorkout-shaped dicts."""
    token  = _get_valid_token(user_id)
    params: dict = {'per_page': 100}
    if since_timestamp is not None:
        params['after'] = int(since_timestamp)

    resp = _requests.get(
        _ACTIVITIES_URL,
        headers={'Authorization': f'Bearer {token}'},
        params=params,
        timeout=30,
    )
    resp.raise_for_status()

    activities = resp.json()
    results    = [w for a in activities if (w := _activity_to_workout(a)) is not None]

    # Update last_sync_at
    now_iso = datetime.now(timezone.utc).isoformat()
    from src.db import get_conn
    try:
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    'UPDATE strava_tokens SET last_sync_at = %s WHERE user_id = %s',
                    (now_iso, user_id),
                )
            conn.commit()
    except RuntimeError:
        pass

    return results
