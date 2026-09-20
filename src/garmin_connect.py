"""Garmin Connect integration — OAuth, activity fetch, backfill.

Deliberately mirrors oauth.py's public surface (is_configured / get_status /
generate_auth_url / handle_callback / disconnect) so the two integrations read
alike from api.py.

Lives in src/ rather than as a root-level garmin.py: the repo already has a
`garmin/` directory (the Connect IQ watch app), and a sibling garmin.py would
shadow it as a namespace package.

## On the endpoint constants below

The Connect Developer Program's exact hosts and paths are documented in
Garmin's partner portal, which is gated behind an approved application. Every
one of them is therefore overridable by environment variable, and
GARMIN_API_BASE in particular is what lets the whole flow be exercised against
a local stub with no approval at all (see test_garmin_webhook.py). Verify them
against the real documentation before going live — treat the defaults as a
starting point, not as confirmed fact.

## OAuth version

The program has moved from OAuth 1.0a (legacy Health API) to OAuth 2.0 + PKCE.
The token store covers both; only `_auth_headers` and `_get_valid_token` branch
on `oauth_version`, and everything downstream takes an opaque headers dict.
Only the 2.0 path is implemented here — if an approved account turns out to be
on 1.0a, that is where the HMAC-SHA1 signer goes.
"""
from __future__ import annotations

import base64
import hashlib
import os
import secrets
import time
from datetime import datetime, timezone
from urllib.parse import urlencode, urlparse

import requests as _requests

from src import oauth_state

# --- Endpoints (override via env; see the module docstring) -----------------
AUTH_URL = os.environ.get('GARMIN_AUTH_URL', 'https://connect.garmin.com/oauth2Confirm')
TOKEN_URL = os.environ.get('GARMIN_TOKEN_URL',
                           'https://diauth.garmin.com/di-oauth2-service/oauth/token')
API_BASE = os.environ.get('GARMIN_API_BASE', 'https://apis.garmin.com').rstrip('/')

USER_ID_PATH = '/wellness-api/rest/user/id'
REGISTRATION_PATH = '/wellness-api/rest/user/registration'
BACKFILL_PATH = '/wellness-api/rest/backfill/activities'

SCOPE = os.environ.get('GARMIN_SCOPE', 'ACTIVITY_EXPORT')

HTTP_TIMEOUT = 30
# Refresh a little early rather than racing the expiry.
TOKEN_REFRESH_MARGIN_SEC = 300
# Garmin's backfill accepts at most 90 days per request.
BACKFILL_WINDOW_DAYS = 90

_TABLE_READY: bool | None = None


# ---------------------------------------------------------------------------
# Configuration

def _creds() -> tuple[str, str, str]:
    """(client_id, client_secret, redirect_uri)."""
    return (
        os.environ.get('GARMIN_CLIENT_ID', ''),
        os.environ.get('GARMIN_CLIENT_SECRET', ''),
        os.environ.get('GARMIN_REDIRECT_URI',
                       'http://localhost:8000/api/oauth/garmin/callback'),
    )


def is_configured() -> bool:
    """False leaves the whole feature inert rather than broken — every route
    checks this, exactly as the Strava ones check oauth.is_configured()."""
    client_id, client_secret, _ = _creds()
    return bool(client_id and client_secret)


def webhook_secret() -> str:
    return os.environ.get('GARMIN_WEBHOOK_SECRET', '')


# ---------------------------------------------------------------------------
# Token storage

def _ensure_table(cur) -> bool:
    global _TABLE_READY
    if _TABLE_READY is not None:
        return _TABLE_READY
    try:
        cur.execute('''
            CREATE TABLE IF NOT EXISTS garmin_tokens (
                user_id                  TEXT PRIMARY KEY,
                oauth_version            SMALLINT NOT NULL DEFAULT 2,
                access_token             TEXT NOT NULL,
                refresh_token            TEXT,
                token_secret             TEXT,
                expires_at               BIGINT,
                refresh_token_expires_at BIGINT,
                garmin_user_id           TEXT UNIQUE,
                scope                    TEXT,
                athlete_name             TEXT,
                connected_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                last_sync_at             TIMESTAMPTZ,
                last_webhook_at          TIMESTAMPTZ
            )
        ''')
        cur.execute('CREATE INDEX IF NOT EXISTS idx_garmin_tokens_garmin_user '
                    'ON garmin_tokens (garmin_user_id)')
        cur.execute('''
            CREATE TABLE IF NOT EXISTS garmin_activities (
                garmin_user_id TEXT NOT NULL,
                summary_id     TEXT NOT NULL,
                user_id        TEXT NOT NULL,
                workout_id     TEXT,
                imported_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                PRIMARY KEY (garmin_user_id, summary_id)
            )
        ''')
        _TABLE_READY = True
    except Exception:
        _TABLE_READY = False
    return _TABLE_READY


def _conn():
    from src.db import _get_pg_conn
    return _get_pg_conn()


def _token_row(user_id: str) -> dict | None:
    import psycopg2.extras as _extras
    conn = _conn()
    if conn is None:
        return None
    with conn.cursor(cursor_factory=_extras.RealDictCursor) as cur:
        if not _ensure_table(cur):
            return None
        cur.execute('SELECT * FROM garmin_tokens WHERE user_id = %s', (user_id,))
        row = cur.fetchone()
    return dict(row) if row else None


def user_for_garmin_id(garmin_user_id: str) -> str | None:
    """The reverse lookup the webhook depends on — Garmin identifies the
    athlete by its own id and knows nothing about ours."""
    conn = _conn()
    if conn is None:
        return None
    with conn.cursor() as cur:
        if not _ensure_table(cur):
            return None
        cur.execute('SELECT user_id FROM garmin_tokens WHERE garmin_user_id = %s',
                    (garmin_user_id,))
        row = cur.fetchone()
    return row[0] if row else None


def _store_tokens(user_id: str, tokens: dict, garmin_user_id: str | None) -> None:
    conn = _conn()
    if conn is None:
        raise RuntimeError('No database connection')
    expires_at = None
    if tokens.get('expires_in'):
        expires_at = int(time.time()) + int(tokens['expires_in'])
    refresh_expires_at = None
    if tokens.get('refresh_token_expires_in'):
        refresh_expires_at = int(time.time()) + int(tokens['refresh_token_expires_in'])

    with conn.cursor() as cur:
        _ensure_table(cur)
        cur.execute('''
            INSERT INTO garmin_tokens
            (user_id, oauth_version, access_token, refresh_token, expires_at,
             refresh_token_expires_at, garmin_user_id, scope)
            VALUES (%s, 2, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (user_id) DO UPDATE SET
                access_token             = EXCLUDED.access_token,
                refresh_token            = COALESCE(EXCLUDED.refresh_token,
                                                    garmin_tokens.refresh_token),
                expires_at               = EXCLUDED.expires_at,
                refresh_token_expires_at = EXCLUDED.refresh_token_expires_at,
                garmin_user_id           = COALESCE(EXCLUDED.garmin_user_id,
                                                    garmin_tokens.garmin_user_id),
                scope                    = EXCLUDED.scope
        ''', (
            user_id, tokens.get('access_token'), tokens.get('refresh_token'),
            expires_at, refresh_expires_at, garmin_user_id, tokens.get('scope'),
        ))


def _touch(user_id: str, column: str) -> None:
    if column not in ('last_sync_at', 'last_webhook_at'):
        raise ValueError(f'unexpected column: {column}')
    conn = _conn()
    if conn is None:
        return
    try:
        with conn.cursor() as cur:
            cur.execute(f'UPDATE garmin_tokens SET {column} = NOW() WHERE user_id = %s',
                        (user_id,))
    except Exception:
        pass


# ---------------------------------------------------------------------------
# Status / authorization

def get_status(user_id: str) -> dict:
    try:
        row = _token_row(user_id)
    except Exception:
        row = None

    if not row:
        return {'connected': False, 'configured': is_configured()}
    return {
        'connected':       True,
        'configured':      True,
        'garminUserId':    row.get('garmin_user_id'),
        'athleteName':     row.get('athlete_name'),
        'connected_at':    str(row['connected_at']) if row.get('connected_at') else None,
        'last_sync_at':    str(row['last_sync_at']) if row.get('last_sync_at') else None,
        'last_webhook_at': str(row['last_webhook_at']) if row.get('last_webhook_at') else None,
    }


def _pkce_pair() -> tuple[str, str]:
    verifier = secrets.token_urlsafe(64)
    digest = hashlib.sha256(verifier.encode()).digest()
    challenge = base64.urlsafe_b64encode(digest).decode().rstrip('=')
    return verifier, challenge


def generate_auth_url(user_id: str) -> str:
    client_id, _, redirect_uri = _creds()
    verifier, challenge = _pkce_pair()
    state = oauth_state.new_state()
    # The verifier is a secret the callback must recover server-side, which is
    # why state lives in Postgres rather than a cookie.
    oauth_state.put(state, user_id, 'garmin', verifier)

    params = {
        'client_id':             client_id,
        'response_type':         'code',
        'redirect_uri':          redirect_uri,
        'state':                 state,
        'code_challenge':        challenge,
        'code_challenge_method': 'S256',
    }
    if SCOPE:
        params['scope'] = SCOPE
    return f'{AUTH_URL}?{urlencode(params)}'


def handle_callback(code: str, state: str) -> str:
    """Exchange the code for tokens and bind them to the athlete.

    Returns our user_id. Raises ValueError on a bad state, which the route
    turns into an error redirect.
    """
    taken = oauth_state.take(state, 'garmin')
    if taken is None:
        raise ValueError('Invalid or expired state parameter — possible CSRF')
    user_id, verifier = taken

    client_id, client_secret, redirect_uri = _creds()
    resp = _requests.post(
        TOKEN_URL,
        data={
            'grant_type':    'authorization_code',
            'client_id':     client_id,
            'client_secret': client_secret,
            'code':          code,
            'redirect_uri':  redirect_uri,
            'code_verifier': verifier or '',
        },
        headers={'Content-Type': 'application/x-www-form-urlencoded'},
        timeout=HTTP_TIMEOUT,
    )
    resp.raise_for_status()
    tokens = resp.json()

    garmin_user_id = None
    try:
        garmin_user_id = fetch_garmin_user_id(tokens['access_token'])
    except Exception:
        # Without this the webhook cannot route pushes to this athlete, but the
        # connection is still worth keeping — a backfill can fill it in later.
        pass

    _store_tokens(user_id, tokens, garmin_user_id)
    return user_id


def fetch_garmin_user_id(access_token: str) -> str | None:
    resp = _requests.get(
        f'{API_BASE}{USER_ID_PATH}',
        headers={'Authorization': f'Bearer {access_token}'},
        timeout=HTTP_TIMEOUT,
    )
    resp.raise_for_status()
    return (resp.json() or {}).get('userId')


def _get_valid_token(user_id: str) -> str:
    row = _token_row(user_id)
    if not row:
        raise RuntimeError('Garmin not connected')

    if row.get('oauth_version', 2) == 1:
        # Legacy Health API: the token does not expire and is signed per
        # request rather than sent as a bearer. Not implemented — no approved
        # 1.0a account to verify against.
        raise NotImplementedError('OAuth 1.0a Garmin accounts are not supported yet')

    expires_at = row.get('expires_at')
    if expires_at and int(expires_at) - TOKEN_REFRESH_MARGIN_SEC <= int(time.time()):
        if not row.get('refresh_token'):
            raise RuntimeError('Garmin token expired and no refresh token is stored')
        client_id, client_secret, _ = _creds()
        resp = _requests.post(
            TOKEN_URL,
            data={
                'grant_type':    'refresh_token',
                'client_id':     client_id,
                'client_secret': client_secret,
                'refresh_token': row['refresh_token'],
            },
            timeout=HTTP_TIMEOUT,
        )
        resp.raise_for_status()
        tokens = resp.json()
        _store_tokens(user_id, tokens, row.get('garmin_user_id'))
        return tokens['access_token']

    return row['access_token']


def _auth_headers(user_id: str) -> dict:
    return {'Authorization': f'Bearer {_get_valid_token(user_id)}'}


def disconnect(user_id: str) -> None:
    """Deregister with Garmin (stopping the webhook) and drop the tokens."""
    try:
        _requests.delete(f'{API_BASE}{REGISTRATION_PATH}',
                         headers=_auth_headers(user_id), timeout=HTTP_TIMEOUT)
    except Exception:
        # Garmin being unreachable must not strand the athlete in a state where
        # the UI says connected and they cannot disconnect.
        pass

    conn = _conn()
    if conn is None:
        return
    with conn.cursor() as cur:
        _ensure_table(cur)
        cur.execute('DELETE FROM garmin_tokens WHERE user_id = %s', (user_id,))


# ---------------------------------------------------------------------------
# Activity fetch

def _default_port(scheme: str) -> int:
    return 443 if scheme == 'https' else 80


def is_allowed_callback(url: str) -> bool:
    """Guard the webhook's fetch against SSRF.

    The callback URL arrives in an unauthenticated POST body. Without this
    check, anyone who learned the webhook URL could make the server fetch
    arbitrary hosts — including anything on its internal network, such as a
    cloud metadata endpoint.

    Host AND port must both match the configured API base. Checking the host
    alone is not enough: when API_BASE points at a host that also runs other
    services (a local stub during development, or anything co-hosted), a
    different port on that same host would otherwise be reachable.
    """
    try:
        target = urlparse(url)
        allowed = urlparse(API_BASE)
    except Exception:
        return False

    if target.scheme not in ('http', 'https'):
        return False
    if not target.hostname or not allowed.hostname:
        return False

    target_port = target.port or _default_port(target.scheme)
    allowed_port = allowed.port or _default_port(allowed.scheme or 'https')
    if target_port != allowed_port:
        return False

    # Exact host, or a subdomain of the configured API base.
    return (target.hostname == allowed.hostname
            or target.hostname.endswith('.' + allowed.hostname))


def fetch_activity_bytes(user_id: str, callback_url: str) -> bytes:
    """Fetch an activity's file from Garmin using our own stored credentials.

    Fetching rather than trusting a pushed body is what makes the data
    authenticated by Garmin's API instead of merely asserted by an anonymous
    POST.
    """
    if not is_allowed_callback(callback_url):
        raise ValueError(f'Refusing to fetch a callback outside {API_BASE}')
    resp = _requests.get(callback_url, headers=_auth_headers(user_id),
                         timeout=HTTP_TIMEOUT)
    resp.raise_for_status()
    return resp.content


def request_backfill(user_id: str, days: int = BACKFILL_WINDOW_DAYS) -> dict:
    """Ask Garmin to replay history through the webhook.

    Garmin's backfill is itself asynchronous: it answers 202 and then delivers
    the activities to the same notification endpoint. That is why this app
    needs no poller and no scheduler for history.
    """
    now = int(time.time())
    start = now - days * 86400
    windows = 0
    errors = []

    cursor = start
    while cursor < now:
        end = min(cursor + BACKFILL_WINDOW_DAYS * 86400, now)
        try:
            resp = _requests.get(
                f'{API_BASE}{BACKFILL_PATH}',
                headers=_auth_headers(user_id),
                params={'summaryStartTimeInSeconds': cursor,
                        'summaryEndTimeInSeconds': end},
                timeout=HTTP_TIMEOUT,
            )
            # 202 Accepted is the success case; 409 means already requested.
            if resp.status_code not in (200, 202, 409):
                errors.append(f'{resp.status_code}: {resp.text[:200]}')
            else:
                windows += 1
        except Exception as e:
            errors.append(str(e))
        cursor = end

    _touch(user_id, 'last_sync_at')
    return {'requestedWindows': windows, 'days': days, 'errors': errors}


# ---------------------------------------------------------------------------
# Ledger

def already_imported(garmin_user_id: str, summary_id: str) -> bool:
    conn = _conn()
    if conn is None:
        return False
    with conn.cursor() as cur:
        if not _ensure_table(cur):
            return False
        cur.execute(
            'SELECT 1 FROM garmin_activities WHERE garmin_user_id = %s AND summary_id = %s',
            (garmin_user_id, summary_id),
        )
        return cur.fetchone() is not None


def record_import(garmin_user_id: str, summary_id: str, user_id: str,
                  workout_id: str | None) -> None:
    conn = _conn()
    if conn is None:
        return
    with conn.cursor() as cur:
        _ensure_table(cur)
        cur.execute('''
            INSERT INTO garmin_activities
            (garmin_user_id, summary_id, user_id, workout_id)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (garmin_user_id, summary_id) DO UPDATE SET
                workout_id = EXCLUDED.workout_id
        ''', (garmin_user_id, summary_id, user_id, workout_id))


# ---------------------------------------------------------------------------
# Summary fallback

_GARMIN_ACTIVITY_MAP = {
    'RUNNING': 'aerobic_base', 'TRAIL_RUNNING': 'aerobic_base',
    'TREADMILL_RUNNING': 'aerobic_base', 'INDOOR_RUNNING': 'aerobic_base',
    'CYCLING': 'aerobic_base', 'ROAD_BIKING': 'aerobic_base',
    'MOUNTAIN_BIKING': 'aerobic_base', 'INDOOR_CYCLING': 'aerobic_base',
    'VIRTUAL_RIDE': 'aerobic_base',
    'LAP_SWIMMING': 'aerobic_base', 'OPEN_WATER_SWIMMING': 'aerobic_base',
    'ROWING': 'aerobic_base', 'INDOOR_ROWING': 'aerobic_base',
    'WALKING': 'durability', 'HIKING': 'durability',
    'STRENGTH_TRAINING': 'max_strength', 'INDOOR_CARDIO': 'mixed_modal_conditioning',
    'HIIT': 'anaerobic_intervals', 'CARDIO_TRAINING': 'mixed_modal_conditioning',
    'YOGA': 'mobility', 'PILATES': 'mobility', 'BREATHWORK': 'mobility',
    'FITNESS_EQUIPMENT': 'mixed_modal_conditioning',
}


def summary_to_workout(summary: dict) -> dict | None:
    """Build an ImportedWorkout from a ping's summary fields.

    Used only when the activity file itself cannot be fetched — a summary has
    no GPS track and no HR samples, so it is deliberately the fallback. The
    dedup layer will enrich it if the file arrives later.
    """
    from src.workout_ids import deterministic_id

    start_sec = summary.get('startTimeInSeconds')
    duration_sec = summary.get('durationInSeconds')
    if start_sec is None or duration_sec is None:
        return None

    offset = summary.get('startTimeOffsetInSeconds') or 0
    start = datetime.fromtimestamp(int(start_sec), tz=timezone.utc)
    end = datetime.fromtimestamp(int(start_sec) + int(duration_sec), tz=timezone.utc)
    duration_min = round(int(duration_sec) / 60)

    activity_type = str(summary.get('activityType') or 'GENERIC').upper()
    display_type = activity_type.replace('_', ' ').title()
    distance_m = summary.get('distanceInMeters')

    return {
        'id': deterministic_id('garmin', start.isoformat(), display_type, duration_min),
        'source': 'garmin',
        'date': datetime.fromtimestamp(int(start_sec) + offset, tz=timezone.utc)
                        .strftime('%Y-%m-%d'),
        'startTime': start.isoformat(),
        'endTime': end.isoformat(),
        'durationMinutes': duration_min,
        'activityType': display_type,
        'inferredModalityId': _GARMIN_ACTIVITY_MAP.get(activity_type),
        'heartRate': {
            'avg': summary.get('averageHeartRateInBeatsPerMinute'),
            'max': summary.get('maxHeartRateInBeatsPerMinute'),
            'min': None,
            'samples': [],
        },
        'calories': summary.get('activeKilocalories'),
        'distance': ({'value': round(float(distance_m) / 1000, 3), 'unit': 'km'}
                     if distance_m else None),
        'elevation': ({'gain': round(float(summary['totalElevationGainInMeters'])),
                       'loss': round(float(summary.get('totalElevationLossInMeters') or 0))}
                      if summary.get('totalElevationGainInMeters') else None),
        'gpsTrack': None,
        'rawData': {'garminSummaryId': summary.get('summaryId'),
                    'activityType': activity_type},
    }
