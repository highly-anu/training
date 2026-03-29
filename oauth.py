"""Strava OAuth 2.0 integration — token storage, authorization, sync."""
from __future__ import annotations

import os
import secrets
import sqlite3
import time
import uuid
from datetime import datetime, timezone
from urllib.parse import urlencode

import requests as _requests

# ---------------------------------------------------------------------------
# Database

DB_PATH = os.path.join(os.path.dirname(__file__), 'data', 'oauth.db')

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


def _get_db() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db() -> None:
    """Create tables if they don't exist. Safe to call on every request."""
    with _get_db() as conn:
        conn.execute('''
            CREATE TABLE IF NOT EXISTS oauth_tokens (
                provider     TEXT PRIMARY KEY,
                access_token TEXT NOT NULL,
                refresh_token TEXT NOT NULL,
                expires_at   INTEGER NOT NULL,
                athlete_id   TEXT,
                athlete_name TEXT,
                athlete_profile TEXT,
                last_sync_at TEXT
            )
        ''')
        conn.execute('''
            CREATE TABLE IF NOT EXISTS oauth_state (
                state      TEXT PRIMARY KEY,
                created_at INTEGER NOT NULL
            )
        ''')


# ---------------------------------------------------------------------------
# Strava helpers

_AUTH_URL = 'https://www.strava.com/oauth/authorize'
_TOKEN_URL = 'https://www.strava.com/oauth/token'
_ACTIVITIES_URL = 'https://www.strava.com/api/v3/athlete/activities'
_DEAUTH_URL = 'https://www.strava.com/oauth/deauthorize'


def _creds() -> tuple[str, str, str]:
    """Return (client_id, client_secret, redirect_uri)."""
    client_id = os.environ.get('STRAVA_CLIENT_ID', '')
    client_secret = os.environ.get('STRAVA_CLIENT_SECRET', '')
    redirect_uri = os.environ.get(
        'STRAVA_REDIRECT_URI', 'http://localhost:8000/api/oauth/strava/callback'
    )
    return client_id, client_secret, redirect_uri


def is_configured() -> bool:
    client_id, client_secret, _ = _creds()
    return bool(client_id and client_secret)


# ---------------------------------------------------------------------------
# Status

def get_strava_status() -> dict:
    with _get_db() as conn:
        row = conn.execute(
            "SELECT * FROM oauth_tokens WHERE provider='strava'"
        ).fetchone()
    if not row:
        return {'connected': False, 'configured': is_configured()}
    return {
        'connected': True,
        'configured': True,
        'athlete': {
            'id': row['athlete_id'],
            'name': row['athlete_name'],
            'profile': row['athlete_profile'],
        },
        'last_sync_at': row['last_sync_at'],
    }


# ---------------------------------------------------------------------------
# Authorization

def generate_auth_url() -> str:
    client_id, _, redirect_uri = _creds()
    state = secrets.token_urlsafe(16)
    with _get_db() as conn:
        # Purge states older than 10 minutes
        conn.execute(
            'DELETE FROM oauth_state WHERE created_at < ?', (int(time.time()) - 600,)
        )
        conn.execute(
            'INSERT OR REPLACE INTO oauth_state VALUES (?, ?)', (state, int(time.time()))
        )
    params = {
        'client_id': client_id,
        'redirect_uri': redirect_uri,
        'response_type': 'code',
        'approval_prompt': 'auto',
        'scope': 'activity:read_all',
        'state': state,
    }
    return f'{_AUTH_URL}?{urlencode(params)}'


def handle_callback(code: str, state: str) -> None:
    """Exchange authorization code for tokens; store in DB."""
    with _get_db() as conn:
        row = conn.execute(
            'SELECT * FROM oauth_state WHERE state=?', (state,)
        ).fetchone()
        if not row or int(time.time()) - row['created_at'] > 600:
            raise ValueError('Invalid or expired state parameter — possible CSRF')
        conn.execute('DELETE FROM oauth_state WHERE state=?', (state,))

    client_id, client_secret, _ = _creds()
    resp = _requests.post(_TOKEN_URL, data={
        'client_id': client_id,
        'client_secret': client_secret,
        'code': code,
        'grant_type': 'authorization_code',
    }, timeout=15)
    resp.raise_for_status()
    data = resp.json()

    athlete = data.get('athlete', {})
    name = f"{athlete.get('firstname', '')} {athlete.get('lastname', '')}".strip()
    profile = athlete.get('profile_medium') or athlete.get('profile')

    with _get_db() as conn:
        conn.execute('''
            INSERT OR REPLACE INTO oauth_tokens
            (provider, access_token, refresh_token, expires_at, athlete_id, athlete_name, athlete_profile)
            VALUES ('strava', ?, ?, ?, ?, ?, ?)
        ''', (
            data['access_token'], data['refresh_token'], data['expires_at'],
            str(athlete.get('id', '')), name, profile,
        ))


# ---------------------------------------------------------------------------
# Token refresh + disconnect

def _get_valid_token() -> str:
    with _get_db() as conn:
        row = conn.execute(
            "SELECT * FROM oauth_tokens WHERE provider='strava'"
        ).fetchone()
    if not row:
        raise ValueError('Strava not connected')

    # Refresh if expiring within 5 minutes
    if int(time.time()) >= row['expires_at'] - 300:
        client_id, client_secret, _ = _creds()
        resp = _requests.post(_TOKEN_URL, data={
            'client_id': client_id,
            'client_secret': client_secret,
            'refresh_token': row['refresh_token'],
            'grant_type': 'refresh_token',
        }, timeout=15)
        resp.raise_for_status()
        data = resp.json()
        with _get_db() as conn:
            conn.execute(
                'UPDATE oauth_tokens SET access_token=?, refresh_token=?, expires_at=? '
                "WHERE provider='strava'",
                (data['access_token'], data['refresh_token'], data['expires_at'])
            )
        return data['access_token']

    return row['access_token']


def disconnect() -> None:
    try:
        token = _get_valid_token()
        _requests.post(_DEAUTH_URL, headers={'Authorization': f'Bearer {token}'}, timeout=10)
    except Exception:
        pass  # best-effort revocation
    with _get_db() as conn:
        conn.execute("DELETE FROM oauth_tokens WHERE provider='strava'")


# ---------------------------------------------------------------------------
# Activity sync

def _activity_to_workout(a: dict) -> dict | None:
    """Convert a Strava activity dict to an ImportedWorkout-shaped dict."""
    if not a.get('start_date'):
        return None
    sport_type = a.get('sport_type') or a.get('type') or 'Workout'
    elapsed = a.get('elapsed_time', 0)
    try:
        start_dt = datetime.fromisoformat(a['start_date'].replace('Z', '+00:00'))
        end_dt = datetime.fromtimestamp(start_dt.timestamp() + elapsed, tz=timezone.utc)
    except Exception:
        return None

    dist = a.get('distance', 0)
    kj = a.get('kilojoules')
    avg_hr = a.get('average_heartrate')
    max_hr = a.get('max_heartrate')

    return {
        'id': str(uuid.uuid4()),
        'source': 'strava',
        'date': start_dt.strftime('%Y-%m-%d'),
        'startTime': start_dt.isoformat(),
        'endTime': end_dt.isoformat(),
        'durationMinutes': round(elapsed / 60),
        'activityType': sport_type,
        'inferredModalityId': _STRAVA_MODALITY_MAP.get(sport_type),
        'heartRate': {
            'avg': avg_hr,
            'max': max_hr,
            'min': None,
            'samples': [],
        },
        'calories': round(kj * 0.239) if kj else None,
        'distance': {'value': round(dist / 1000, 3), 'unit': 'km'} if dist else None,
        'rawData': {},
    }


def sync_activities(since_timestamp: float | None = None) -> list[dict]:
    """Pull activities from Strava, return ImportedWorkout-shaped dicts."""
    token = _get_valid_token()
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
    results = [w for a in activities if (w := _activity_to_workout(a)) is not None]

    # Update last_sync_at
    now_iso = datetime.now(timezone.utc).isoformat()
    with _get_db() as conn:
        conn.execute(
            "UPDATE oauth_tokens SET last_sync_at=? WHERE provider='strava'", (now_iso,)
        )

    return results
